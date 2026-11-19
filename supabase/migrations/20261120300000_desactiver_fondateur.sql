-- ============================================================
-- Migration 36 : le super-admin peut désactiver un fondateur (v2.10.0)
-- ============================================================
-- 1. set_account_disabled : un fondateur peut être désactivé, mais SEULEMENT par un
--    super-admin (ni par un admin de famille, ni par lui-même). Un super-admin reste
--    intouchable. « Retirer » (suppression) un fondateur reste interdit (remove_member).
-- 2. is_founder : un fondateur désactivé perd ses pouvoirs de fondateur (inviter,
--    voir et gérer ses familles). Sans cela, la désactivation serait incomplète :
--    is_founder ne regardait que super_families.founder_id.
-- Contrôle : supabase/tests/controle_36_desactiver_fondateur.sql
-- ============================================================

CREATE OR REPLACE FUNCTION public.is_founder(sfid uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT auth.uid() IS NOT NULL
     AND EXISTS (SELECT 1 FROM public.super_families WHERE id = sfid AND founder_id = auth.uid())
     AND NOT EXISTS (SELECT 1 FROM private.disabled_accounts d WHERE d.user_id = auth.uid())
$$;

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
  IF EXISTS (SELECT 1 FROM public.super_admins WHERE user_id = p_user) THEN
    RAISE EXCEPTION 'Un super-admin ne peut pas être désactivé' USING ERRCODE = '42501';
  END IF;
  IF EXISTS (SELECT 1 FROM public.super_families WHERE founder_id = p_user)
     AND NOT public.is_super_admin() THEN
    RAISE EXCEPTION 'Seul un super-admin peut désactiver un fondateur' USING ERRCODE = '42501';
  END IF;

  IF p_disabled THEN
    INSERT INTO private.disabled_accounts (user_id, disabled_by) VALUES (p_user, auth.uid())
    ON CONFLICT (user_id) DO NOTHING;
  ELSE
    DELETE FROM private.disabled_accounts WHERE user_id = p_user;
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.set_account_disabled(uuid, boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.set_account_disabled(uuid, boolean) TO authenticated;
