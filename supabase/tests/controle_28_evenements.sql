-- Contrôle de la migration 28 (événements). Chaque colonne doit valoir true.
SELECT
  (SELECT count(*) = 3 FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public' AND c.relname IN ('events', 'event_tasks', 'event_rsvps') AND c.relrowsecurity) AS tables_rls_ok,
  (SELECT count(*) = 12 FROM pg_policies
    WHERE schemaname = 'public' AND tablename IN ('events', 'event_tasks', 'event_rsvps')) AS regles_ok,
  (SELECT count(*) = 3 FROM pg_trigger
    WHERE tgname IN ('trg_guard_event', 'trg_guard_event_task', 'trg_guard_event_rsvp') AND NOT tgisinternal) AS gardes_ok,
  EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_forget_event_volunteer') AS oubli_compte_ok,
  (NOT has_function_privilege('anon', 'public.can_see_event(uuid)', 'EXECUTE')
    AND has_function_privilege('authenticated', 'public.can_see_event(uuid)', 'EXECUTE')
    AND NOT has_function_privilege('anon', 'public.event_people(uuid)', 'EXECUTE')
    AND NOT has_function_privilege('authenticated', 'public.guard_event_task()', 'EXECUTE')) AS droits_fonctions_ok,
  (SELECT count(*) = 0 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND tablename IN ('events', 'event_tasks', 'event_rsvps')) AS hors_temps_reel_ok,
  (SELECT count(*) = 0 FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public' AND c.relkind = 'r' AND NOT c.relrowsecurity) AS toutes_tables_rls_ok;
