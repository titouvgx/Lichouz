-- ============================================================
-- Contrôle de la migration 21 (supprimer_mon_compte) — LECTURE SEULE
-- ============================================================
-- À lancer dans le SQL Editor juste après la migration 21.
-- Attendu : une seule ligne, toutes les colonnes à true.
-- ============================================================
SELECT
  (SELECT count(*) = 1
     FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = 'delete_my_account' AND p.prosecdef
  ) AS fonction_ok,
  (SELECT coalesce(bool_and(NOT has_function_privilege('anon', p.oid, 'EXECUTE')
                            AND has_function_privilege('authenticated', p.oid, 'EXECUTE')), false)
     FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = 'delete_my_account'
  ) AS droits_execution_ok,
  -- La fonction tourne avec les droits de son propriétaire : il doit pouvoir supprimer un compte
  (SELECT coalesce(bool_and(has_table_privilege(p.proowner, 'auth.users', 'DELETE')), false)
     FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = 'delete_my_account'
  ) AS suppression_compte_ok,
  -- Essais ratés : table cachée (schéma private, RLS activé, aucun droit pour l'API)
  (SELECT c.relrowsecurity FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'private' AND c.relname = 'account_deletion_attempts'
  ) AS essais_rls_ok,
  NOT has_schema_privilege('anon', 'private', 'USAGE')
    AND NOT has_schema_privilege('authenticated', 'private', 'USAGE') AS schema_private_ferme_ok,
  -- Vérification du mot de passe : tous les mots de passe sont bien en bcrypt ($2…),
  -- le seul format que delete_my_account sait vérifier
  NOT EXISTS (SELECT 1 FROM auth.users
               WHERE encrypted_password IS NOT NULL AND encrypted_password <> ''
                 AND encrypted_password NOT LIKE '$2%') AS mots_de_passe_bcrypt_ok,
  extensions.crypt('essai', extensions.gen_salt('bf')) LIKE '$2%' AS crypt_disponible_ok;
