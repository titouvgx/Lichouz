-- Contrôle de la migration 30 (étoiles). Chaque colonne doit valoir true.
SELECT
  (SELECT c.relrowsecurity FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public' AND c.relname = 'recipe_ratings') AS notes_rls_ok,
  (SELECT count(*) = 4 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'recipe_ratings') AS regles_ok,
  EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_guard_recipe_rating') AS garde_ok,
  (NOT has_function_privilege('anon', 'public.recipe_rating_stats(uuid[])', 'EXECUTE')
    AND has_function_privilege('authenticated', 'public.recipe_rating_stats(uuid[])', 'EXECUTE')) AS droits_ok,
  (position('notes_donnees' in pg_get_functiondef('public.export_my_data()'::regprocedure)) > 0) AS export_ok,
  (SELECT count(*) = 0 FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public' AND c.relkind = 'r' AND NOT c.relrowsecurity) AS toutes_tables_rls_ok;
