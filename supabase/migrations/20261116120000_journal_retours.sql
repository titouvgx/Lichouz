-- ═══════════════════════════════════════════════════════════════
-- Migration 23 — Journal des erreurs et retours des utilisateurs (v1.6.0)
-- ═══════════════════════════════════════════════════════════════
-- 1. public.app_errors : les erreurs de l'appli sur les téléphones de la famille.
--    - Écrit par toute personne connectée (pour elle-même), lu et purgé par le
--      super-admin seulement. Aucune modification possible.
--    - user_id / family_id / created_at forcés par la base (jamais crus du téléphone).
--    - 30 erreurs par personne et par heure au maximum (au-delà : refus).
--    - Conservées 90 jours (purge automatique à chaque nouvelle erreur).
--    - Le contenu est nettoyé par l'appli avant l'envoi (pas de jeton
--      d'invitation, pas d'e-mail, pas de paramètres d'adresse).
-- 2. public.feedback : idées, bugs et remarques envoyés depuis l'appli.
--    - Écrit par toute personne connectée (pour elle-même) ; chacun relit les
--      siens ; le super-admin lit tout, change le statut, supprime.
--    - 10 retours par personne et par 24 h au maximum.
-- Les deux tables suivent le compte : supprimer un compte supprime ses erreurs
-- et ses retours (ON DELETE CASCADE, droit à l'effacement).
-- Anonymes : aucune règle RLS, donc rien (ni lecture ni écriture).
-- Contrôle : supabase/tests/controle_23_journal_retours.sql

-- ── 1. Journal des erreurs ───────────────────────────────────
CREATE TABLE IF NOT EXISTS public.app_errors (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  created_at  timestamptz NOT NULL DEFAULT now(),
  user_id     uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  family_id   uuid REFERENCES public.families(id) ON DELETE SET NULL,
  app_version text CHECK (app_version IS NULL OR char_length(app_version) <= 20),
  route       text CHECK (route IS NULL OR char_length(route) <= 100),
  message     text NOT NULL CHECK (char_length(message) BETWEEN 1 AND 500),
  stack       text CHECK (stack IS NULL OR char_length(stack) <= 4000),
  user_agent  text CHECK (user_agent IS NULL OR char_length(user_agent) <= 300)
);
COMMENT ON TABLE public.app_errors IS
  'Erreurs de l''appli (v1.6.0). Écrites par la personne connectée, lues par le super-admin, gardées 90 jours.';
CREATE INDEX IF NOT EXISTS idx_app_errors_created ON public.app_errors(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_app_errors_user ON public.app_errors(user_id, created_at DESC);

-- Comme les autres tables du projet : droits Supabase par défaut, tout est filtré
-- par les règles RLS (aucune règle pour anon = rien ; aucune règle UPDATE = rien).
ALTER TABLE public.app_errors ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "app_errors_insert" ON public.app_errors;
CREATE POLICY "app_errors_insert" ON public.app_errors
  FOR INSERT TO authenticated WITH CHECK (user_id = auth.uid() AND public.is_member());
DROP POLICY IF EXISTS "app_errors_select" ON public.app_errors;
CREATE POLICY "app_errors_select" ON public.app_errors
  FOR SELECT TO authenticated USING (public.is_super_admin());
DROP POLICY IF EXISTS "app_errors_delete" ON public.app_errors;
CREATE POLICY "app_errors_delete" ON public.app_errors
  FOR DELETE TO authenticated USING (public.is_super_admin());

CREATE OR REPLACE FUNCTION public.guard_app_error_insert()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
BEGIN
  -- Sans utilisateur (SQL Editor, service) : valeurs gardées telles quelles.
  -- Un anonyme est ensuite refusé par RLS (aucune règle pour lui).
  IF auth.uid() IS NULL THEN
    RETURN NEW;
  END IF;
  NEW.user_id := auth.uid();
  NEW.created_at := now();
  NEW.family_id := (SELECT p.family_id FROM public.profiles p WHERE p.id = auth.uid());
  IF (SELECT count(*) FROM public.app_errors e
       WHERE e.user_id = NEW.user_id AND e.created_at > now() - interval '1 hour') >= 30 THEN
    RAISE EXCEPTION 'Trop d''erreurs envoyées : réessaie plus tard' USING ERRCODE = '54000';
  END IF;
  DELETE FROM public.app_errors WHERE created_at < now() - interval '90 days';
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION public.guard_app_error_insert() FROM PUBLIC, anon, authenticated;
DROP TRIGGER IF EXISTS trg_app_error_insert ON public.app_errors;
CREATE TRIGGER trg_app_error_insert
  BEFORE INSERT ON public.app_errors
  FOR EACH ROW EXECUTE FUNCTION public.guard_app_error_insert();

-- ── 2. Retours des utilisateurs ──────────────────────────────
CREATE TABLE IF NOT EXISTS public.feedback (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  created_at  timestamptz NOT NULL DEFAULT now(),
  user_id     uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  family_id   uuid REFERENCES public.families(id) ON DELETE SET NULL,
  kind        text NOT NULL DEFAULT 'idee' CHECK (kind IN ('idee', 'bug', 'autre')),
  message     text NOT NULL CHECK (char_length(btrim(message)) BETWEEN 1 AND 2000),
  app_version text CHECK (app_version IS NULL OR char_length(app_version) <= 20),
  status      text NOT NULL DEFAULT 'nouveau' CHECK (status IN ('nouveau', 'lu', 'fait'))
);
COMMENT ON TABLE public.feedback IS
  'Idées, bugs, remarques envoyés depuis l''appli (v1.6.0). L''auteur relit les siens ; le super-admin lit tout.';
CREATE INDEX IF NOT EXISTS idx_feedback_created ON public.feedback(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_feedback_user ON public.feedback(user_id, created_at DESC);

ALTER TABLE public.feedback ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "feedback_insert" ON public.feedback;
CREATE POLICY "feedback_insert" ON public.feedback
  FOR INSERT TO authenticated WITH CHECK (user_id = auth.uid() AND public.is_member());
DROP POLICY IF EXISTS "feedback_select" ON public.feedback;
CREATE POLICY "feedback_select" ON public.feedback
  FOR SELECT TO authenticated USING (user_id = auth.uid() OR public.is_super_admin());
DROP POLICY IF EXISTS "feedback_update" ON public.feedback;
CREATE POLICY "feedback_update" ON public.feedback
  FOR UPDATE TO authenticated USING (public.is_super_admin()) WITH CHECK (public.is_super_admin());
DROP POLICY IF EXISTS "feedback_delete" ON public.feedback;
CREATE POLICY "feedback_delete" ON public.feedback
  FOR DELETE TO authenticated USING (public.is_super_admin());

CREATE OR REPLACE FUNCTION public.guard_feedback_insert()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN NEW;
  END IF;
  NEW.user_id := auth.uid();
  NEW.created_at := now();
  NEW.status := 'nouveau';
  NEW.message := btrim(NEW.message);
  NEW.family_id := (SELECT p.family_id FROM public.profiles p WHERE p.id = auth.uid());
  IF (SELECT count(*) FROM public.feedback f
       WHERE f.user_id = NEW.user_id AND f.created_at > now() - interval '24 hours') >= 10 THEN
    RAISE EXCEPTION 'Tu as déjà envoyé 10 retours aujourd''hui : merci, réessaie demain'
      USING ERRCODE = '54000';
  END IF;
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION public.guard_feedback_insert() FROM PUBLIC, anon, authenticated;
DROP TRIGGER IF EXISTS trg_feedback_insert ON public.feedback;
CREATE TRIGGER trg_feedback_insert
  BEFORE INSERT ON public.feedback
  FOR EACH ROW EXECUTE FUNCTION public.guard_feedback_insert();

-- Modification d'un retour (super-admin) : seul le statut peut changer.
-- Exception : family_id passe à NULL quand la famille est supprimée (ON DELETE
-- SET NULL) ; sans elle, supprimer une famille citée par un retour échouerait.
CREATE OR REPLACE FUNCTION public.guard_feedback_update()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
BEGIN
  IF (NEW.id, NEW.created_at, NEW.user_id, NEW.kind, NEW.message, NEW.app_version)
     IS DISTINCT FROM
     (OLD.id, OLD.created_at, OLD.user_id, OLD.kind, OLD.message, OLD.app_version)
     OR (NEW.family_id IS DISTINCT FROM OLD.family_id AND NEW.family_id IS NOT NULL) THEN
    RAISE EXCEPTION 'Seul le statut d''un retour peut changer' USING ERRCODE = '42501';
  END IF;
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION public.guard_feedback_update() FROM PUBLIC, anon, authenticated;
DROP TRIGGER IF EXISTS trg_feedback_update ON public.feedback;
CREATE TRIGGER trg_feedback_update
  BEFORE UPDATE ON public.feedback
  FOR EACH ROW EXECUTE FUNCTION public.guard_feedback_update();
