-- Contrôle de la migration 37 (validation des recettes publiques). Chaque colonne doit valoir true.
SELECT
  EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'recipes' AND column_name = 'public_status') AS colonne_statut_ok,
  pg_get_functiondef('public.guard_recipe_write()'::regprocedure) LIKE '%lichouz.public_op%' AS garde_publication_ok,
  pg_get_functiondef('public.can_read_recipe(uuid)'::regprocedure) LIKE '%public_status = ''validee''%' AS lecture_validees_ok,
  pg_get_functiondef('public.request_public_publication(uuid)'::regprocedure) LIKE '%>= 3%' AS limite_3_ok,
  has_function_privilege('authenticated', 'public.request_public_publication(uuid)', 'EXECUTE')
    AND has_function_privilege('authenticated', 'public.review_public_recipe(uuid, boolean, text)', 'EXECUTE')
    AND NOT has_function_privilege('anon', 'public.request_public_publication(uuid)', 'EXECUTE')
    AND NOT has_function_privilege('anon', 'public.review_public_recipe(uuid, boolean, text)', 'EXECUTE')
    AND NOT has_function_privilege('anon', 'public.public_review_queue()', 'EXECUTE') AS droits_ok,
  (SELECT count(*) FROM public.recipes WHERE public_status IS NOT NULL) = 0 AS aucune_recette_publiee_au_depart_ok;
