-- ============================================================
-- Contrôle de la migration 24 (invitation_email) — LECTURE SEULE
-- ============================================================
-- À lancer dans le SQL Editor juste après la migration 24.
-- Attendu : une seule ligne, toutes les colonnes à true.
-- ============================================================
SELECT
  (SELECT count(*) = 2 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'invitations'
      AND column_name IN ('email_hash', 'email_hint')) AS colonnes_ok,
  NOT EXISTS (SELECT 1 FROM information_schema.columns
               WHERE table_schema = 'public' AND table_name = 'invitations' AND column_name = 'email') AS adresse_jamais_gardee_ok,
  (SELECT count(*) = 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = 'create_invitation') AS une_seule_create_invitation_ok,
  (SELECT bool_and(pg_get_function_identity_arguments(p.oid) LIKE '%p_email text%'
                   AND NOT has_function_privilege('anon', p.oid, 'EXECUTE')
                   AND has_function_privilege('authenticated', p.oid, 'EXECUTE'))
     FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = 'create_invitation') AS create_invitation_ok,
  (SELECT bool_and(pg_get_function_result(p.oid) LIKE '%email_hint%'
                   AND has_function_privilege('anon', p.oid, 'EXECUTE'))
     FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = 'invitation_info') AS invitation_info_ok,
  (SELECT bool_and(pg_get_functiondef(p.oid) LIKE '%invitation_email_hash%'
                   AND NOT has_function_privilege('authenticated', p.oid, 'EXECUTE')
                   AND has_function_privilege('service_role', p.oid, 'EXECUTE'))
     FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = 'consume_invitation') AS consume_verifie_adresse_ok,
  (SELECT bool_and(pg_get_functiondef(p.oid) LIKE '%seulement toi-même%')
     FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = 'guard_item_checked_by') AS coche_a_son_nom_ok,
  (SELECT count(*) = 2 FROM pg_policies
    WHERE schemaname = 'storage' AND tablename = 'objects'
      AND policyname IN ('recipe_photos_select', 'recipe_photos_delete')
      AND qual LIKE '%owner%') AS photos_orphelines_ok,
  (SELECT count(*) = 0 FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public' AND c.relkind = 'r' AND NOT c.relrowsecurity) AS toutes_tables_rls_ok;
