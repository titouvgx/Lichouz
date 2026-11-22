-- ============================================================
-- Migration 38 : le super-admin déplace un foyer d'une famille à une autre
-- ============================================================
-- TEMPORAIRE (outil de mise en place, à retirer plus tard : DROP FUNCTION public.move_family).
-- Réservée au super-admin (42501 sinon). Le trigger guard_family_write garde la limite
-- de 3 foyers par famille (sauf famille dont le fondateur est super-admin).
-- Les recettes « famille » (visibility = super_famille) suivent le foyer : elles sont
-- lues selon la famille du foyer, rien n'est copié ni supprimé.
-- ============================================================

CREATE OR REPLACE FUNCTION public.move_family(p_family uuid, p_super_family uuid)
RETURNS void LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_old uuid;
BEGIN
  IF auth.uid() IS NULL OR NOT public.is_super_admin() THEN
    RAISE EXCEPTION 'Réservé au super-admin' USING ERRCODE = '42501';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.super_families WHERE id = p_super_family) THEN
    RAISE EXCEPTION 'Famille introuvable' USING ERRCODE = 'P0002';
  END IF;
  SELECT super_family_id INTO v_old FROM public.families WHERE id = p_family;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Foyer introuvable' USING ERRCODE = 'P0002';
  END IF;
  IF v_old = p_super_family THEN
    RAISE EXCEPTION 'Ce foyer est déjà dans cette famille' USING ERRCODE = 'check_violation';
  END IF;
  UPDATE public.families SET super_family_id = p_super_family WHERE id = p_family;
END $$;

REVOKE ALL ON FUNCTION public.move_family(uuid, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.move_family(uuid, uuid) TO authenticated;
