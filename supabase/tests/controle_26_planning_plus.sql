-- Contrôle de la migration 26 (planning_plus, v1.99.0) : entrée/plat/dessert, restes, semaines types.
-- À lancer dans le SQL Editor (ou par le connecteur) : chaque colonne doit valoir true.
SELECT
  (SELECT count(*) = 2 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'meal_slots' AND column_name IN ('course', 'leftover_of')) AS colonnes_ok,
  (SELECT pg_get_constraintdef(oid) LIKE '%course%' FROM pg_constraint
    WHERE conrelid = 'public.meal_slots'::regclass AND conname = 'uq_slot') AS unicite_par_plat_ok,
  (SELECT count(*) = 0 FROM public.meal_slots WHERE course IS NULL OR course NOT IN ('entree', 'plat', 'dessert')) AS creneaux_existants_ok,
  (SELECT count(*) = 2 FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public' AND c.relname IN ('week_templates', 'week_template_slots') AND c.relrowsecurity) AS tables_rls_ok,
  (SELECT count(*) = 3 FROM pg_trigger
    WHERE tgname IN ('trg_guard_meal_slot_leftover', 'trg_guard_week_template', 'trg_guard_week_template_slot')) AS gardes_ok,
  (has_function_privilege('authenticated', 'public.copy_week_slots(uuid, uuid, boolean)', 'EXECUTE')
    AND has_function_privilege('authenticated', 'public.save_week_template(uuid, text)', 'EXECUTE')
    AND has_function_privilege('authenticated', 'public.apply_week_template(uuid, uuid, boolean)', 'EXECUTE')
    AND NOT has_function_privilege('anon', 'public.copy_week_slots(uuid, uuid, boolean)', 'EXECUTE')
    AND NOT has_function_privilege('anon', 'public.fill_plan_slots(uuid, jsonb, boolean)', 'EXECUTE')) AS droits_fonctions_ok,
  (SELECT bool_and(NOT p.prosecdef) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname IN ('fill_plan_slots', 'copy_week_slots', 'save_week_template', 'apply_week_template')) AS fonctions_invoker_ok,
  (SELECT count(*) = 0 FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public' AND c.relkind = 'r' AND NOT c.relrowsecurity) AS toutes_tables_rls_ok;
