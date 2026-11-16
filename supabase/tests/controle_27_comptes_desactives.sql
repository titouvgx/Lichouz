-- Contrôle de la migration 27 (comptes_desactives, v1.99.0).
-- À lancer dans le SQL Editor (ou par le connecteur) : chaque colonne doit valoir true.
SELECT
  to_regclass('private.disabled_accounts') IS NOT NULL AS table_privee_ok,
  NOT has_schema_privilege('authenticated', 'private', 'USAGE')
    AND NOT has_schema_privilege('anon', 'private', 'USAGE') AS schema_prive_ferme_ok,
  (SELECT count(*) = 0 FROM private.disabled_accounts) AS aucun_compte_desactive_au_depart_ok,
  (SELECT bool_and(pg_get_functiondef(p.oid) LIKE '%disabled_accounts%') FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname IN ('user_family_id', 'is_family', 'is_member', 'is_admin', 'my_super_family_id')) AS regles_tiennent_compte_ok,
  EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'profiles' AND policyname = 'profiles_select_self') AS relire_son_profil_ok,
  (has_function_privilege('authenticated', 'public.set_account_disabled(uuid, boolean)', 'EXECUTE')
    AND has_function_privilege('authenticated', 'public.disabled_members(uuid)', 'EXECUTE')
    AND has_function_privilege('authenticated', 'public.my_account_disabled()', 'EXECUTE')
    AND NOT has_function_privilege('anon', 'public.set_account_disabled(uuid, boolean)', 'EXECUTE')
    AND NOT has_function_privilege('anon', 'public.disabled_members(uuid)', 'EXECUTE')
    AND NOT has_function_privilege('anon', 'public.my_account_disabled()', 'EXECUTE')) AS droits_fonctions_ok,
  (SELECT count(*) = 0 FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public' AND c.relkind = 'r' AND NOT c.relrowsecurity) AS toutes_tables_rls_ok;
