-- Contrôle de la migration 32 (succès). Chaque colonne doit valoir true.
SELECT
  (SELECT bool_and(c.relrowsecurity) FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public' AND c.relname IN ('user_achievements', 'cook_sessions', 'booster_openings')) AS rls_ok,
  (SELECT count(*) = 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'user_achievements') AS trophees_lecture_seule_ok,
  (SELECT count(*) = 2 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'cook_sessions') AS seances_regles_ok,
  (SELECT count(*) = 2 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'booster_openings') AS boosters_regles_ok,
  (SELECT count(*) = 2 FROM pg_trigger WHERE tgname IN ('trg_guard_cook_session', 'trg_guard_booster_opening')) AS gardes_ok,
  (SELECT count(*) = 40 FROM jsonb_object_keys(public.achievement_tiers())) AS quarante_trophees_ok,
  (NOT has_function_privilege('authenticated', 'public.achievement_progress()', 'EXECUTE')
    AND has_function_privilege('authenticated', 'public.refresh_my_achievements()', 'EXECUTE')
    AND NOT has_function_privilege('anon', 'public.my_achievements()', 'EXECUTE')) AS droits_ok,
  (public.current_terms_version() = '2026-11-19') AS version_conditions_ok,
  (position('succes_obtenus' in pg_get_functiondef('public.export_my_data()'::regprocedure)) > 0) AS export_ok,
  (SELECT count(*) = 0 FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public' AND c.relkind = 'r' AND NOT c.relrowsecurity) AS toutes_tables_rls_ok;
