-- ============================================================
-- Migration 31 : commentaires des recettes (v2.6.0)
-- ============================================================
-- Un commentaire est visible par SA FAMILLE seulement (tous les foyers de la
-- super-famille de son auteur), et seulement par ceux qui lisent la recette.
-- Sur une recette du catalogue, chaque famille ne voit que ses commentaires.
-- Supprimer : l'auteur, ou un admin du foyer de l'auteur. Pas de modification
-- (on supprime et on réécrit). 500 caractères, 30 par heure et par personne.
-- Auteur, famille et date écrits par la base. Effacés avec le compte.
-- Nouvelle version des conditions (2026-11-18) : la famille voit désormais
-- les commentaires → tout le monde ré-accepte une fois.
-- Contrôle : supabase/tests/controle_31_commentaires.sql. Idempotente.
-- ============================================================

CREATE TABLE IF NOT EXISTS public.recipe_comments (
  id              uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  recipe_id       uuid        NOT NULL REFERENCES public.recipes(id) ON DELETE CASCADE,
  author_id       uuid        NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  super_family_id uuid        NOT NULL REFERENCES public.super_families(id) ON DELETE CASCADE,
  body            text        NOT NULL CHECK (char_length(btrim(body)) BETWEEN 1 AND 500),
  created_at      timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_recipe_comments_recipe ON public.recipe_comments(recipe_id, super_family_id, created_at);
CREATE INDEX IF NOT EXISTS idx_recipe_comments_author ON public.recipe_comments(author_id, created_at);
COMMENT ON TABLE public.recipe_comments IS
  'Commentaires des recettes, visibles dans la famille de l''auteur seulement — migration 31.';

ALTER TABLE public.recipe_comments ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "comments_select" ON public.recipe_comments;
DROP POLICY IF EXISTS "comments_insert" ON public.recipe_comments;
DROP POLICY IF EXISTS "comments_delete" ON public.recipe_comments;

CREATE POLICY "comments_select" ON public.recipe_comments FOR SELECT
  USING (super_family_id = public.my_super_family_id() AND public.can_read_recipe(recipe_id));

CREATE POLICY "comments_insert" ON public.recipe_comments FOR INSERT
  WITH CHECK (
    author_id = auth.uid()
    AND public.is_member()
    AND super_family_id = public.my_super_family_id()
    AND public.can_read_recipe(recipe_id)
  );

-- L'auteur, ou un admin du foyer de l'auteur (même foyer que moi)
CREATE POLICY "comments_delete" ON public.recipe_comments FOR DELETE
  USING (
    author_id = auth.uid()
    OR (
      public.is_admin()
      AND EXISTS (SELECT 1 FROM public.profiles a
                   WHERE a.id = recipe_comments.author_id AND a.family_id = public.user_family_id())
    )
  );
-- Pas de règle UPDATE : un commentaire ne se modifie pas.

-- Auteur, famille et date forcés ; 30 commentaires par heure et par personne
CREATE OR REPLACE FUNCTION public.guard_recipe_comment()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
BEGIN
  -- Une personne connectée : tout est forcé. La base elle-même (administration,
  -- banc de tests) peut écrire pour quelqu'un ; anon n'a aucun droit d'écriture.
  IF auth.uid() IS NOT NULL THEN
    NEW.author_id := auth.uid();
    NEW.super_family_id := public.my_super_family_id();
    IF NEW.super_family_id IS NULL THEN
      RAISE EXCEPTION 'Connexion requise' USING ERRCODE = '42501';
    END IF;
  END IF;
  NEW.created_at := now();
  NEW.body := btrim(NEW.body);
  IF (SELECT count(*) FROM public.recipe_comments c
       WHERE c.author_id = NEW.author_id AND c.created_at > now() - interval '1 hour') >= 30 THEN
    RAISE EXCEPTION 'Trop de commentaires : réessaie dans un moment' USING ERRCODE = 'P0001';
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_guard_recipe_comment ON public.recipe_comments;
CREATE TRIGGER trg_guard_recipe_comment BEFORE INSERT ON public.recipe_comments
  FOR EACH ROW EXECUTE FUNCTION public.guard_recipe_comment();
REVOKE ALL ON FUNCTION public.guard_recipe_comment() FROM PUBLIC, anon, authenticated;

-- Lecture avec le prénom de l'auteur (les profils des autres foyers ne sont pas
-- lisibles directement) : mêmes conditions que la règle SELECT.
CREATE OR REPLACE FUNCTION public.recipe_comments_list(p_recipe uuid)
RETURNS TABLE (id uuid, body text, created_at timestamptz, author_id uuid,
               author_name text, author_pseudo text, mine boolean, can_delete boolean)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT c.id, c.body, c.created_at, c.author_id,
         a.display_name, a.pseudo,
         c.author_id = auth.uid(),
         c.author_id = auth.uid() OR (public.is_admin() AND a.family_id = public.user_family_id())
    FROM public.recipe_comments c
    JOIN public.profiles a ON a.id = c.author_id
   WHERE c.recipe_id = p_recipe
     AND c.super_family_id = public.my_super_family_id()
     AND public.can_read_recipe(p_recipe)
   ORDER BY c.created_at
   LIMIT 200
