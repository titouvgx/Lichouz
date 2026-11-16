-- ============================================================
-- Migration 27 : désactiver un compte (v1.99.0, lot V1-9)
-- ============================================================
-- Un compte désactivé garde tout (profil, recettes, historique) mais ne voit
-- plus rien et ne peut plus rien écrire : il n'est plus « membre » pour les
-- règles RLS. On peut le réactiver à tout moment. (Retirer = supprimer, migration 19.)
--
-- Le drapeau est rangé dans le schéma `private` (jamais exposé par l'API) :
-- personne ne peut se réactiver en modifiant son propre profil.
-- Qui peut (dés)activer : mêmes règles que « retirer un membre » —
-- super-admin, fondateur de la super-famille, admin de la famille.
-- Jamais soi-même, ni un fondateur, ni un super-admin.
--
-- Effet : les fonctions de base des règles (user_family_id, is_family,
-- is_member, is_admin, my_super_family_id) ignorent un compte désactivé.
-- La personne peut seulement relire son propre profil (pour que l'appli
-- lui affiche « compte désactivé ») et appeler my_account_disabled().
-- Contrôle : supabase/tests/controle_27_comptes_desactives.sql
-- ============================================================

CREATE SCHEMA IF NOT EXISTS private;
REVOKE ALL ON SCHEMA private FROM PUBLIC, anon, authenticated;

CREATE TABLE IF NOT EXISTS private.disabled_accounts (
  user_id      uuid        PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  disabled_by  uuid                 REFERENCES auth.users(id) ON DELETE SET NULL,
  disabled_at  timestamptz NOT NULL DEFAULT now()
);
REVOKE ALL ON private.disabled_accounts FROM PUBLIC, anon, authenticated;

-- ── Fonctions de base des règles : un compte désactivé ne compte plus ──
CREATE OR REPLACE FUNCTION public.user_family_id()
RETURNS uuid LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT p.family_id FROM public.profiles p
   WHERE p.id = auth.uid()
     AND NOT EXISTS (SELECT 1 FROM private.disabled_accounts d WHERE d.user_id = p.id)
$$;

CREATE OR REPLACE FUNCTION public.is_family(fid uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.profiles p
     WHERE p.id = auth.uid() AND p.family_id = fid
       AND NOT EXISTS (SELECT 1 FROM private.disabled_accounts d WHERE d.user_id = p.id)
  )
$$;

CREATE OR REPLACE FUNCTION public.is_member()
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.profiles p
     WHERE p.id = auth.uid()
       AND NOT EXISTS (SELECT 1 FROM private.disabled_accounts d WHERE d.user_id = p.id)
  )
$$;

CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.profiles p
     WHERE p.id = auth.uid() AND p.role = 'admin'
       AND NOT EXISTS (SELECT 1 FROM private.disabled_accounts d WHERE d.user_id = p.id)
  )
$$;

CREATE OR REPLACE FUNCTION public.my_super_family_id()
RETURNS uuid LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT f.super_family_id FROM public.profiles p
    JOIN public.families f ON f.id = p.family_id
   WHERE p.id = auth.uid()
     AND NOT EXISTS (SELECT 1 FROM private.disabled_accounts d WHERE d.user_id = p.id)
$$;

-- Relire son propre profil, même désactivé (l'appli affiche alors un message)
DROP POLICY IF EXISTS "profiles_select_self" ON public.profiles;
CREATE POLICY "profiles_select_self" ON public.profiles FOR SELECT USING (id = auth.uid());

-- ── Mon compte est-il désactivé ? ──
CREATE OR REPLACE FUNCTION public.my_account_disabled()
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT EXISTS (SELECT 1 FROM private.disabled_accounts WHERE user_id = auth.uid())
$$;

-- ── Qui a le droit de gérer ce compte ? (mêmes règles que remove_member) ──
CREATE OR REPLACE FUNCTION public.set_account_disabled(p_user uuid, p_disabled boolean)
RETURNS void LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_family uuid;
  v_sf     uuid;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Connexion requise' USING ERRCODE = '42501';
  END IF;
  SELECT p.family_id, f.super_family_id INTO v_family, v_sf
    FROM public.profiles p JOIN public.families f ON f.id = p.family_id
   WHERE p.id = p_user
     FOR UPDATE OF p;
  -- Même message si la personne n'existe pas ou si on n'a pas le droit
  IF NOT FOUND OR NOT (
    public.is_super_admin()
    OR public.is_founder(v_sf)
    OR (public.is_admin() AND public.is_family(v_family))
  ) THEN
    RAISE EXCEPTION 'Membre introuvable' USING ERRCODE = '42501';
  END IF;
  IF p_user = auth.uid() THEN
    RAISE EXCEPTION 'Tu ne peux pas désactiver ton propre compte' USING ERRCODE = '42501';
  END IF;
  IF EXISTS (SELECT 1 FROM public.super_families WHERE founder_id = p_user) THEN
    RAISE EXCEPTION 'Le compte d''un fondateur ne peut pas être désactivé' USING ERRCODE = '42501';
  END IF;
  IF EXISTS (SELECT 1 FROM public.super_admins WHERE user_id = p_user) THEN
    RAISE EXCEPTION 'Un super-admin ne peut pas être désactivé' USING ERRCODE = '42501';
  END IF;

  IF p_disabled THEN
    INSERT INTO private.disabled_accounts (user_id, disabled_by) VALUES (p_user, auth.uid())
    ON CONFLICT (user_id) DO NOTHING;
  ELSE
    DELETE FROM private.disabled_accounts WHERE user_id = p_user;
  END IF;
END;
$$;

-- ── Membres désactivés d'une famille (pour l'écran Ma famille / Administration) ──
-- Vide si on n'a pas le droit de gérer cette famille.
CREATE OR REPLACE FUNCTION public.disabled_members(p_family uuid)
RETURNS TABLE (user_id uuid, disabled_at timestamptz)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT d.user_id, d.disabled_at
    FROM private.disabled_accounts d
    JOIN public.profiles p ON p.id = d.user_id
    JOIN public.families f ON f.id = p.family_id
   WHERE p.family_id = p_family
     AND (public.is_super_admin()
          OR public.is_founder(f.super_family_id)
          OR (public.is_admin() AND public.is_family(p_family)))
$$;

REVOKE ALL ON FUNCTION public.my_account_disabled() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.set_account_disabled(uuid, boolean) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.disabled_members(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.my_account_disabled() TO authenticated;
GRANT EXECUTE ON FUNCTION public.set_account_disabled(uuid, boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION public.disabled_members(uuid) TO authenticated;
