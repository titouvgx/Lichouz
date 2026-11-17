-- ============================================================
-- Migration 30 : étoiles (v2.2.0, V2 « fun UX »)
-- ============================================================
-- Chacun note une recette qu'il peut lire, de 1 à 5 étoiles, une fois (modifiable).
-- Le détail des votes est PRIVÉ (on ne relit que les siens) ; tout le monde voit la
-- moyenne et le nombre de votes des recettes qu'il peut lire (recipe_rating_stats).
-- Contrôle : supabase/tests/controle_30_etoiles.sql. Idempotente.
-- ============================================================

CREATE TABLE IF NOT EXISTS public.recipe_ratings (
  id          uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  recipe_id   uuid        NOT NULL REFERENCES public.recipes(id) ON DELETE CASCADE,
  profile_id  uuid        NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  stars       smallint    NOT NULL CHECK (stars BETWEEN 1 AND 5),
  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT uq_recipe_rating UNIQUE (recipe_id, profile_id)
);
CREATE INDEX IF NOT EXISTS idx_recipe_ratings_recipe ON public.recipe_ratings(recipe_id);
COMMENT ON TABLE public.recipe_ratings IS 'Notes (1 à 5 étoiles) : votes privés, moyenne visible via recipe_rating_stats — migration 30.';

ALTER TABLE public.recipe_ratings ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "ratings_select" ON public.recipe_ratings;
DROP POLICY IF EXISTS "ratings_insert" ON public.recipe_ratings;
DROP POLICY IF EXISTS "ratings_update" ON public.recipe_ratings;
DROP POLICY IF EXISTS "ratings_delete" ON public.recipe_ratings;
CREATE POLICY "ratings_select" ON public.recipe_ratings FOR SELECT
  USING (profile_id = auth.uid());
CREATE POLICY "ratings_insert" ON public.recipe_ratings FOR INSERT
  WITH CHECK (profile_id = auth.uid() AND public.is_member() AND public.can_read_recipe(recipe_id));
CREATE POLICY "ratings_update" ON public.recipe_ratings FOR UPDATE
  USING (profile_id = auth.uid())
  WITH CHECK (profile_id = auth.uid() AND public.is_member() AND public.can_read_recipe(recipe_id));
CREATE POLICY "ratings_delete" ON public.recipe_ratings FOR DELETE
  USING (profile_id = auth.uid());

-- Une note ne change ni de recette ni de personne ; dates écrites par la base
CREATE OR REPLACE FUNCTION public.guard_recipe_rating()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
BEGIN
  IF TG_OP = 'UPDATE' THEN
    NEW.recipe_id := OLD.recipe_id;
    NEW.profile_id := OLD.profile_id;
    NEW.created_at := OLD.created_at;
  ELSE
    NEW.created_at := now();
  END IF;
  NEW.updated_at := now();
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_guard_recipe_rating ON public.recipe_ratings;
CREATE TRIGGER trg_guard_recipe_rating BEFORE INSERT OR UPDATE ON public.recipe_ratings
  FOR EACH ROW EXECUTE FUNCTION public.guard_recipe_rating();
REVOKE ALL ON FUNCTION public.guard_recipe_rating() FROM PUBLIC, anon, authenticated;

-- Moyenne + nombre de votes, seulement pour les recettes que l'on peut lire (50 au plus par appel)
CREATE OR REPLACE FUNCTION public.recipe_rating_stats(p_recipes uuid[])
RETURNS TABLE (recipe_id uuid, average numeric, votes integer)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT n.recipe_id, round(avg(n.stars)::numeric, 1), count(*)::integer
    FROM public.recipe_ratings n
   WHERE n.recipe_id = ANY (p_recipes[1:50])
     AND public.can_read_recipe(n.recipe_id)
   GROUP BY n.recipe_id
$$;
REVOKE ALL ON FUNCTION public.recipe_rating_stats(uuid[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.recipe_rating_stats(uuid[]) TO authenticated;

-- Mes données : les notes données font partie de l'export
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
