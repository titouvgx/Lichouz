-- Contrôle de la migration 25 (étiquettes) et de la migration générée des étiquettes du catalogue.
-- À lancer dans le SQL Editor (ou par le connecteur) : chaque colonne doit valoir true.
SELECT
  (SELECT count(*) = 4 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'recipes'
      AND column_name IN ('diets', 'origin', 'themes', 'budget')) AS colonnes_ok,
  (SELECT count(*) = 4 FROM pg_constraint
    WHERE conrelid = 'public.recipes'::regclass
      AND conname IN ('recipes_diets_list', 'recipes_origin_list', 'recipes_themes_list', 'recipes_budget_range')) AS contraintes_ok,
  has_function_privilege('authenticated', 'public.tags_in_list(text[], text[])', 'EXECUTE') AS fonction_executable_ok,
  NOT public.tags_in_list(ARRAY['pirate'], ARRAY['vegan'])
    AND NOT public.tags_in_list(ARRAY['vegan', 'vegan'], ARRAY['vegan'])
    AND public.tags_in_list('{}'::text[], ARRAY['vegan']) AS liste_fixe_ok,
  (SELECT string_agg(name, ' | ' ORDER BY position, name) FROM public.recipe_categories)
    = 'Apéritif | Entrée | Plat | Accompagnement | Sauce | Dessert | Petit-déj & goûter | Boisson & cocktail' AS types_de_plat_ok,
  (SELECT count(*) = 50 FROM public.recipes
    WHERE visibility = 'catalogue' AND (cardinality(themes) > 0 OR budget IS NOT NULL)) AS catalogue_etiquete_ok,
  (SELECT count(*) = 0 FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public' AND c.relkind = 'r' AND NOT c.relrowsecurity) AS toutes_tables_rls_ok;
