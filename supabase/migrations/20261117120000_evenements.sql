-- ============================================================
-- Migration 28 : événements (v1.999.0, lot N « Noël »)
-- ============================================================
-- Un modèle réutilisable (Noël, anniversaire, fête…) :
--   - events            : l'événement (date, chez qui, thème, playlist, notes, visibilité)
--   - event_tasks       : « qui fait quoi » (pôles proposés + tâches libres) ; volontaires
--                         = tableau de personnes, chacun ne s'ajoute / ne se retire que lui-même
--   - event_rsvps       : réponse oui / non / peut-être, une par personne et par événement
--
-- Visibilité (décision du 17/11/2026) : choisie à la création
--   'foyer'   → le foyer du créateur seulement
--   'famille' → tous les foyers de la famille élargie (même super-famille)
-- Création : tout membre ; modification / suppression de l'événement : son créateur
-- ou un admin du foyer. Pas d'exception super-admin (données privées des foyers).
-- RLS sur les trois tables ; gardes par trigger (auteur forcé, limites, volontaires).
-- Contrôle : supabase/tests/controle_28_evenements.sql. Idempotente.
-- ============================================================

-- ── Tables ──────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.events (
  id            uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  family_id     uuid        NOT NULL REFERENCES public.families(id) ON DELETE CASCADE,
  created_by    uuid                 REFERENCES public.profiles(id) ON DELETE SET NULL,
  kind          text        NOT NULL DEFAULT 'noel' CHECK (kind IN ('noel', 'anniversaire', 'fete', 'autre')),
  scope         text        NOT NULL DEFAULT 'foyer' CHECK (scope IN ('foyer', 'famille')),
  title         text        NOT NULL CHECK (char_length(btrim(title)) BETWEEN 1 AND 80),
  starts_on     date        NOT NULL,
  start_time    time,
  location      text        CHECK (location IS NULL OR char_length(location) <= 80),
  theme         text        CHECK (theme IS NULL OR char_length(theme) <= 80),
  playlist_url  text        CHECK (playlist_url IS NULL OR (char_length(playlist_url) <= 300 AND playlist_url ~ '^https://[^[:space:]]+$')),
  notes         text        CHECK (notes IS NULL OR char_length(notes) <= 1000),
  created_at    timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_events_family ON public.events(family_id, starts_on);
COMMENT ON TABLE public.events IS 'Événements (Noël, anniversaires…) du foyer ou de la famille élargie — migration 28.';

CREATE TABLE IF NOT EXISTS public.event_tasks (
  id          uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  event_id    uuid        NOT NULL REFERENCES public.events(id) ON DELETE CASCADE,
  label       text        NOT NULL CHECK (char_length(btrim(label)) BETWEEN 1 AND 60),
  position    smallint    NOT NULL DEFAULT 0 CHECK (position BETWEEN 0 AND 99),
  volunteers  uuid[]      NOT NULL DEFAULT '{}' CHECK (cardinality(volunteers) <= 20),
  created_by  uuid                 REFERENCES public.profiles(id) ON DELETE SET NULL,
  created_at  timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_event_tasks_event ON public.event_tasks(event_id);
COMMENT ON TABLE public.event_tasks IS '« Qui fait quoi » d''un événement ; volunteers = personnes inscrites (chacun s''inscrit lui-même).';

CREATE TABLE IF NOT EXISTS public.event_rsvps (
  id          uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  event_id    uuid        NOT NULL REFERENCES public.events(id) ON DELETE CASCADE,
  profile_id  uuid        NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  answer      text        NOT NULL CHECK (answer IN ('oui', 'non', 'peut_etre')),
  updated_at  timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT uq_event_rsvp UNIQUE (event_id, profile_id)
);
CREATE INDEX IF NOT EXISTS idx_event_rsvps_event ON public.event_rsvps(event_id);
COMMENT ON TABLE public.event_rsvps IS 'Réponses aux événements (oui / non / peut-être), une par personne.';

-- ── Aides (SECURITY DEFINER : lisent events sans passer par RLS) ──
CREATE OR REPLACE FUNCTION public.can_see_event(eid uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.events e
     WHERE e.id = eid
       AND (
         public.is_family(e.family_id)
         OR (e.scope = 'famille'
             AND public.my_super_family_id() IS NOT NULL
             AND public.family_super_family(e.family_id) = public.my_super_family_id())
       )
  )
$$;

CREATE OR REPLACE FUNCTION public.can_edit_event(eid uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.events e
     WHERE e.id = eid
       AND public.is_family(e.family_id)
       AND (e.created_by = auth.uid() OR public.is_admin())
  )
$$;
REVOKE ALL ON FUNCTION public.can_see_event(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.can_edit_event(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.can_see_event(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.can_edit_event(uuid) TO authenticated;

-- ── RLS ─────────────────────────────────────────────────────
ALTER TABLE public.events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.event_tasks ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.event_rsvps ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "events_select" ON public.events;
DROP POLICY IF EXISTS "events_insert" ON public.events;
DROP POLICY IF EXISTS "events_update" ON public.events;
DROP POLICY IF EXISTS "events_delete" ON public.events;
CREATE POLICY "events_select" ON public.events FOR SELECT
  USING (
    public.is_family(family_id)
    OR (scope = 'famille'
        AND public.my_super_family_id() IS NOT NULL
        AND public.family_super_family(family_id) = public.my_super_family_id())
  );
CREATE POLICY "events_insert" ON public.events FOR INSERT
  WITH CHECK (public.is_family(family_id));
CREATE POLICY "events_update" ON public.events FOR UPDATE
  USING (public.is_family(family_id) AND (created_by = auth.uid() OR public.is_admin()))
  WITH CHECK (public.is_family(family_id));
CREATE POLICY "events_delete" ON public.events FOR DELETE
  USING (public.is_family(family_id) AND (created_by = auth.uid() OR public.is_admin()));

DROP POLICY IF EXISTS "event_tasks_select" ON public.event_tasks;
DROP POLICY IF EXISTS "event_tasks_insert" ON public.event_tasks;
DROP POLICY IF EXISTS "event_tasks_update" ON public.event_tasks;
DROP POLICY IF EXISTS "event_tasks_delete" ON public.event_tasks;
CREATE POLICY "event_tasks_select" ON public.event_tasks FOR SELECT
  USING (public.can_see_event(event_id));
-- Toute personne qui voit l'événement peut proposer une tâche…
CREATE POLICY "event_tasks_insert" ON public.event_tasks FOR INSERT
  WITH CHECK (public.can_see_event(event_id));
-- … et s'inscrire / se retirer (le trigger limite ce qu'elle peut changer)
CREATE POLICY "event_tasks_update" ON public.event_tasks FOR UPDATE
  USING (public.can_see_event(event_id))
  WITH CHECK (public.can_see_event(event_id));
-- Supprimer une tâche : celle ou celui qui l'a écrite, ou qui peut modifier l'événement
CREATE POLICY "event_tasks_delete" ON public.event_tasks FOR DELETE
  USING (public.can_see_event(event_id) AND (created_by = auth.uid() OR public.can_edit_event(event_id)));

DROP POLICY IF EXISTS "event_rsvps_select" ON public.event_rsvps;
DROP POLICY IF EXISTS "event_rsvps_insert" ON public.event_rsvps;
DROP POLICY IF EXISTS "event_rsvps_update" ON public.event_rsvps;
DROP POLICY IF EXISTS "event_rsvps_delete" ON public.event_rsvps;
CREATE POLICY "event_rsvps_select" ON public.event_rsvps FOR SELECT
  USING (public.can_see_event(event_id));
CREATE POLICY "event_rsvps_insert" ON public.event_rsvps FOR INSERT
  WITH CHECK (profile_id = auth.uid() AND public.is_member() AND public.can_see_event(event_id));
CREATE POLICY "event_rsvps_update" ON public.event_rsvps FOR UPDATE
  USING (profile_id = auth.uid() AND public.can_see_event(event_id))
  WITH CHECK (profile_id = auth.uid() AND public.can_see_event(event_id));
CREATE POLICY "event_rsvps_delete" ON public.event_rsvps FOR DELETE
  USING (profile_id = auth.uid());

-- ── Gardes ──────────────────────────────────────────────────
-- Événement : auteur forcé, 30 événements par foyer, textes nettoyés
CREATE OR REPLACE FUNCTION public.guard_event()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    IF auth.uid() IS NOT NULL THEN NEW.created_by := auth.uid(); END IF;
    IF (SELECT count(*) FROM public.events WHERE family_id = NEW.family_id) >= 30 THEN
      RAISE EXCEPTION 'Pas plus de 30 événements par foyer : supprime les anciens' USING ERRCODE = '54000';
    END IF;
  ELSE
    -- (changer de foyer est refusé par la règle RLS : WITH CHECK is_family)
    IF auth.uid() IS NOT NULL THEN NEW.created_by := OLD.created_by; END IF;
    NEW.updated_at := now();
  END IF;
  NEW.title := btrim(NEW.title);
  NEW.location := NULLIF(btrim(NEW.location), '');
  NEW.theme := NULLIF(btrim(NEW.theme), '');
  NEW.notes := NULLIF(btrim(NEW.notes), '');
  NEW.playlist_url := NULLIF(btrim(NEW.playlist_url), '');
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_guard_event ON public.events;
CREATE TRIGGER trg_guard_event BEFORE INSERT OR UPDATE ON public.events
  FOR EACH ROW EXECUTE FUNCTION public.guard_event();

-- Tâches : auteur forcé, 30 par événement ; une personne qui n'est ni l'auteur de la
-- tâche ni « modificatrice » de l'événement ne peut que s'ajouter ou se retirer elle-même.
CREATE OR REPLACE FUNCTION public.guard_event_task()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  me uuid := auth.uid();
  added uuid[];
  removed uuid[];
BEGIN
  IF array_position(NEW.volunteers, NULL) IS NOT NULL
     OR cardinality(NEW.volunteers) <> (SELECT count(DISTINCT v) FROM unnest(NEW.volunteers) AS v) THEN
    RAISE EXCEPTION 'Volontaires invalides' USING ERRCODE = '22023';
  END IF;
  NEW.label := btrim(NEW.label);
  IF me IS NULL THEN RETURN NEW; END IF; -- super-utilisateur, migrations

  IF TG_OP = 'INSERT' THEN
    NEW.created_by := me;
    IF (SELECT count(*) FROM public.event_tasks WHERE event_id = NEW.event_id) >= 30 THEN
      RAISE EXCEPTION 'Pas plus de 30 tâches par événement' USING ERRCODE = '54000';
    END IF;
    -- À la création, on ne peut inscrire que soi-même
    IF EXISTS (SELECT 1 FROM unnest(NEW.volunteers) AS v WHERE v <> me) THEN
      RAISE EXCEPTION '« Qui fait quoi » : tu ne peux inscrire que toi-même' USING ERRCODE = '42501';
    END IF;
    RETURN NEW;
  END IF;

  -- UPDATE
  NEW.created_by := OLD.created_by;
  IF NEW.event_id IS DISTINCT FROM OLD.event_id THEN
    RAISE EXCEPTION 'Une tâche ne change pas d''événement' USING ERRCODE = '42501';
  END IF;
  SELECT coalesce(array_agg(v), '{}') INTO added FROM unnest(NEW.volunteers) AS v WHERE NOT v = ANY (OLD.volunteers);
  SELECT coalesce(array_agg(v), '{}') INTO removed FROM unnest(OLD.volunteers) AS v WHERE NOT v = ANY (NEW.volunteers);
  -- Personne n'inscrit quelqu'un d'autre
  IF EXISTS (SELECT 1 FROM unnest(added) AS v WHERE v <> me) THEN
    RAISE EXCEPTION '« Qui fait quoi » : tu ne peux inscrire que toi-même' USING ERRCODE = '42501';
  END IF;
  IF OLD.created_by IS DISTINCT FROM me AND NOT public.can_edit_event(OLD.event_id) THEN
    IF NEW.label IS DISTINCT FROM OLD.label OR NEW.position IS DISTINCT FROM OLD.position THEN
      RAISE EXCEPTION 'Seul l''auteur de la tâche ou de l''événement la modifie' USING ERRCODE = '42501';
    END IF;
    IF EXISTS (SELECT 1 FROM unnest(removed) AS v WHERE v <> me) THEN
      RAISE EXCEPTION '« Qui fait quoi » : tu ne peux retirer que toi-même' USING ERRCODE = '42501';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_guard_event_task ON public.event_tasks;
CREATE TRIGGER trg_guard_event_task BEFORE INSERT OR UPDATE ON public.event_tasks
  FOR EACH ROW EXECUTE FUNCTION public.guard_event_task();

-- Réponses : date de mise à jour
CREATE OR REPLACE FUNCTION public.guard_event_rsvp()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
BEGIN
  IF TG_OP = 'UPDATE' THEN
    NEW.event_id := OLD.event_id;
    NEW.profile_id := OLD.profile_id;
  END IF;
  NEW.updated_at := now();
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_guard_event_rsvp ON public.event_rsvps;
CREATE TRIGGER trg_guard_event_rsvp BEFORE INSERT OR UPDATE ON public.event_rsvps
  FOR EACH ROW EXECUTE FUNCTION public.guard_event_rsvp();

-- Compte supprimé : on le retire des « qui fait quoi » (pas d'identifiant orphelin)
CREATE OR REPLACE FUNCTION public.forget_event_volunteer()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
BEGIN
  UPDATE public.event_tasks SET volunteers = array_remove(volunteers, OLD.id)
   WHERE OLD.id = ANY (volunteers);
  RETURN OLD;
END;
$$;
DROP TRIGGER IF EXISTS trg_forget_event_volunteer ON public.profiles;
CREATE TRIGGER trg_forget_event_volunteer AFTER DELETE ON public.profiles
  FOR EACH ROW EXECUTE FUNCTION public.forget_event_volunteer();

REVOKE ALL ON FUNCTION public.guard_event() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.guard_event_task() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.guard_event_rsvp() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.forget_event_volunteer() FROM PUBLIC, anon, authenticated;

-- ── Prénoms des personnes d'un événement ────────────────────
-- Pour un événement « famille », les prénoms des autres foyers ne sont pas lisibles
-- dans profiles (règle de la migration 17). Cette fonction ne renvoie QUE le prénom
-- des personnes qui ont répondu ou se sont inscrites, et seulement si on voit l'événement.
CREATE OR REPLACE FUNCTION public.event_people(p_event uuid)
RETURNS TABLE (id uuid, display_name text)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT p.id, p.display_name
    FROM public.profiles p
   WHERE public.can_see_event(p_event)
     AND (
       p.id IN (SELECT r.profile_id FROM public.event_rsvps r WHERE r.event_id = p_event)
       OR p.id IN (SELECT unnest(t.volunteers) FROM public.event_tasks t WHERE t.event_id = p_event)
       OR p.id = (SELECT e.created_by FROM public.events e WHERE e.id = p_event)
     )
$$;
REVOKE ALL ON FUNCTION public.event_people(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.event_people(uuid) TO authenticated;

-- ── S'inscrire / se retirer en une seule opération ──────────
-- (deux personnes qui s'inscrivent en même temps ne s'effacent pas l'une l'autre).
-- SECURITY INVOKER : RLS et le trigger guard_event_task s'appliquent normalement.
CREATE OR REPLACE FUNCTION public.toggle_event_volunteer(p_task uuid, p_on boolean)
RETURNS uuid[]
LANGUAGE sql VOLATILE SECURITY INVOKER SET search_path = '' AS $$
  UPDATE public.event_tasks
     SET volunteers = CASE
           WHEN p_on THEN array_append(array_remove(volunteers, auth.uid()), auth.uid())
           ELSE array_remove(volunteers, auth.uid())
         END
   WHERE id = p_task AND auth.uid() IS NOT NULL
  RETURNING volunteers
$$;
REVOKE ALL ON FUNCTION public.toggle_event_volunteer(uuid, boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.toggle_event_volunteer(uuid, boolean) TO authenticated;
