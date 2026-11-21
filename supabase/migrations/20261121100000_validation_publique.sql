-- ============================================================
-- Migration 37 : validation par l'admin des recettes rendues publiques
-- ============================================================
-- Règle (décision de Titouan, 19/11/2026, précisée le 21/11/2026) : une recette ne
-- devient visible du public QUE si le super-admin l'a validée. Les visibilités
-- « famille » (foyer) et « super_famille » (toutes nos familles) ne changent pas et ne
-- demandent aucune validation : la publication publique est une couche en plus.
--
-- Colonnes (recipes) : public_status NULL | 'en_attente' | 'validee' | 'refusee',
--   public_requested_at, public_reviewed_at, public_reviewed_by, public_refusal_reason.
-- Fonctions : request_public_publication, withdraw_public_publication,
--   review_public_recipe (super-admin), public_review_queue (super-admin).
-- Garde (base, pas seulement l'écran) :
--   - aucune écriture directe des colonnes public_* hors de ces fonctions ;
--   - une recette validée dont le contenu est modifié (recette, ingrédients, étapes)
--     repasse « en attente » et sort du public (revalidation à chaque modification) ;
--   - au plus 3 demandes en attente par auteur ;
--   - les recettes du super-admin sont publiées directement.
-- Lecture : un membre connecté lit les recettes validées et non archivées. Pas d'accès
-- anonyme (l'appli exige une connexion).
-- Contrôle : supabase/tests/controle_37_validation_publique.sql
-- ============================================================

-- ── 1. Colonnes ───────────────────────────────────────────────
ALTER TABLE public.recipes
  ADD COLUMN IF NOT EXISTS public_status         text,
  ADD COLUMN IF NOT EXISTS public_requested_at   timestamptz,
  ADD COLUMN IF NOT EXISTS public_reviewed_at    timestamptz,
  ADD COLUMN IF NOT EXISTS public_reviewed_by    uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS public_refusal_reason text;

ALTER TABLE public.recipes DROP CONSTRAINT IF EXISTS recipes_public_status_check;
ALTER TABLE public.recipes ADD CONSTRAINT recipes_public_status_check
  CHECK (public_status IS NULL OR public_status IN ('en_attente', 'validee', 'refusee'));

-- Motifs de refus : liste fermée (les libellés sont dans src/lib/publication.ts)
ALTER TABLE public.recipes DROP CONSTRAINT IF EXISTS recipes_public_reason_check;
ALTER TABLE public.recipes ADD CONSTRAINT recipes_public_reason_check
  CHECK (
    public_refusal_reason IS NULL
    OR (public_status = 'refusee'
        AND public_refusal_reason IN ('contenu_inapproprie', 'recette_incomplete',
                                      'copie_suspecte', 'photo_inadaptee', 'doublon', 'autre'))
  );

-- Le catalogue n'a pas de statut de publication (il est déjà livré avec l'appli)
ALTER TABLE public.recipes DROP CONSTRAINT IF EXISTS recipes_public_not_catalogue;
ALTER TABLE public.recipes ADD CONSTRAINT recipes_public_not_catalogue
  CHECK (public_status IS NULL OR visibility <> 'catalogue');

CREATE INDEX IF NOT EXISTS idx_recipes_public_pending
  ON public.recipes(created_by) WHERE public_status = 'en_attente';
CREATE INDEX IF NOT EXISTS idx_recipes_public_validated
  ON public.recipes(id) WHERE public_status = 'validee';

COMMENT ON COLUMN public.recipes.public_status IS
  'Publication publique : NULL (non demandée) | en_attente | validee | refusee. Modifiable seulement par les fonctions de publication.';

-- ── 2. Lecture : les recettes validées sont lisibles par tout membre ──
DROP POLICY IF EXISTS "recipes_select" ON public.recipes;
CREATE POLICY "recipes_select" ON public.recipes FOR SELECT
  USING (
    public.is_super_admin()
    OR public.is_family(family_id)
    OR (visibility = 'catalogue' AND public.is_member())
    OR (visibility = 'super_famille' AND public.family_super_family(family_id) = public.my_super_family_id())
    OR (public_status = 'validee' AND archived_at IS NULL AND public.is_member())
  );

CREATE OR REPLACE FUNCTION public.can_read_recipe(rid uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.recipes r
    WHERE r.id = rid AND (
      public.is_super_admin()
      OR public.is_family(r.family_id)
      OR (r.visibility = 'catalogue' AND public.is_member())
      OR (r.visibility = 'super_famille'
          AND public.family_super_family(r.family_id) = public.my_super_family_id())
      OR (r.public_status = 'validee' AND r.archived_at IS NULL AND public.is_member())
    )
  )
$$;

-- ── 3. Garde d'écriture (reprend la migration 22 + règles de publication) ──
-- Les fonctions de publication lèvent le drapeau transactionnel lichouz.public_op ;
-- un client ne peut pas le poser (il n'a aucun accès SQL libre, seulement l'API).
CREATE OR REPLACE FUNCTION public.guard_recipe_write()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
BEGIN
  IF auth.uid() IS NULL OR public.is_super_admin() THEN
    RETURN NEW;
  END IF;
  IF TG_OP = 'INSERT' THEN
    IF NEW.created_by IS DISTINCT FROM auth.uid() THEN
      RAISE EXCEPTION 'Auteur de la recette : soi-même uniquement' USING ERRCODE = '42501';
    END IF;
    IF NEW.archived_at IS NOT NULL THEN
      RAISE EXCEPTION 'Une nouvelle recette ne peut pas être archivée' USING ERRCODE = '42501';
    END IF;
    IF NEW.public_status IS NOT NULL OR NEW.public_requested_at IS NOT NULL
       OR NEW.public_reviewed_at IS NOT NULL OR NEW.public_reviewed_by IS NOT NULL
       OR NEW.public_refusal_reason IS NOT NULL THEN
      RAISE EXCEPTION 'Publication publique : passer par la demande de validation' USING ERRCODE = '42501';
    END IF;
    RETURN NEW;
  END IF;
  IF NEW.family_id IS DISTINCT FROM OLD.family_id
     OR (NEW.created_by IS DISTINCT FROM OLD.created_by
         AND NOT (NEW.created_by IS NULL
                  AND NOT EXISTS (SELECT 1 FROM auth.users u WHERE u.id = OLD.created_by))) THEN
    RAISE EXCEPTION 'Modification interdite : famille ou auteur de la recette' USING ERRCODE = '42501';
  END IF;
  IF NEW.archived_at IS DISTINCT FROM OLD.archived_at
     AND NOT (public.is_admin() AND public.is_family(OLD.family_id) AND OLD.visibility <> 'catalogue') THEN
    RAISE EXCEPTION 'Seul un administrateur de la famille peut archiver ou restaurer cette recette'
      USING ERRCODE = '42501';
  END IF;
  IF OLD.visibility = 'super_famille' AND NEW.visibility = 'famille' AND EXISTS (
    SELECT 1 FROM public.meal_slots s JOIN public.meal_plans mp ON mp.id = s.meal_plan_id
    WHERE s.recipe_id = NEW.id AND mp.family_id <> NEW.family_id
  ) THEN
    RAISE EXCEPTION 'Cette recette est au planning d''une autre famille : elle doit rester partagée'
      USING ERRCODE = 'check_violation';
  END IF;
  -- Publication publique
  IF coalesce(current_setting('lichouz.public_op', true), '') <> '1' THEN
    IF NEW.public_status IS DISTINCT FROM OLD.public_status
       OR NEW.public_requested_at IS DISTINCT FROM OLD.public_requested_at
       OR NEW.public_reviewed_at IS DISTINCT FROM OLD.public_reviewed_at
       OR NEW.public_reviewed_by IS DISTINCT FROM OLD.public_reviewed_by
       OR NEW.public_refusal_reason IS DISTINCT FROM OLD.public_refusal_reason THEN
      RAISE EXCEPTION 'Publication publique : passer par la demande de validation' USING ERRCODE = '42501';
    END IF;
    -- Contenu modifié sur une recette validée : retour en attente (revalidation)
    IF OLD.public_status = 'validee' AND (
         NEW.title IS DISTINCT FROM OLD.title
         OR NEW.category_id IS DISTINCT FROM OLD.category_id
         OR NEW.prep_time_min IS DISTINCT FROM OLD.prep_time_min
         OR NEW.default_portions IS DISTINCT FROM OLD.default_portions
         OR NEW.image_url IS DISTINCT FROM OLD.image_url
         OR NEW.diets IS DISTINCT FROM OLD.diets
         OR NEW.origin IS DISTINCT FROM OLD.origin
         OR NEW.themes IS DISTINCT FROM OLD.themes
         OR NEW.budget IS DISTINCT FROM OLD.budget) THEN
      NEW.public_status := 'en_attente';
      NEW.public_requested_at := now();
      NEW.public_reviewed_at := NULL;
      NEW.public_reviewed_by := NULL;
    END IF;
  END IF;
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION public.guard_recipe_write() FROM PUBLIC, anon, authenticated;

-- Ingrédients et étapes modifiés par un non super-admin : la recette validée repasse en attente
CREATE OR REPLACE FUNCTION public.requeue_public_recipe()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_rid uuid := coalesce(NEW.recipe_id, OLD.recipe_id);
BEGIN
  IF auth.uid() IS NULL OR public.is_super_admin() THEN
    RETURN NULL;
  END IF;
  PERFORM set_config('lichouz.public_op', '1', true);
  UPDATE public.recipes
     SET public_status = 'en_attente', public_requested_at = now(),
         public_reviewed_at = NULL, public_reviewed_by = NULL
   WHERE id = v_rid AND public_status = 'validee';
  PERFORM set_config('lichouz.public_op', '', true);
  RETURN NULL;
END;
$$;
REVOKE ALL ON FUNCTION public.requeue_public_recipe() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trg_requeue_public_ingredients ON public.recipe_ingredients;
CREATE TRIGGER trg_requeue_public_ingredients
  AFTER INSERT OR UPDATE OR DELETE ON public.recipe_ingredients
  FOR EACH ROW EXECUTE FUNCTION public.requeue_public_recipe();
DROP TRIGGER IF EXISTS trg_requeue_public_steps ON public.recipe_steps;
CREATE TRIGGER trg_requeue_public_steps
  AFTER INSERT OR UPDATE OR DELETE ON public.recipe_steps
  FOR EACH ROW EXECUTE FUNCTION public.requeue_public_recipe();

-- ── 4. Fonctions de publication ───────────────────────────────

-- Demander la publication publique (auteur). Le super-admin publie directement.
CREATE OR REPLACE FUNCTION public.request_public_publication(p_recipe uuid)
RETURNS text LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_uid uuid := auth.uid();
  r     public.recipes%ROWTYPE;
  v_new text;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Connexion requise' USING ERRCODE = '42501';
  END IF;
  SELECT * INTO r FROM public.recipes WHERE id = p_recipe FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Recette introuvable' USING ERRCODE = 'P0002';
  END IF;
  IF r.created_by IS DISTINCT FROM v_uid AND NOT public.is_super_admin() THEN
    RAISE EXCEPTION 'Seul l''auteur peut demander la publication de sa recette' USING ERRCODE = '42501';
  END IF;
  IF r.visibility = 'catalogue' THEN
    RAISE EXCEPTION 'Une recette du catalogue ne se publie pas' USING ERRCODE = 'check_violation';
  END IF;
  IF r.archived_at IS NOT NULL THEN
    RAISE EXCEPTION 'Restaure la recette avant de demander sa publication' USING ERRCODE = 'check_violation';
  END IF;
  IF r.public_status IN ('en_attente', 'validee') THEN
    RAISE EXCEPTION 'Cette recette est déjà publique ou en attente de validation' USING ERRCODE = 'check_violation';
  END IF;

  IF public.is_super_admin() AND r.created_by = v_uid THEN
    v_new := 'validee'; -- les recettes du super-admin sont publiées directement
  ELSE
    -- le verrou évite de dépasser la limite avec deux demandes simultanées
    PERFORM pg_advisory_xact_lock(hashtext('lichouz.public_request:' || v_uid::text));
    IF (SELECT count(*) FROM public.recipes
         WHERE created_by = v_uid AND public_status = 'en_attente' AND archived_at IS NULL) >= 3 THEN
      RAISE EXCEPTION 'Tu as déjà 3 demandes en attente : attends qu''elles soient traitées'
        USING ERRCODE = 'check_violation';
    END IF;
    v_new := 'en_attente';
  END IF;

  PERFORM set_config('lichouz.public_op', '1', true);
  UPDATE public.recipes
     SET public_status = v_new, public_requested_at = now(),
         public_reviewed_at = CASE WHEN v_new = 'validee' THEN now() END,
         public_reviewed_by = CASE WHEN v_new = 'validee' THEN v_uid END,
         public_refusal_reason = NULL
   WHERE id = p_recipe;
  PERFORM set_config('lichouz.public_op', '', true);
  RETURN v_new;
END;
$$;

-- Retirer sa demande, ou dépublier (auteur ou super-admin). Les copies déjà faites restent.
CREATE OR REPLACE FUNCTION public.withdraw_public_publication(p_recipe uuid)
RETURNS void LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_uid uuid := auth.uid();
  r     public.recipes%ROWTYPE;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Connexion requise' USING ERRCODE = '42501';
  END IF;
  SELECT * INTO r FROM public.recipes WHERE id = p_recipe FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Recette introuvable' USING ERRCODE = 'P0002';
  END IF;
  IF r.created_by IS DISTINCT FROM v_uid AND NOT public.is_super_admin() THEN
    RAISE EXCEPTION 'Seul l''auteur ou l''administrateur peut dépublier cette recette' USING ERRCODE = '42501';
  END IF;
  IF r.public_status IS NULL THEN
    RETURN;
  END IF;
  PERFORM set_config('lichouz.public_op', '1', true);
  UPDATE public.recipes
     SET public_status = NULL, public_requested_at = NULL, public_reviewed_at = NULL,
         public_reviewed_by = NULL, public_refusal_reason = NULL
   WHERE id = p_recipe;
  PERFORM set_config('lichouz.public_op', '', true);
END;
$$;

-- Valider ou refuser (super-admin seulement)
CREATE OR REPLACE FUNCTION public.review_public_recipe(p_recipe uuid, p_approve boolean, p_reason text DEFAULT NULL)
RETURNS void LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_uid    uuid := auth.uid();
  v_status text;
BEGIN
  IF v_uid IS NULL OR NOT public.is_super_admin() THEN
    RAISE EXCEPTION 'Réservé à l''administrateur' USING ERRCODE = '42501';
  END IF;
  SELECT public_status INTO v_status FROM public.recipes WHERE id = p_recipe FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Recette introuvable' USING ERRCODE = 'P0002';
  END IF;
  IF v_status IS DISTINCT FROM 'en_attente' THEN
    RAISE EXCEPTION 'Cette recette n''est pas en attente de validation' USING ERRCODE = 'check_violation';
  END IF;
  IF NOT p_approve AND (p_reason IS NULL OR p_reason NOT IN
      ('contenu_inapproprie', 'recette_incomplete', 'copie_suspecte', 'photo_inadaptee', 'doublon', 'autre')) THEN
    RAISE EXCEPTION 'Motif de refus obligatoire (liste fermée)' USING ERRCODE = 'check_violation';
  END IF;
  PERFORM set_config('lichouz.public_op', '1', true);
  UPDATE public.recipes
     SET public_status = CASE WHEN p_approve THEN 'validee' ELSE 'refusee' END,
         public_reviewed_at = now(), public_reviewed_by = v_uid,
         public_refusal_reason = CASE WHEN p_approve THEN NULL ELSE p_reason END
   WHERE id = p_recipe;
  PERFORM set_config('lichouz.public_op', '', true);
END;
$$;

-- File d'attente de l'administration (super-admin seulement), la plus ancienne d'abord
CREATE OR REPLACE FUNCTION public.public_review_queue()
RETURNS TABLE (recipe_id uuid, title text, image_url text, author_pseudo text, requested_at timestamptz)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
BEGIN
  IF auth.uid() IS NULL OR NOT public.is_super_admin() THEN
    RAISE EXCEPTION 'Réservé à l''administrateur' USING ERRCODE = '42501';
  END IF;
  RETURN QUERY
    SELECT r.id, r.title, r.image_url, p.pseudo, r.public_requested_at
      FROM public.recipes r
      LEFT JOIN public.profiles p ON p.id = r.created_by
     WHERE r.public_status = 'en_attente' AND r.archived_at IS NULL
     ORDER BY r.public_requested_at ASC;
END;
$$;

REVOKE ALL ON FUNCTION public.request_public_publication(uuid)             FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.withdraw_public_publication(uuid)            FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.review_public_recipe(uuid, boolean, text)    FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.public_review_queue()                        FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.request_public_publication(uuid)          TO authenticated;
GRANT EXECUTE ON FUNCTION public.withdraw_public_publication(uuid)         TO authenticated;
GRANT EXECUTE ON FUNCTION public.review_public_recipe(uuid, boolean, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.public_review_queue()                     TO authenticated;
