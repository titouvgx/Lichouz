-- Contrôle de la migration 36 (désactiver un fondateur, v2.10.0). Chaque colonne doit valoir true.
SELECT
  pg_get_functiondef('public.is_founder(uuid)'::regprocedure) LIKE '%disabled_accounts%' AS fondateur_desactive_perd_ses_pouvoirs_ok,
  pg_get_functiondef('public.set_account_disabled(uuid, boolean)'::regprocedure) LIKE '%Seul un super-admin peut désactiver un fondateur%' AS regle_fondateur_ok,
  pg_get_functiondef('public.set_account_disabled(uuid, boolean)'::regprocedure) LIKE '%Un super-admin ne peut pas être désactivé%' AS super_admin_protege_ok,
  has_function_privilege('authenticated', 'public.set_account_disabled(uuid, boolean)', 'EXECUTE')
    AND NOT has_function_privilege('anon', 'public.set_account_disabled(uuid, boolean)', 'EXECUTE') AS droits_ok;
