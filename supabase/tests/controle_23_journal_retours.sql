-- ============================================================
-- Contrôle de la migration 23 (journal_retours) — LECTURE SEULE
-- ============================================================
-- À lancer dans le SQL Editor juste après la migration 23.
-- Attendu : une seule ligne, toutes les colonnes à true.
-- ============================================================
SELECT
  (SELECT count(*) = 2 FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public' AND c.relname IN ('app_errors', 'feedback') AND c.relrowsecurity) AS tables_rls_ok,
  (SELECT count(*) = 3 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'app_errors') AS regles_erreurs_ok,
  NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'app_errors'
               AND cmd IN ('UPDATE', 'ALL')) AS erreurs_non_modifiables_ok,
  (SELECT count(*) = 4 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'feedback') AS regles_retours_ok,
  NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename IN ('app_errors', 'feedback')
               AND 'anon' = ANY (roles)) AS rien_pour_anonymes_ok,
  (SELECT count(*) = 3 FROM pg_trigger
    WHERE tgname IN ('trg_app_error_insert', 'trg_feedback_insert', 'trg_feedback_update') AND NOT tgisinternal) AS gardes_ok,
  (SELECT count(*) = 2 FROM pg_constraint
    WHERE contype = 'f' AND confdeltype = 'c'
      AND conrelid IN ('public.app_errors'::regclass, 'public.feedback'::regclass)
      AND confrelid = 'public.profiles'::regclass) AS effacement_avec_le_compte_ok,
  (SELECT count(*) = 0 FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public' AND c.relkind = 'r' AND NOT c.relrowsecurity) AS toutes_tables_rls_ok;
