-- ═══════════════════════════════════════════════════════════════
-- Migration 22 — Archives, limites de texte, liste de courses (v1.4.0)
-- ═══════════════════════════════════════════════════════════════
-- 1. Recettes ARCHIVÉES au lieu de supprimées
--    Supprimer effaçait aussi les créneaux de toutes les familles (cascade).
--    Désormais : recipes.archived_at (NULL = active). Une recette archivée
--    disparaît des listes et de la recherche (côté appli) mais reste lisible :
--    plannings, historique et listes de courses ne bougent pas.
--    Archiver / restaurer : mêmes droits que l'ancienne suppression
--    (admin de la famille propriétaire, hors catalogue ; ou super-admin).
--    Plus AUCUN DELETE direct sur recipes depuis l'API (même super-admin) :
--    une vraie suppression se fait dans le SQL Editor.
-- 2. Limites de longueur (choix « larges » du 15/11/2026) :
--    titre 120 · ingrédient 80 · unité 20 · étape 1 000 · 60 ingrédients et
--    40 étapes par recette · article de liste 80 · quantité d'article 120.
--    Les données existantes respectent toutes ces limites (vérifié le
--    15/11/2026 en lecture sur la prod : max 40 / 28 / 10 / 366 / 17 / 12).
-- 3. Liste de courses :
--    - shopping_list_items.source_recipe_ids : TOUTES les recettes qui
--      demandent l'article (source_recipe_id = la première, gardée).
--    - replace_planned_items() : recalcul de la liste en UNE transaction
--      (avant : suppression puis insertion, une coupure réseau entre les
--      deux vidait la liste). SECURITY INVOKER : les règles RLS s'appliquent.
-- Contrôle : supabase/tests/controle_22_archives_limites_liste.sql

-- ── 1. Archives ──────────────────────────────────────────────
ALTER TABLE public.recipes ADD COLUMN IF NOT EXISTS archived_at timestamptz;
COMMENT ON COLUMN public.recipes.archived_at IS
  'Date d''archivage (NULL = recette active). Archivée = masquée des listes, gardée dans les plannings.';
CREATE INDEX IF NOT EXISTS idx_recipes_active ON public.recipes(family_id) WHERE archived_at IS NULL;

DROP POLICY IF EXISTS "recipes_delete" ON public.recipes;

-- Garde : archiver / restaurer = admin de la famille (hors catalogue) ou super-admin.
-- Le reste de la garde est repris tel quel de la migration 19.
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
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION public.guard_recipe_write() FROM PUBLIC, anon, authenticated;

-- ── 2. Limites de longueur ───────────────────────────────────
ALTER TABLE public.recipes DROP CONSTRAINT IF EXISTS recipes_title_length;
ALTER TABLE public.recipes ADD CONSTRAINT recipes_title_length
  CHECK (char_length(title) BETWEEN 1 AND 120);
ALTER TABLE public.recipe_ingredients DROP CONSTRAINT IF EXISTS recipe_ingredients_text_length;
ALTER TABLE public.recipe_ingredients ADD CONSTRAINT recipe_ingredients_text_length
  CHECK (char_length(name) BETWEEN 1 AND 80 AND (unit IS NULL OR char_length(unit) <= 20));
ALTER TABLE public.recipe_steps DROP CONSTRAINT IF EXISTS recipe_steps_text_length;
ALTER TABLE public.recipe_steps ADD CONSTRAINT recipe_steps_text_length
  CHECK (char_length(instruction) BETWEEN 1 AND 1000);
ALTER TABLE public.shopping_list_items DROP CONSTRAINT IF EXISTS shopping_list_items_text_length;
ALTER TABLE public.shopping_list_items ADD CONSTRAINT shopping_list_items_text_length
  CHECK (char_length(name) BETWEEN 1 AND 80 AND (quantity IS NULL OR char_length(quantity) <= 120));

-- Nombre d'ingrédients / d'étapes par recette. Un déclencheur BEFORE ROW voit
-- les lignes déjà insérées par la même commande : une insertion groupée de
-- 61 ingrédients est donc bien refusée à la 61e.
CREATE OR REPLACE FUNCTION public.guard_recipe_children_count()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_max int := CASE TG_TABLE_NAME WHEN 'recipe_ingredients' THEN 60 ELSE 40 END;
  v_n   int;
BEGIN
  IF TG_TABLE_NAME = 'recipe_ingredients' THEN
    SELECT count(*) INTO v_n FROM public.recipe_ingredients WHERE recipe_id = NEW.recipe_id;
  ELSE
    SELECT count(*) INTO v_n FROM public.recipe_steps WHERE recipe_id = NEW.recipe_id;
  END IF;
  IF v_n >= v_max THEN
    RAISE EXCEPTION 'Trop de lignes : % au maximum par recette', v_max USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION public.guard_recipe_children_count() FROM PUBLIC, anon, authenticated;
DROP TRIGGER IF EXISTS trg_recipe_ingredients_count ON public.recipe_ingredients;
CREATE TRIGGER trg_recipe_ingredients_count
  BEFORE INSERT ON public.recipe_ingredients
  FOR EACH ROW EXECUTE FUNCTION public.guard_recipe_children_count();
