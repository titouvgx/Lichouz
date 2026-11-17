-- ============================================================
-- Migration 29 : conformité (v2.0.0, lot C)
-- ============================================================
-- 1. Pseudo obligatoire et unique (profiles.pseudo)
--      3 à 20 caractères : lettres sans accent, chiffres, « _ » et « . » ;
--      unique sans tenir compte des majuscules ; noms réservés ;
--      seulement par soi-même ; changement au plus une fois tous les 30 jours.
-- 2. Acceptation des conditions (terms_acceptances)
--      une ligne par personne et par version des documents (preuve : date + version) ;
--      tranche d'âge déclarée (majeur / 15_17 / moins_15).
--      Moins de 15 ans (loi Informatique et Libertés, art. 45) : accord d'un parent
--      du même foyer (adulte ayant accepté), donné et retirable depuis l'appli.
-- 3. Mes données : export_my_data() renvoie tout ce qui concerne la personne connectée.
-- 4. Durées de conservation : purge_expired_data(), lancée chaque nuit par pg_cron
--    (si l'extension existe ; le banc PGlite ne l'a pas).
-- Contrôle : supabase/tests/controle_29_conformite.sql. Idempotente.
-- ============================================================

-- ── 1. Pseudo ───────────────────────────────────────────────
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS pseudo text;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS pseudo_changed_at timestamptz;

-- Liste des noms réservés : la même liste est dans src/lib/pseudo.ts (un test compare).
CREATE OR REPLACE FUNCTION public.pseudo_is_valid(p text)
RETURNS boolean LANGUAGE sql IMMUTABLE SET search_path = '' AS $$
  SELECT p ~ '^[A-Za-z0-9_.]{3,20}$'
     AND p !~ '^[._]' AND p !~ '[._]$' AND p !~ '\.\.'
     AND NOT (lower(p) = ANY (ARRAY[
       'admin', 'administrateur', 'administration', 'moderateur', 'moderation', 'modo',
       'support', 'aide', 'help', 'contact', 'equipe', 'staff', 'officiel', 'service',
       'root', 'system', 'systeme', 'superadmin', 'super_admin', 'fondateur',
       'null', 'undefined', 'anonyme', 'inconnu', 'supprime', 'auteur_supprime', 'compte_supprime'
     ]))
     AND lower(p) !~ '^(lichouz|admin)'
$$;
-- Exécutable par tous : la contrainte ci-dessous l'appelle avec les droits de la personne.
GRANT EXECUTE ON FUNCTION public.pseudo_is_valid(text) TO anon, authenticated;

ALTER TABLE public.profiles DROP CONSTRAINT IF EXISTS profiles_pseudo_valid;
ALTER TABLE public.profiles ADD CONSTRAINT profiles_pseudo_valid
  CHECK (pseudo IS NULL OR public.pseudo_is_valid(pseudo));
CREATE UNIQUE INDEX IF NOT EXISTS uq_profiles_pseudo ON public.profiles (lower(pseudo)) WHERE pseudo IS NOT NULL;
COMMENT ON COLUMN public.profiles.pseudo IS 'Pseudo unique (sans tenir compte des majuscules), choisi par la personne — migration 29.';

CREATE OR REPLACE FUNCTION public.guard_profile_pseudo()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    IF auth.uid() IS NOT NULL THEN NEW.pseudo := NULL; NEW.pseudo_changed_at := NULL; END IF;
    RETURN NEW;
  END IF;
  -- Date du dernier changement : jamais écrite à la main
  IF NEW.pseudo IS NOT DISTINCT FROM OLD.pseudo THEN
    NEW.pseudo_changed_at := OLD.pseudo_changed_at;
    RETURN NEW;
  END IF;
  IF auth.uid() IS NULL OR public.is_super_admin() THEN
    NEW.pseudo_changed_at := now();
    RETURN NEW;
  END IF;
  IF OLD.id <> auth.uid() OR NOT public.is_member() THEN
    RAISE EXCEPTION 'Modification interdite : le pseudo d''un autre membre' USING ERRCODE = '42501';
  END IF;
  IF NEW.pseudo IS NULL THEN
    RAISE EXCEPTION 'Le pseudo ne peut pas être effacé' USING ERRCODE = '42501';
  END IF;
  IF OLD.pseudo IS NOT NULL AND lower(NEW.pseudo) = lower(OLD.pseudo) THEN
    NEW.pseudo_changed_at := OLD.pseudo_changed_at; -- majuscules seulement : toujours permis
    RETURN NEW;
  END IF;
  IF OLD.pseudo IS NOT NULL AND OLD.pseudo_changed_at > now() - interval '30 days' THEN
    RAISE EXCEPTION 'Pseudo changé il y a moins de 30 jours' USING ERRCODE = '42501';
  END IF;
  NEW.pseudo_changed_at := now();
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_guard_profile_pseudo ON public.profiles;
CREATE TRIGGER trg_guard_profile_pseudo BEFORE INSERT OR UPDATE ON public.profiles
  FOR EACH ROW EXECUTE FUNCTION public.guard_profile_pseudo();
