-- ═══════════════════════════════════════════════════════════════
-- Migration 21 — « Supprimer mon compte » (v1.2.0)
-- ═══════════════════════════════════════════════════════════════
-- delete_my_account(p_password) : la personne connectée supprime SON compte.
--   Refusé (message clair, rien n'est touché) :
--     - super-admin ou fondateur d'une super-famille (rôle à transmettre d'abord, hors appli) ;
--     - dernier admin d'une famille qui a encore d'autres membres ;
--     - connecté sans profil.
--   Mot de passe redemandé et vérifié ICI (bcrypt de Supabase, extensions.crypt) :
--   un téléphone déverrouillé ne suffit pas. 5 erreurs en 15 minutes → bloqué
--   15 minutes (sinon la fonction servirait à deviner le mot de passe sans
--   passer par les limites de Supabase Auth).
--   Résultat : 'supprime' | 'mot_de_passe_incorrect' | 'trop_d_essais'
--   (pas d'erreur pour un mauvais mot de passe : l'essai raté doit être enregistré,
--   une erreur annulerait l'enregistrement).
--   Effet, comme remove_member : compte Auth supprimé → profil en cascade,
--   recettes gardées (auteur NULL), « coché par » / cuisinier → NULL,
--   liens d'invitation créés par la personne supprimés. Si elle était seule
--   dans sa famille, la famille reste (vide) : le fondateur la supprime ensuite
--   avec delete_family.
-- Verrou sur la ligne de la famille : deux admins qui partent en même temps
-- passent l'un après l'autre (le second voit que l'autre est parti → refusé).
--
-- Essais ratés : schéma « private » (jamais exposé par l'API, aucun droit pour
-- anon / authenticated), RLS activé quand même, aucune règle.

CREATE SCHEMA IF NOT EXISTS private;
REVOKE ALL ON SCHEMA private FROM PUBLIC, anon, authenticated;

CREATE TABLE IF NOT EXISTS private.account_deletion_attempts (
  id         bigint      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  user_id    uuid        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS account_deletion_attempts_user_idx
  ON private.account_deletion_attempts (user_id, created_at);
ALTER TABLE private.account_deletion_attempts ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private.account_deletion_attempts FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.delete_my_account(p_password text)
RETURNS text LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_me     uuid := auth.uid();
  v_family uuid;
  v_role   text;
  v_hash   text;
BEGIN
  IF v_me IS NULL THEN
    RAISE EXCEPTION 'Connexion requise' USING ERRCODE = '42501';
  END IF;

  SELECT p.family_id INTO v_family FROM public.profiles p WHERE p.id = v_me;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Profil introuvable' USING ERRCODE = '42501';
  END IF;
  -- Verrou famille puis profil (même ordre pour tout le monde : pas d'interblocage)
  PERFORM 1 FROM public.families f WHERE f.id = v_family FOR UPDATE;
  SELECT p.role INTO v_role FROM public.profiles p WHERE p.id = v_me FOR UPDATE;

  IF EXISTS (SELECT 1 FROM public.super_admins WHERE user_id = v_me) THEN
    RAISE EXCEPTION 'Tu es super-admin : transmets d''abord ce rôle (dans Supabase)' USING ERRCODE = 'check_violation';
  END IF;
  IF EXISTS (SELECT 1 FROM public.super_families WHERE founder_id = v_me) THEN
    RAISE EXCEPTION 'Tu es fondateur : demande d''abord au super-admin de transmettre ton rôle' USING ERRCODE = 'check_violation';
  END IF;
  IF v_role = 'admin'
     AND EXISTS (SELECT 1 FROM public.profiles p WHERE p.family_id = v_family AND p.id <> v_me)
     AND NOT EXISTS (SELECT 1 FROM public.profiles p
                     WHERE p.family_id = v_family AND p.id <> v_me AND p.role = 'admin') THEN
    RAISE EXCEPTION 'Tu es le dernier admin de ta famille : nomme d''abord un autre admin dans Ma famille'
      USING ERRCODE = 'check_violation';
  END IF;

  -- Limite d'essais (on oublie les essais de plus d'un jour)
  DELETE FROM private.account_deletion_attempts
   WHERE user_id = v_me AND created_at < now() - interval '1 day';
  IF (SELECT count(*) FROM private.account_deletion_attempts
       WHERE user_id = v_me AND created_at > now() - interval '15 minutes') >= 5 THEN
    RETURN 'trop_d_essais';
  END IF;

  SELECT u.encrypted_password INTO v_hash FROM auth.users u WHERE u.id = v_me;
  IF p_password IS NULL OR p_password = '' OR v_hash IS NULL OR v_hash NOT LIKE '$2%'
     OR extensions.crypt(p_password, v_hash) IS DISTINCT FROM v_hash THEN
    INSERT INTO private.account_deletion_attempts (user_id) VALUES (v_me);
    RETURN 'mot_de_passe_incorrect';
  END IF;

  DELETE FROM auth.users WHERE id = v_me;
  RETURN 'supprime';
END;
$$;

REVOKE ALL ON FUNCTION public.delete_my_account(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.delete_my_account(text) TO authenticated;