DROP TRIGGER IF EXISTS trg_recipe_steps_count ON public.recipe_steps;
CREATE TRIGGER trg_recipe_steps_count
  BEFORE INSERT ON public.recipe_steps
  FOR EACH ROW EXECUTE FUNCTION public.guard_recipe_children_count();

-- ── 3a. Recettes d'origine d'un article ──────────────────────
ALTER TABLE public.shopping_list_items
  ADD COLUMN IF NOT EXISTS source_recipe_ids uuid[] NOT NULL DEFAULT '{}';
ALTER TABLE public.shopping_list_items DROP CONSTRAINT IF EXISTS shopping_list_items_sources_count;
ALTER TABLE public.shopping_list_items ADD CONSTRAINT shopping_list_items_sources_count
  CHECK (cardinality(source_recipe_ids) <= 50);
UPDATE public.shopping_list_items
   SET source_recipe_ids = ARRAY[source_recipe_id]
 WHERE source_recipe_id IS NOT NULL AND source_recipe_ids = '{}';

-- Garde des articles : reprise de la migration 17 + chaque recette d'origine
-- de la liste doit être lisible (sinon on pourrait sonder des recettes d'autrui).
CREATE OR REPLACE FUNCTION public.guard_item_checked_by()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
BEGIN
  IF NEW.source_recipe_id IS NOT NULL AND auth.uid() IS NOT NULL AND NOT public.is_super_admin()
     AND (TG_OP = 'INSERT' OR NEW.source_recipe_id IS DISTINCT FROM OLD.source_recipe_id)
     AND NOT public.can_read_recipe(NEW.source_recipe_id) THEN
    RAISE EXCEPTION 'Recette d''origine inaccessible' USING ERRCODE = '42501';
  END IF;
  IF cardinality(NEW.source_recipe_ids) > 0 AND auth.uid() IS NOT NULL AND NOT public.is_super_admin()
     AND (TG_OP = 'INSERT' OR NEW.source_recipe_ids IS DISTINCT FROM OLD.source_recipe_ids)
     AND EXISTS (SELECT 1 FROM unnest(NEW.source_recipe_ids) AS r(id) WHERE NOT public.can_read_recipe(r.id)) THEN
    RAISE EXCEPTION 'Recette d''origine inaccessible' USING ERRCODE = '42501';
  END IF;
  IF NEW.checked_by IS NOT NULL AND auth.uid() IS NOT NULL AND NOT public.is_super_admin()
     AND (TG_OP = 'INSERT' OR NEW.checked_by IS DISTINCT FROM OLD.checked_by)
     AND NOT EXISTS (
       SELECT 1 FROM public.profiles p JOIN public.shopping_lists sl ON sl.family_id = p.family_id
       WHERE p.id = NEW.checked_by AND sl.id = NEW.shopping_list_id
     ) THEN
    RAISE EXCEPTION '« Coché par » doit être un membre du foyer' USING ERRCODE = '42501';
  END IF;
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION public.guard_item_checked_by() FROM PUBLIC, anon, authenticated;

-- ── 3b. Recalcul de la liste en une transaction ──────────────
-- p_items : tableau JSON des articles issus du planning, calculés par l'appli
-- (buildRegeneratedItems). Les articles ajoutés à la main ne sont pas touchés.
-- SECURITY INVOKER : la mise à jour de la liste passe par la règle
-- shopping_lists_update (famille + planning du même foyer), la suppression et
-- l'insertion par celles des articles. Liste d'un autre foyer → « introuvable ».
CREATE OR REPLACE FUNCTION public.replace_planned_items(p_list_id uuid, p_plan_id uuid, p_items jsonb)
RETURNS integer LANGUAGE plpgsql VOLATILE SECURITY INVOKER SET search_path = '' AS $$
DECLARE
  v_n int;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Connexion requise' USING ERRCODE = '42501';
  END IF;
  IF p_items IS NULL OR jsonb_typeof(p_items) <> 'array' OR jsonb_array_length(p_items) > 500 THEN
    RAISE EXCEPTION 'Articles invalides (500 au maximum)' USING ERRCODE = '22023';
  END IF;
  UPDATE public.shopping_lists SET meal_plan_id = p_plan_id
   WHERE id = p_list_id AND status = 'active';
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Liste introuvable' USING ERRCODE = '42501';
  END IF;
  DELETE FROM public.shopping_list_items WHERE shopping_list_id = p_list_id AND NOT is_extra;
  INSERT INTO public.shopping_list_items (
    shopping_list_id, name, quantity, shopping_category_id, source_recipe_id, source_recipe_ids,
    is_extra, checked, needed, checked_by, checked_at, position)
  SELECT p_list_id, x.name, x.quantity, x.shopping_category_id, x.source_recipe_id,
         coalesce(x.source_recipe_ids, '{}'), false, coalesce(x.checked, false),
         coalesce(x.needed, false), x.checked_by, x.checked_at, coalesce(x.position, 0)
    FROM jsonb_to_recordset(p_items) AS x(
      name text, quantity text, shopping_category_id uuid, source_recipe_id uuid,
      source_recipe_ids uuid[], checked boolean, needed boolean, checked_by uuid,
      checked_at timestamptz, position int);
  GET DIAGNOSTICS v_n = ROW_COUNT;
  RETURN v_n;
END;
$$;
REVOKE ALL ON FUNCTION public.replace_planned_items(uuid, uuid, jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.replace_planned_items(uuid, uuid, jsonb) TO authenticated;
