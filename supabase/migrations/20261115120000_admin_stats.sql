-- ═══════════════════════════════════════════════════════════════
-- Migration 20 — Statistiques pour la page Administration (v1.1.0)
-- ═══════════════════════════════════════════════════════════════
-- admin_stats() : chiffres globaux, réservés au super-admin.
--   - Uniquement des COMPTES : aucun nom, aucun titre, aucun contenu de recette
--     ne sort de la base (le super-admin ne lit pas les recettes privées des familles).
--   - SECURITY DEFINER pour compter toutes les familles malgré la RLS ; la fonction
--     vérifie elle-même is_super_admin() et refuse tout le monde d'autre.
--   - Aucune table créée ni modifiée : rien à ajouter à la RLS.
-- Semaine = du lundi au dimanche (date_trunc('week') de Postgres), heure du serveur (UTC).

CREATE OR REPLACE FUNCTION public.admin_stats()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_week date := date_trunc('week', now())::date;
  v_result jsonb;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Connexion requise' USING ERRCODE = '42501';
  END IF;
  IF NOT public.is_super_admin() THEN
    RAISE EXCEPTION 'Réservé au super-admin' USING ERRCODE = '42501';
  END IF;

  SELECT jsonb_build_object(
    'recettes', jsonb_build_object(
      'famille',       (SELECT count(*) FROM public.recipes WHERE visibility = 'famille'),
      'super_famille', (SELECT count(*) FROM public.recipes WHERE visibility = 'super_famille'),
      'catalogue',     (SELECT count(*) FROM public.recipes WHERE visibility = 'catalogue'),
      'avec_photo',    (SELECT count(*) FROM public.recipes
                          WHERE visibility <> 'catalogue' AND coalesce(image_url, '') <> ''),
      'ajoutees_7j',   (SELECT count(*) FROM public.recipes
                          WHERE visibility <> 'catalogue' AND created_at >= now() - interval '7 days'),
      'ajoutees_30j',  (SELECT count(*) FROM public.recipes
                          WHERE visibility <> 'catalogue' AND created_at >= now() - interval '30 days')
    ),
    'personnes', jsonb_build_object(
      'total',         (SELECT count(*) FROM public.profiles),
      'nouvelles_30j', (SELECT count(*) FROM public.profiles WHERE created_at >= now() - interval '30 days')
    ),
    'planning', jsonb_build_object(
      'repas_semaine',     (SELECT count(*) FROM public.meal_slots s
                              JOIN public.meal_plans p ON p.id = s.meal_plan_id
                              WHERE p.week_start = v_week),
      'familles_actives',  (SELECT count(DISTINCT p.family_id) FROM public.meal_slots s
                              JOIN public.meal_plans p ON p.id = s.meal_plan_id
                              WHERE p.week_start = v_week)
    ),
    'courses', jsonb_build_object(
      'listes_en_cours',   (SELECT count(*) FROM public.shopping_lists WHERE status = 'active'),
      'terminees_30j',     (SELECT count(*) FROM public.shopping_lists
                              WHERE completed_at >= now() - interval '30 days')
    ),
    'invitations', jsonb_build_object(
      'en_attente', (SELECT count(*) FROM public.invitations
                       WHERE used_at IS NULL AND revoked_at IS NULL AND expires_at > now())
    )
  ) INTO v_result;

  RETURN v_result;
END;
$$;

COMMENT ON FUNCTION public.admin_stats() IS
  'Statistiques globales (comptes uniquement) pour la page Administration. Super-admin seulement.';

REVOKE ALL ON FUNCTION public.admin_stats() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_stats() TO authenticated;
