-- ============================================================
-- Migration 32 : succès / trophées (v2.7.0)
-- ============================================================
-- 40 trophées (19 évolutifs à 3 paliers + 21 secrets), CALCULÉS PAR LA BASE à
-- partir de ce que chacun fait dans l'appli (déclaratif : « cuisiné » = un repas
-- de la Semaine dont le jour est passé et où « Qui cuisine ? » = moi, restes exclus).
--   • achievement_tiers()        : seuils (même liste que src/lib/succes.ts, test qui compare)
--   • my_achievements()          : ma progression + mes trophées obtenus
--   • refresh_my_achievements()  : enregistre les paliers atteints, renvoie les NOUVEAUX
--   • user_achievements          : trophées obtenus (lecture : soi seul ; écriture : la base seule)
--   • cook_sessions              : temps passé en mode « En cuisine » (Toque d'or)
--   • booster_openings           : boosters ouverts et cartes obtenues (Accro, Collectionneur)
-- Visibles par soi seulement (pas de classement pour l'instant). Effacés avec le compte.
-- Nouvelle version des conditions (2026-11-19) → tout le monde ré-accepte une fois.
-- Contrôle : supabase/tests/controle_32_succes.sql. Idempotente.
-- ============================================================

-- ── Trophées obtenus ──
CREATE TABLE IF NOT EXISTS public.user_achievements (
  profile_id  uuid        NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  achievement text        NOT NULL CHECK (achievement ~ '^[a-z_]{2,30}$'),
  tier        smallint    NOT NULL CHECK (tier BETWEEN 1 AND 3),
  unlocked_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (profile_id, achievement, tier)
);
COMMENT ON TABLE public.user_achievements IS 'Trophées obtenus, écrits par refresh_my_achievements seulement — migration 32.';
ALTER TABLE public.user_achievements ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "achievements_select" ON public.user_achievements;
CREATE POLICY "achievements_select" ON public.user_achievements FOR SELECT USING (profile_id = auth.uid());
-- Aucune règle INSERT / UPDATE / DELETE : seule la fonction de la base écrit.

-- ── Temps en cuisine ──
CREATE TABLE IF NOT EXISTS public.cook_sessions (
  id          uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  profile_id  uuid        NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  recipe_id   uuid                 REFERENCES public.recipes(id) ON DELETE SET NULL,
  started_at  timestamptz NOT NULL,
  ended_at    timestamptz NOT NULL,
  minutes     smallint    NOT NULL CHECK (minutes BETWEEN 1 AND 240),
  CHECK (ended_at > started_at)
);
CREATE INDEX IF NOT EXISTS idx_cook_sessions_profile ON public.cook_sessions(profile_id, ended_at);
COMMENT ON TABLE public.cook_sessions IS 'Passages en mode « En cuisine » (durée plafonnée à 4 h) — migration 32.';
ALTER TABLE public.cook_sessions ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "cook_sessions_select" ON public.cook_sessions;
DROP POLICY IF EXISTS "cook_sessions_insert" ON public.cook_sessions;
CREATE POLICY "cook_sessions_select" ON public.cook_sessions FOR SELECT USING (profile_id = auth.uid());
CREATE POLICY "cook_sessions_insert" ON public.cook_sessions FOR INSERT
  WITH CHECK (profile_id = auth.uid() AND public.is_member());

CREATE OR REPLACE FUNCTION public.guard_cook_session()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
BEGIN
  IF auth.uid() IS NOT NULL THEN
    NEW.profile_id := auth.uid();
    -- Une séance récente seulement (pas de séances inventées dans le passé ou le futur)
    IF NEW.ended_at > now() + interval '5 minutes' OR NEW.started_at < now() - interval '1 day' THEN
      RAISE EXCEPTION 'Séance hors délai' USING ERRCODE = '22023';
    END IF;
    IF (SELECT count(*) FROM public.cook_sessions s
         WHERE s.profile_id = NEW.profile_id AND s.ended_at > now() - interval '1 day') >= 30 THEN
      RAISE EXCEPTION 'Trop de séances aujourd''hui' USING ERRCODE = 'P0001';
    END IF;
  END IF;
  NEW.minutes := least(240, greatest(0, ceil(extract(epoch FROM (NEW.ended_at - NEW.started_at)) / 60)))::smallint;
  IF NEW.recipe_id IS NOT NULL AND auth.uid() IS NOT NULL AND NOT public.can_read_recipe(NEW.recipe_id) THEN
    NEW.recipe_id := NULL;
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_guard_cook_session ON public.cook_sessions;
CREATE TRIGGER trg_guard_cook_session BEFORE INSERT ON public.cook_sessions
  FOR EACH ROW EXECUTE FUNCTION public.guard_cook_session();
REVOKE ALL ON FUNCTION public.guard_cook_session() FROM PUBLIC, anon, authenticated;

-- ── Boosters ouverts (une ligne par booster et par jour) ──
CREATE TABLE IF NOT EXISTS public.booster_openings (
  id          uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  profile_id  uuid        NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  kind        text        NOT NULL CHECK (kind ~ '^[a-z_]{2,20}$'),
  day         date        NOT NULL,
  recipe_ids  uuid[]      NOT NULL DEFAULT '{}' CHECK (cardinality(recipe_ids) <= 5),
  created_at  timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT uq_booster_opening UNIQUE (profile_id, kind, day)
);
COMMENT ON TABLE public.booster_openings IS 'Boosters ouverts et cartes obtenues (trophées Accro et Collectionneur) — migration 32.';
ALTER TABLE public.booster_openings ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "booster_openings_select" ON public.booster_openings;
DROP POLICY IF EXISTS "booster_openings_insert" ON public.booster_openings;
CREATE POLICY "booster_openings_select" ON public.booster_openings FOR SELECT USING (profile_id = auth.uid());
CREATE POLICY "booster_openings_insert" ON public.booster_openings FOR INSERT
  WITH CHECK (profile_id = auth.uid() AND public.is_member());

CREATE OR REPLACE FUNCTION public.guard_booster_opening()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  rid uuid;
BEGIN
  IF auth.uid() IS NOT NULL THEN
    NEW.profile_id := auth.uid();
    -- Le jour du téléphone peut différer d'un jour du jour UTC de la base, pas plus
    IF NEW.day NOT BETWEEN current_date - 1 AND current_date + 1 THEN
      RAISE EXCEPTION 'Jour hors délai' USING ERRCODE = '22023';
    END IF;
    FOREACH rid IN ARRAY NEW.recipe_ids LOOP
      IF NOT public.can_read_recipe(rid) THEN
        RAISE EXCEPTION 'Recette inconnue' USING ERRCODE = '42501';
      END IF;
    END LOOP;
  END IF;
  NEW.created_at := now();
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_guard_booster_opening ON public.booster_openings;
CREATE TRIGGER trg_guard_booster_opening BEFORE INSERT ON public.booster_openings
  FOR EACH ROW EXECUTE FUNCTION public.guard_booster_opening();
REVOKE ALL ON FUNCTION public.guard_booster_opening() FROM PUBLIC, anon, authenticated;

-- ── Seuils (évolutifs : 3 paliers ; secrets : 1) ──
CREATE OR REPLACE FUNCTION public.achievement_tiers()
RETURNS jsonb LANGUAGE sql IMMUTABLE SET search_path = '' AS $$
  SELECT '{
    "chef": [10, 50, 200], "plume": [1, 10, 30], "critique": [10, 50, 150], "pipelette": [5, 25, 100],
    "chariot": [50, 300, 1000], "globe": [5, 12, 25], "toque": [120, 600, 3000], "planificateur": [4, 12, 40],
    "regulier": [2, 4, 10], "explorateur": [5, 20, 50], "fetes": [1, 5, 15], "anti_gaspi": [3, 15, 50],
    "touche": [4, 6, 8], "photographe": [1, 10, 30], "ambassadeur": [1, 3, 10], "benevole": [3, 10, 30],
    "partant": [3, 10, 25], "accro": [7, 30, 100], "collectionneur": [10, 50, 150],
    "gros_panier": [101], "exotique": [1], "flemmard": [1], "cocktail": [1], "brise_glace": [1],
    "coup_coeur": [5], "reveillon": [1], "fait_maison": [1], "double_service": [1], "gouteur": [1],
    "curieux": [1], "presse": [1], "repas_complet": [1], "tour_france": [5], "retour_sources": [1],
    "grand_chef": [3], "marathon": [7], "semaine_verte": [1], "courses_eclair": [1], "grande_tablee": [10],
    "vieux": [1]
  }'::jsonb
$$;
REVOKE ALL ON FUNCTION public.achievement_tiers() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.achievement_tiers() TO authenticated;

-- ── Progression : un compteur par trophée, pour la personne connectée ──
-- SECURITY DEFINER : certains calculs regardent des données que l'on ne lit pas
-- directement (notes des autres sur MES recettes, premier commentaire d'une recette) ;
-- seuls des NOMBRES sortent, toujours pour auth.uid().
CREATE OR REPLACE FUNCTION public.achievement_progress()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  me  uuid := auth.uid();
  fam uuid := public.user_family_id();
  res jsonb;
  regions text[] := ARRAY['alsace','auvergne','bourgogne','bretagne','corse','dauphine','limousin','lorraine',
                          'lyonnais','nord','normandie','pays_basque','provence','savoie','sud_ouest','antilles'];
BEGIN
  IF me IS NULL OR fam IS NULL THEN
    RETURN '{}'::jsonb;
  END IF;

  WITH c AS (   -- mes repas cuisinés (jour passé ou aujourd'hui, restes exclus)
    SELECT ms.id, ms.recipe_id, ms.meal_type, coalesce(ms.course, 'plat') AS course,
           mp.week_start, (mp.week_start + ms.day_of_week)::date AS d
      FROM public.meal_slots ms JOIN public.meal_plans mp ON mp.id = ms.meal_plan_id
     WHERE ms.cook_id = me AND ms.leftover_of IS NULL
       AND (mp.week_start + ms.day_of_week)::date <= current_date
  ), r AS (
    SELECT c.*, x.category_id, x.origin, x.visibility, x.prep_time_min, x.diets,
           x.created_by, x.family_id AS rfam, x.created_at AS rcreated
      FROM c JOIN public.recipes x ON x.id = c.recipe_id
  ), my_lists AS (   -- listes de mon foyer où j'ai coché au moins un article
    SELECT l.id FROM public.shopping_lists l
     WHERE l.family_id = fam
       AND EXISTS (SELECT 1 FROM public.shopping_list_items i WHERE i.shopping_list_id = l.id AND i.checked_by = me)
  ), cocktails AS (
    SELECT x.id FROM public.recipes x JOIN public.recipe_categories k ON k.id = x.category_id
     WHERE x.visibility = 'catalogue' AND x.archived_at IS NULL AND k.name = 'Boisson & cocktail'
  )
  SELECT jsonb_build_object(
    -- Évolutifs
    'chef',          (SELECT count(*) FROM r),
    'plume',         (SELECT count(*) FROM public.recipes x WHERE x.created_by = me),
    'critique',      (SELECT count(*) FROM public.recipe_ratings n WHERE n.profile_id = me),
    'pipelette',     (SELECT count(*) FROM public.recipe_comments k WHERE k.author_id = me),
    'chariot',       (SELECT count(*) FROM public.shopping_list_items i WHERE i.checked_by = me AND i.checked),
    'globe',         (SELECT count(DISTINCT origin) FROM r WHERE origin IS NOT NULL),
    'toque',         (SELECT coalesce(sum(s.minutes), 0) FROM public.cook_sessions s WHERE s.profile_id = me),
    'planificateur', (SELECT count(*) FROM (SELECT mp.id FROM public.meal_plans mp JOIN public.meal_slots ms ON ms.meal_plan_id = mp.id
                        WHERE mp.family_id = fam GROUP BY mp.id HAVING count(*) >= 5) w),
    'regulier',      (SELECT coalesce(max(n), 0) FROM (SELECT count(*) n FROM (
                        SELECT w, w - (row_number() OVER (ORDER BY w))::int * 7 AS g FROM (SELECT DISTINCT week_start w FROM r) a) b
                        GROUP BY g) z),
    'explorateur',   (SELECT count(DISTINCT recipe_id) FROM r WHERE visibility = 'catalogue'),
    'fetes',         (SELECT count(*) FROM public.events e WHERE e.created_by = me),
    'anti_gaspi',    (SELECT count(*) FROM public.meal_slots s JOIN public.meal_slots o ON o.id = s.leftover_of WHERE o.cook_id = me),
    'touche',        (SELECT count(DISTINCT category_id) FROM r WHERE category_id IS NOT NULL),
    'photographe',   (SELECT count(*) FROM public.recipes x WHERE x.created_by = me AND x.image_url IS NOT NULL AND x.image_url NOT LIKE 'http%'),
    'ambassadeur',   (SELECT count(*) FROM public.invitations i WHERE i.created_by = me AND i.used_at IS NOT NULL),
    'benevole',      (SELECT count(*) FROM public.event_tasks t WHERE me = ANY (t.volunteers)),
    'partant',       (SELECT count(*) FROM public.event_rsvps v WHERE v.profile_id = me AND v.answer = 'oui'),
    'accro',         (SELECT count(*) FROM public.booster_openings b WHERE b.profile_id = me),
    'collectionneur',(SELECT count(DISTINCT x) FROM public.booster_openings b, unnest(b.recipe_ids) x WHERE b.profile_id = me),
    -- Secrets
    'gros_panier',   (SELECT coalesce(max(n), 0) FROM (SELECT count(*) n FROM public.shopping_list_items i
                        WHERE i.shopping_list_id IN (SELECT id FROM my_lists) GROUP BY i.shopping_list_id) z),
    'exotique',      (SELECT count(*) FROM (SELECT 1 FROM r GROUP BY week_start
                        HAVING count(DISTINCT d) = 7 AND count(DISTINCT recipe_id) >= 7) z),
    'flemmard',      (SELECT count(*) FROM (SELECT 1 FROM r GROUP BY week_start, recipe_id HAVING count(*) >= 4) z),
    'cocktail',      (SELECT CASE WHEN count(*) > 0 AND count(*) = count(*) FILTER (WHERE k.id IN (SELECT recipe_id FROM r)) THEN 1 ELSE 0 END
                        FROM cocktails k),
    'brise_glace',   (SELECT count(*) FROM public.recipe_comments k WHERE k.author_id = me
                        AND NOT EXISTS (SELECT 1 FROM public.recipe_comments k2 WHERE k2.recipe_id = k.recipe_id AND k2.created_at < k.created_at)),
    'coup_coeur',    (SELECT coalesce(max(n), 0) FROM (SELECT count(*) n FROM public.recipe_ratings n JOIN public.recipes x ON x.id = n.recipe_id
                        WHERE x.created_by = me AND n.profile_id <> me AND n.stars >= 4 GROUP BY n.recipe_id) z),
    'reveillon',     (SELECT count(*) FROM r WHERE extract(month FROM d) = 12 AND extract(day FROM d) IN (24, 31)),
    'fait_maison',   (SELECT count(*) FROM r WHERE created_by = me),
    'double_service',(SELECT count(*) FROM (SELECT 1 FROM r GROUP BY d HAVING count(DISTINCT meal_type) = 2) z),
    'gouteur',       (SELECT count(*) FROM (SELECT 1 FROM public.recipe_ratings n WHERE n.profile_id = me
                        GROUP BY n.created_at::date HAVING count(*) >= 5) z),
    'curieux',       (SELECT count(*) FROM r WHERE rfam IS DISTINCT FROM fam AND visibility <> 'catalogue'
                        AND d - rcreated::date BETWEEN 0 AND 6),
    'presse',        (SELECT count(*) FROM (SELECT 1 FROM r WHERE prep_time_min <= 20 GROUP BY week_start HAVING count(*) >= 3) z),
    'repas_complet', (SELECT count(*) FROM (SELECT 1 FROM r GROUP BY d, meal_type HAVING count(DISTINCT course) = 3) z),
    'tour_france',   (SELECT count(DISTINCT origin) FROM r WHERE origin = ANY (regions)),
    'retour_sources',(SELECT count(*) FROM (SELECT d - lag(d) OVER (PARTITION BY recipe_id ORDER BY d) AS gap FROM r) z WHERE gap > 182),
    'grand_chef',    (SELECT count(*) FROM r WHERE prep_time_min > 90),
    'marathon',      (SELECT coalesce(max(n), 0) FROM (SELECT count(*) n FROM (
                        SELECT dd, dd - (row_number() OVER (ORDER BY dd))::int AS g FROM (SELECT DISTINCT d dd FROM r) a) b
                        GROUP BY g) z),
    'semaine_verte', (SELECT count(*) FROM (SELECT 1 FROM r GROUP BY week_start
                        HAVING count(*) >= 5 AND bool_and(diets && ARRAY['vegetarien', 'vegan'])) z),
    'courses_eclair',(SELECT count(*) FROM (SELECT 1 FROM public.shopping_list_items i
                        WHERE i.shopping_list_id IN (SELECT id FROM my_lists) GROUP BY i.shopping_list_id
                        HAVING count(*) >= 20 AND bool_and(i.checked AND i.checked_at IS NOT NULL)
                           AND max(i.checked_at) - min(i.checked_at) <= interval '15 minutes') z),
    'grande_tablee', (SELECT coalesce(max(n), 0) FROM (SELECT count(*) n FROM public.event_rsvps v JOIN public.events e ON e.id = v.event_id
                        WHERE e.created_by = me AND v.answer = 'oui' GROUP BY e.id) z),
    'vieux',         (SELECT CASE WHEN p.created_at <= now() - interval '1 year' THEN 1 ELSE 0 END FROM public.profiles p WHERE p.id = me)
  ) INTO res;
  RETURN res;
END;
$$;
REVOKE ALL ON FUNCTION public.achievement_progress() FROM PUBLIC, anon, authenticated;

-- ── Enregistrer les paliers atteints ; renvoie seulement les NOUVEAUX ──
CREATE OR REPLACE FUNCTION public.refresh_my_achievements()
RETURNS TABLE (achievement text, tier smallint, unlocked_at timestamptz)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
#variable_conflict use_column
DECLARE
  me   uuid := auth.uid();
  prog jsonb;
BEGIN
  IF me IS NULL OR NOT public.is_member() THEN
    RETURN;
  END IF;
  prog := public.achievement_progress();
  RETURN QUERY
  INSERT INTO public.user_achievements AS ua (profile_id, achievement, tier)
  SELECT me, e.key, t.ord::smallint
    FROM jsonb_each(public.achievement_tiers()) e,
         jsonb_array_elements(e.value) WITH ORDINALITY t(th, ord)
   WHERE coalesce((prog ->> e.key)::numeric, 0) >= (t.th)::numeric
  ON CONFLICT DO NOTHING
  RETURNING ua.achievement, ua.tier, ua.unlocked_at;
END;
$$;
REVOKE ALL ON FUNCTION public.refresh_my_achievements() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.refresh_my_achievements() TO authenticated;

-- ── Tout pour la page « Mes trophées » ──
CREATE OR REPLACE FUNCTION public.my_achievements()
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT jsonb_build_object(
    'progress', public.achievement_progress(),
    'unlocked', coalesce((SELECT jsonb_agg(jsonb_build_object('achievement', ua.achievement, 'tier', ua.tier,
                                                              'unlocked_at', ua.unlocked_at) ORDER BY ua.unlocked_at)
                            FROM public.user_achievements ua WHERE ua.profile_id = auth.uid()), '[]'::jsonb)
  )
$$;
REVOKE ALL ON FUNCTION public.my_achievements() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.my_achievements() TO authenticated;

-- ── Nouvelle version des conditions ──
CREATE OR REPLACE FUNCTION public.current_terms_version()
RETURNS text LANGUAGE sql IMMUTABLE SET search_path = '' AS $$ SELECT '2026-11-19'::text $$;
GRANT EXECUTE ON FUNCTION public.current_terms_version() TO authenticated;
REVOKE ALL ON FUNCTION public.current_terms_version() FROM anon;

-- ── Mes données : succès, temps en cuisine et boosters font partie de l'export ──
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
    'succes_obtenus', coalesce((SELECT jsonb_agg(jsonb_build_object('succes', ua.achievement, 'palier', ua.tier, 'le', ua.unlocked_at) ORDER BY ua.unlocked_at)
                 FROM public.user_achievements ua WHERE ua.profile_id = me), '[]'::jsonb),
    'temps_en_cuisine', coalesce((SELECT jsonb_agg(jsonb_build_object('recette', r.title, 'debut', s.started_at, 'minutes', s.minutes) ORDER BY s.started_at)
                 FROM public.cook_sessions s LEFT JOIN public.recipes r ON r.id = s.recipe_id WHERE s.profile_id = me), '[]'::jsonb),
    'boosters_ouverts', coalesce((SELECT jsonb_agg(jsonb_build_object('booster', b.kind, 'jour', b.day, 'recettes',
                    (SELECT coalesce(jsonb_agg(x.title), '[]'::jsonb) FROM public.recipes x WHERE x.id = ANY (b.recipe_ids))) ORDER BY b.day)
                 FROM public.booster_openings b WHERE b.profile_id = me), '[]'::jsonb),
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