REVOKE ALL ON FUNCTION public.guard_profile_pseudo() FROM PUBLIC, anon, authenticated;

-- Pseudo libre ? (le formulaire prévient avant d'envoyer ; la base reste juge)
CREATE OR REPLACE FUNCTION public.pseudo_available(p text)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT public.pseudo_is_valid(p)
     AND NOT EXISTS (SELECT 1 FROM public.profiles x WHERE lower(x.pseudo) = lower(p) AND x.id <> auth.uid())
$$;
REVOKE ALL ON FUNCTION public.pseudo_available(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.pseudo_available(text) TO authenticated;

-- ── 2. Acceptation des conditions ───────────────────────────
-- Version en vigueur des CGU + politique de confidentialité (même valeur dans src/lib/legal.ts).
CREATE OR REPLACE FUNCTION public.current_terms_version()
RETURNS text LANGUAGE sql IMMUTABLE SET search_path = '' AS $$ SELECT '2026-11-17'::text $$;
GRANT EXECUTE ON FUNCTION public.current_terms_version() TO authenticated;
REVOKE ALL ON FUNCTION public.current_terms_version() FROM anon;

CREATE TABLE IF NOT EXISTS public.terms_acceptances (
  id                  uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  profile_id          uuid        NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  version             text        NOT NULL CHECK (version ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'),
  age_group           text        NOT NULL CHECK (age_group IN ('majeur', '15_17', 'moins_15')),
  accepted_at         timestamptz NOT NULL DEFAULT now(),
  parent_id           uuid                 REFERENCES public.profiles(id) ON DELETE SET NULL,
  parent_confirmed_at timestamptz,
  CONSTRAINT uq_terms_acceptance UNIQUE (profile_id, version),
  CONSTRAINT terms_parent_only_minor CHECK (age_group = 'moins_15' OR (parent_id IS NULL AND parent_confirmed_at IS NULL))
);
CREATE INDEX IF NOT EXISTS idx_terms_parent ON public.terms_acceptances(parent_id);
COMMENT ON TABLE public.terms_acceptances IS
  'Acceptation des CGU et de la politique de confidentialité, par version ; accord parental pour les moins de 15 ans — migration 29.';

ALTER TABLE public.terms_acceptances ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "terms_select" ON public.terms_acceptances;
DROP POLICY IF EXISTS "terms_insert" ON public.terms_acceptances;
-- On lit ses propres acceptations et celles des enfants dont on a donné l'accord.
CREATE POLICY "terms_select" ON public.terms_acceptances FOR SELECT
  USING (profile_id = auth.uid() OR parent_id = auth.uid());
-- On n'accepte que pour soi-même. Aucune règle UPDATE / DELETE : la preuve ne se modifie pas
-- (l'accord parental passe par confirm_parental_consent / revoke_parental_consent).
CREATE POLICY "terms_insert" ON public.terms_acceptances FOR INSERT
  WITH CHECK (profile_id = auth.uid() AND public.user_family_id() IS NOT NULL);

CREATE OR REPLACE FUNCTION public.guard_terms_acceptance()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
BEGIN
  IF auth.uid() IS NOT NULL THEN
    NEW.accepted_at := now();
    NEW.parent_id := NULL;
    NEW.parent_confirmed_at := NULL;
    IF NEW.version IS DISTINCT FROM public.current_terms_version() THEN
      RAISE EXCEPTION 'Ces conditions ne sont plus en vigueur : recharge l''appli' USING ERRCODE = '22023';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_guard_terms_acceptance ON public.terms_acceptances;
CREATE TRIGGER trg_guard_terms_acceptance BEFORE INSERT ON public.terms_acceptances
  FOR EACH ROW EXECUTE FUNCTION public.guard_terms_acceptance();
REVOKE ALL ON FUNCTION public.guard_terms_acceptance() FROM PUBLIC, anon, authenticated;

-- Fenêtre d'accueil : pseudo + acceptation en une seule opération.
-- SECURITY INVOKER : les règles RLS et les gardes s'appliquent normalement.
-- Renvoie 'ok' ou 'attente_parent'. Une tranche d'âge déjà déclarée pour cette version
-- n'est pas modifiable (pas de « je me déclare majeur » après coup).
CREATE OR REPLACE FUNCTION public.accept_terms(p_version text, p_age_group text, p_pseudo text)
RETURNS text LANGUAGE plpgsql VOLATILE SECURITY INVOKER SET search_path = '' AS $$
DECLARE
  me uuid := auth.uid();
  res text;
BEGIN
  IF me IS NULL THEN
    RAISE EXCEPTION 'Connexion requise' USING ERRCODE = '42501';
  END IF;
  IF p_pseudo IS NOT NULL AND btrim(p_pseudo) <> '' THEN
    UPDATE public.profiles SET pseudo = btrim(p_pseudo)
     WHERE id = me AND pseudo IS DISTINCT FROM btrim(p_pseudo);
  END IF;
  IF (SELECT p.pseudo FROM public.profiles p WHERE p.id = me) IS NULL THEN
    RAISE EXCEPTION 'Choisis un pseudo' USING ERRCODE = '22023';
  END IF;
  INSERT INTO public.terms_acceptances (profile_id, version, age_group)
  VALUES (me, p_version, p_age_group)
  ON CONFLICT (profile_id, version) DO NOTHING;
  SELECT CASE WHEN t.age_group = 'moins_15' AND t.parent_confirmed_at IS NULL THEN 'attente_parent' ELSE 'ok' END
    INTO res
    FROM public.terms_acceptances t
   WHERE t.profile_id = me AND t.version = p_version;
  RETURN res;
END;
$$;
REVOKE ALL ON FUNCTION public.accept_terms(text, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.accept_terms(text, text, text) TO authenticated;

-- Adulte du foyer ayant accepté la version en vigueur ?
CREATE OR REPLACE FUNCTION public.is_adult_of_family()
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT public.user_family_id() IS NOT NULL AND EXISTS (
    SELECT 1 FROM public.terms_acceptances t
     WHERE t.profile_id = auth.uid()
       AND t.version = public.current_terms_version()
       AND t.age_group = 'majeur'
  )
$$;
REVOKE ALL ON FUNCTION public.is_adult_of_family() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.is_adult_of_family() TO authenticated;

-- Enfants du foyer : en attente d'accord, ou accord donné par moi (pour pouvoir le retirer).
CREATE OR REPLACE FUNCTION public.parental_consents()
RETURNS TABLE (profile_id uuid, display_name text, accepted_at timestamptz, confirmed_at timestamptz)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT t.profile_id, p.display_name, t.accepted_at, t.parent_confirmed_at
    FROM public.terms_acceptances t
    JOIN public.profiles p ON p.id = t.profile_id
   WHERE public.is_adult_of_family()
     AND t.version = public.current_terms_version()
     AND t.age_group = 'moins_15'
     AND t.profile_id <> auth.uid()
     AND p.family_id = public.user_family_id()
     AND (t.parent_confirmed_at IS NULL OR t.parent_id = auth.uid())
   ORDER BY p.display_name
$$;
REVOKE ALL ON FUNCTION public.parental_consents() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.parental_consents() TO authenticated;

CREATE OR REPLACE FUNCTION public.confirm_parental_consent(p_child uuid)
RETURNS boolean LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $$
DECLARE n int;
BEGIN
  IF NOT public.is_adult_of_family() THEN
    RAISE EXCEPTION 'Seul un adulte du foyer peut donner son accord' USING ERRCODE = '42501';
  END IF;
  UPDATE public.terms_acceptances t
     SET parent_id = auth.uid(), parent_confirmed_at = now()
    FROM public.profiles p
   WHERE p.id = t.profile_id
     AND t.profile_id = p_child
     AND t.profile_id <> auth.uid()
     AND p.family_id = public.user_family_id()
     AND t.version = public.current_terms_version()
     AND t.age_group = 'moins_15'
     AND t.parent_confirmed_at IS NULL;
  GET DIAGNOSTICS n = ROW_COUNT;
  IF n = 0 THEN
    RAISE EXCEPTION 'Aucune demande d''accord à confirmer pour cette personne' USING ERRCODE = '42501';
  END IF;
  RETURN true;
END;
$$;
REVOKE ALL ON FUNCTION public.confirm_parental_consent(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.confirm_parental_consent(uuid) TO authenticated;

-- Retirer son accord : seul le parent qui l'a donné. L'enfant est de nouveau bloqué.
CREATE OR REPLACE FUNCTION public.revoke_parental_consent(p_child uuid)
RETURNS boolean LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $$
DECLARE n int;
BEGIN
  UPDATE public.terms_acceptances t
     SET parent_id = NULL, parent_confirmed_at = NULL
   WHERE t.profile_id = p_child
     AND t.parent_id = auth.uid()
     AND t.version = public.current_terms_version();
  GET DIAGNOSTICS n = ROW_COUNT;
  IF n = 0 THEN
    RAISE EXCEPTION 'Aucun accord donné par toi pour cette personne' USING ERRCODE = '42501';
  END IF;
  RETURN true;
END;
$$;
REVOKE ALL ON FUNCTION public.revoke_parental_consent(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.revoke_parental_consent(uuid) TO authenticated;

-- ── 3. Mes données (droit d'accès et de portabilité) ────────
-- Uniquement les lignes de la personne connectée (filtre auth.uid() partout).
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

-- ── 4. Durées de conservation ───────────────────────────────
-- Mêmes durées que la politique de confidentialité (src/pages/Confidentialite.svelte).
-- Ne touche jamais aux comptes, profils, recettes ni à la preuve d'acceptation.
CREATE OR REPLACE FUNCTION public.purge_expired_data()
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  n_err int; n_inv int; n_fb int; n_evt int; n_list int; n_plan int; n_att int;
BEGIN
  DELETE FROM public.app_errors WHERE created_at < now() - interval '90 days';
  GET DIAGNOSTICS n_err = ROW_COUNT;
  -- Liens d'invitation utilisés, annulés ou expirés depuis plus de 90 jours
  DELETE FROM public.invitations
   WHERE greatest(coalesce(used_at, '-infinity'), coalesce(revoked_at, '-infinity'), expires_at) < now() - interval '90 days'
     AND (used_at IS NOT NULL OR revoked_at IS NOT NULL OR expires_at < now());
  GET DIAGNOSTICS n_inv = ROW_COUNT;
  DELETE FROM public.feedback WHERE created_at < now() - interval '2 years';
  GET DIAGNOSTICS n_fb = ROW_COUNT;
  DELETE FROM public.events WHERE starts_on < current_date - interval '1 year';
  GET DIAGNOSTICS n_evt = ROW_COUNT;
  DELETE FROM public.shopping_lists WHERE status = 'completed' AND completed_at < now() - interval '2 years';
  GET DIAGNOSTICS n_list = ROW_COUNT;
  DELETE FROM public.meal_plans WHERE week_start < current_date - interval '2 years';
  GET DIAGNOSTICS n_plan = ROW_COUNT;
  DELETE FROM private.account_deletion_attempts WHERE created_at < now() - interval '1 day';
  GET DIAGNOSTICS n_att = ROW_COUNT;
  RETURN jsonb_build_object('erreurs', n_err, 'invitations', n_inv, 'retours', n_fb, 'evenements', n_evt,
                            'listes', n_list, 'plannings', n_plan, 'essais_suppression', n_att);
END;
$$;
-- Personne ne la lance depuis l'appli : seulement la tâche de nuit (rôle postgres).
REVOKE ALL ON FUNCTION public.purge_expired_data() FROM PUBLIC, anon, authenticated;

-- Tâche de nuit (03:17 UTC). L'instruction est construite en morceaux pour que le banc
-- PGlite (qui n'a pas pg_cron) ne la prenne pas pour une extension à charger.
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_available_extensions WHERE name = 'pg_cron') THEN
    EXECUTE 'CREATE ' || 'EXTENSION IF NOT EXISTS pg_cron';
    IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'lichouz-purge') THEN
      PERFORM cron.unschedule('lichouz-purge');
    END IF;
    PERFORM cron.schedule('lichouz-purge', '17 3 * * *', 'SELECT public.purge_expired_data()');
  END IF;
END;
$$;
