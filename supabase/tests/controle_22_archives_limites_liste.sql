-- ============================================================
-- Contrôle de la migration 22 (archives_limites_liste) — LECTURE SEULE
-- ============================================================
-- À lancer dans le SQL Editor juste après la migration 22.
-- Attendu : une seule ligne, toutes les colonnes à true.
-- ============================================================
SELECT
  EXISTS (SELECT 1 FROM information_schema.columns
           WHERE table_schema = 'public' AND table_name = 'recipes' AND column_name = 'archived_at') AS colonne_archive_ok,
  NOT EXISTS (SELECT 1 FROM pg_policies
               WHERE schemaname = 'public' AND tablename = 'recipes' AND cmd = 'DELETE') AS plus_de_suppression_directe_ok,
  (SELECT count(*) = 4 FROM pg_constraint
    WHERE conname IN ('recipes_title_length', 'recipe_ingredients_text_length',
                      'recipe_steps_text_length', 'shopping_list_items_text_length')
      AND convalidated) AS limites_texte_ok,
  (SELECT count(*) = 2 FROM pg_trigger
    WHERE tgname IN ('trg_recipe_ingredients_count', 'trg_recipe_steps_count') AND NOT tgisinternal) AS limites_nombre_ok,
  EXISTS (SELECT 1 FROM information_schema.columns
           WHERE table_schema = 'public' AND table_name = 'shopping_list_items'
             AND column_name = 'source_recipe_ids') AS colonne_origines_ok,
  NOT EXISTS (SELECT 1 FROM public.shopping_list_items
               WHERE source_recipe_id IS NOT NULL AND NOT (source_recipe_id = ANY (source_recipe_ids))) AS origines_reprises_ok,
  (SELECT coalesce(bool_and(NOT p.prosecdef
                            AND NOT has_function_privilege('anon', p.oid, 'EXECUTE')
                            AND has_function_privilege('authenticated', p.oid, 'EXECUTE')), false)
     FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = 'replace_planned_items') AS fonction_liste_ok,
  (SELECT count(*) = 0 FROM public.recipes WHERE archived_at IS NOT NULL) AS aucune_archive_au_depart_ok,
  (SELECT count(*) = 0 FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public' AND c.relkind = 'r' AND NOT c.relrowsecurity) AS toutes_tables_rls_ok;
