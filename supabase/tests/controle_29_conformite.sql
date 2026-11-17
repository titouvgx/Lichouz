-- Contrôle de la migration 29 (conformité). Chaque colonne doit valoir true
-- (tache_nuit_ok vaut false seulement si pg_cron n'existe pas sur la base).
SELECT
  EXISTS (SELECT 1 FROM information_schema.columns
           WHERE table_schema = 'public' AND table_name = 'profiles' AND column_name = 'pseudo') AS pseudo_ok,
  EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname = 'public' AND indexname = 'uq_profiles_pseudo') AS pseudo_unique_ok,
  (SELECT c.relrowsecurity FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public' AND c.relname = 'terms_acceptances') AS acceptations_rls_ok,
  (SELECT count(*) = 2 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'terms_acceptances') AS regles_ok,
  (SELECT count(*) = 2 FROM pg_trigger
    WHERE tgname IN ('trg_guard_profile_pseudo', 'trg_guard_terms_acceptance') AND NOT tgisinternal) AS gardes_ok,
  (public.current_terms_version() = '2026-11-17') AS version_ok,
  (NOT has_function_privilege('authenticated', 'public.purge_expired_data()', 'EXECUTE')
    AND NOT has_function_privilege('anon', 'public.export_my_data()', 'EXECUTE')
    AND has_function_privilege('authenticated', 'public.export_my_data()', 'EXECUTE')
    AND NOT has_function_privilege('anon', 'public.accept_terms(text, text, text)', 'EXECUTE')) AS droits_fonctions_ok,
  (SELECT count(*) = 0 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND tablename = 'terms_acceptances') AS hors_temps_reel_ok,
  EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron')
    AND (SELECT count(*) = 1 FROM cron.job WHERE jobname = 'lichouz-purge') AS tache_nuit_ok,
  (SELECT count(*) = 0 FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public' AND c.relkind = 'r' AND NOT c.relrowsecurity) AS toutes_tables_rls_ok;
