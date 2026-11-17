-- Contrôle de la migration 31 (commentaires). Chaque colonne doit valoir true.
SELECT
  (SELECT c.relrowsecurity FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public' AND c.relname = 'recipe_comments') AS commentaires_rls_ok,
  (SELECT count(*) = 3 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'recipe_comments') AS regles_ok,
  NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'recipe_comments' AND cmd = 'UPDATE') AS pas_de_modification_ok,
  EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_guard_recipe_comment') AS garde_ok,
  (NOT has_function_privilege('anon', 'public.recipe_comments_list(uuid)', 'EXECUTE')
    AND has_function_privilege('authenticated', 'public.recipe_comments_list(uuid)', 'EXECUTE')) AS droits_ok,
  (public.current_terms_version() = '2026-11-18') AS version_conditions_ok,
  (position('commentaires_ecrits' in pg_get_functiondef('public.export_my_data()'::regprocedure)) > 0) AS export_ok,
  (SELECT count(*) = 0 FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public' AND c.relkind = 'r' AND NOT c.relrowsecurity) AS toutes_tables_rls_ok;