$$;
REVOKE ALL ON FUNCTION public.recipe_comments_list(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.recipe_comments_list(uuid) TO authenticated;

-- ── Nouvelle version des conditions ──
CREATE OR REPLACE FUNCTION public.current_terms_version()
RETURNS text LANGUAGE sql IMMUTABLE SET search_path = '' AS $$ SELECT '2026-11-18'::text $$;
GRANT EXECUTE ON FUNCTION public.current_terms_version() TO authenticated;
REVOKE ALL ON FUNCTION public.current_terms_version() FROM anon;

-- ── Mes données : les commentaires écrits font partie de l'export ──
CREATE OR REPLACE FUNCTION public.export_my_data()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  me uuid := auth.uid();
BEGIN
  IF me IS NULL OR NOT EXISTS (SELECT 1 FROM public.profiles WHERE id = me) THEN
    RAISE EXCEPTION 'Connexion requise' USING ERRCODE = '42501';
  END IF;
  RETURN jsonb_build_object(
    'genere_le', now(),
    'compte', (SELECT jsonb_build_object('id', u.id, 'email', u.email, 'cree_le', u.created_at,
                                          'derniere_connexion', u.last_sign_in_at)
                 FROM auth.users u WHERE u.id = me),
    'profil', (SELECT jsonb_build_object('prenom', p.display_name, 'pseudo', p.pseudo, 'role', p.role,
                                          'foyer', f.name, 'cree_le', p.created_at,
                                          'compte_desactive', EXISTS (SELECT 1 FROM private.disabled_accounts d WHERE d.user_id = me))
                 FROM public.profiles p JOIN public.families f ON f.id = p.family_id WHERE p.id = me),
    'conditions_acceptees', coalesce((SELECT jsonb_agg(jsonb_build_object('version', t.version, 'tranche_age', t.age_group,
                                          'acceptees_le', t.accepted_at, 'accord_parent_le', t.parent_confirmed_at) ORDER BY t.accepted_at)
                 FROM public.terms_acceptances t WHERE t.profile_id = me), '[]'::jsonb),
    'accords_parentaux_donnes', coalesce((SELECT jsonb_agg(jsonb_build_object('enfant', p.display_name, 'le', t.parent_confirmed_at))
                 FROM public.terms_acceptances t JOIN public.profiles p ON p.id = t.profile_id WHERE t.parent_id = me), '[]'::jsonb),
    'recettes_ecrites', coalesce((SELECT jsonb_agg(jsonb_build_object(
                    'titre', r.title, 'visibilite', r.visibility, 'creee_le', r.created_at, 'archivee_le', r.archived_at,
                    'ingredients', (SELECT coalesce(jsonb_agg(jsonb_build_object('nom', i.name, 'quantite', i.quantity, 'unite', i.unit) ORDER BY i.position), '[]'::jsonb)
                                      FROM public.recipe_ingredients i WHERE i.recipe_id = r.id),
                    'etapes', (SELECT coalesce(jsonb_agg(s.instruction ORDER BY s.position), '[]'::jsonb)
                                 FROM public.recipe_steps s WHERE s.recipe_id = r.id)) ORDER BY r.created_at)
                 FROM public.recipes r WHERE r.created_by = me), '[]'::jsonb),
    'repas_cuisines', coalesce((SELECT jsonb_agg(jsonb_build_object('semaine', mp.week_start, 'jour', ms.day_of_week,
                                          'repas', ms.meal_type, 'recette', r.title) ORDER BY mp.week_start, ms.day_of_week)
                 FROM public.meal_slots ms JOIN public.meal_plans mp ON mp.id = ms.meal_plan_id
                 JOIN public.recipes r ON r.id = ms.recipe_id WHERE ms.cook_id = me), '[]'::jsonb),
    'articles_coches', coalesce((SELECT jsonb_agg(jsonb_build_object('article', it.name, 'le', it.checked_at) ORDER BY it.checked_at)
                 FROM public.shopping_list_items it WHERE it.checked_by = me), '[]'::jsonb),
    'evenements_crees', coalesce((SELECT jsonb_agg(jsonb_build_object('titre', e.title, 'date', e.starts_on, 'lieu', e.location,
                                          'theme', e.theme, 'notes', e.notes, 'playlist', e.playlist_url) ORDER BY e.starts_on)
                 FROM public.events e WHERE e.created_by = me), '[]'::jsonb),
    'reponses_evenements', coalesce((SELECT jsonb_agg(jsonb_build_object('evenement', e.title, 'reponse', v.answer, 'le', v.updated_at))
                 FROM public.event_rsvps v JOIN public.events e ON e.id = v.event_id WHERE v.profile_id = me), '[]'::jsonb),
    'taches_evenements', coalesce((SELECT jsonb_agg(jsonb_build_object('evenement', e.title, 'tache', t.label))
                 FROM public.event_tasks t JOIN public.events e ON e.id = t.event_id WHERE me = ANY (t.volunteers)), '[]'::jsonb),
    'semaines_types_creees', coalesce((SELECT jsonb_agg(w.name) FROM public.week_templates w WHERE w.created_by = me), '[]'::jsonb),
    'invitations_creees', coalesce((SELECT jsonb_agg(jsonb_build_object('libelle', i.label, 'adresse_reservee', i.email_hint,
                                          'creee_le', i.created_at, 'utilisee_le', i.used_at, 'annulee_le', i.revoked_at) ORDER BY i.created_at)
                 FROM public.invitations i WHERE i.created_by = me), '[]'::jsonb),
    'notes_donnees', coalesce((SELECT jsonb_agg(jsonb_build_object('recette', r.title, 'etoiles', n.stars, 'le', n.updated_at) ORDER BY n.updated_at)
                 FROM public.recipe_ratings n JOIN public.recipes r ON r.id = n.recipe_id WHERE n.profile_id = me), '[]'::jsonb),
    'commentaires_ecrits', coalesce((SELECT jsonb_agg(jsonb_build_object('recette', r.title, 'texte', c.body, 'le', c.created_at) ORDER BY c.created_at)
                 FROM public.recipe_comments c JOIN public.recipes r ON r.id = c.recipe_id WHERE c.author_id = me), '[]'::jsonb),
    'idees_et_retours', coalesce((SELECT jsonb_agg(jsonb_build_object('type', fb.kind, 'message', fb.message, 'statut', fb.status,
                                          'le', fb.created_at) ORDER BY fb.created_at)
                 FROM public.feedback fb WHERE fb.user_id = me), '[]'::jsonb),
    'journal_erreurs', coalesce((SELECT jsonb_agg(jsonb_build_object('message', ae.message, 'page', ae.route,
                                          'version', ae.app_version, 'le', ae.created_at) ORDER BY ae.created_at)
                 FROM public.app_errors ae WHERE ae.user_id = me), '[]'::jsonb)
  );
END;
$$;
REVOKE ALL ON FUNCTION public.export_my_data() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.export_my_data() TO authenticated;
