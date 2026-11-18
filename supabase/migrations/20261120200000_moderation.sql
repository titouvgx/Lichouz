-- ============================================================
-- Migration 35 : modération par le super-admin (v2.9.0)
-- ============================================================
-- Trois fonctions, TOUTES réservées au super-admin (refus 42501 sinon) :
--   moderation_comments(limit)       derniers commentaires de toutes les familles
--   moderation_delete_comment(id)    supprime un commentaire (0 ligne = erreur, jamais « réussi »)
--   moderation_accounts()            comptes (pseudo, foyer, rôle, désactivé ou non)
-- Désactiver / réactiver un compte : set_account_disabled (déjà existante, migration 26).
-- Aucune table nouvelle, aucun droit direct ajouté : l'accès passe par ces fonctions.
-- ============================================================

CREATE OR REPLACE FUNCTION public.moderation_comments(p_limit integer DEFAULT 100)
RETURNS TABLE (id uuid, body text, created_at timestamptz, recipe_id uuid, recipe_title text,
               author_id uuid, author_pseudo text, author_name text, family_name text, disabled boolean)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
BEGIN
  IF auth.uid() IS NULL OR NOT public.is_super_admin() THEN
    RAISE EXCEPTION 'Réservé au super-admin' USING ERRCODE = '42501';
  END IF;
  RETURN QUERY
    SELECT c.id, c.body, c.created_at, c.recipe_id, r.title,
           c.author_id, a.pseudo, a.display_name, f.name,
           EXISTS (SELECT 1 FROM private.disabled_accounts d WHERE d.user_id = c.author_id)
      FROM public.recipe_comments c
      JOIN public.recipes r ON r.id = c.recipe_id
      JOIN public.profiles a ON a.id = c.author_id
      LEFT JOIN public.families f ON f.id = a.family_id
     ORDER BY c.created_at DESC
     LIMIT least(greatest(coalesce(p_limit, 100), 1), 300);
END $$;

CREATE OR REPLACE FUNCTION public.moderation_delete_comment(p_id uuid)
RETURNS void LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $$
BEGIN
  IF auth.uid() IS NULL OR NOT public.is_super_admin() THEN
    RAISE EXCEPTION 'Réservé au super-admin' USING ERRCODE = '42501';
  END IF;
  DELETE FROM public.recipe_comments WHERE id = p_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Commentaire introuvable' USING ERRCODE = 'P0002';
  END IF;
END $$;

CREATE OR REPLACE FUNCTION public.moderation_accounts()
RETURNS TABLE (user_id uuid, pseudo text, display_name text, role text, family_name text,
               created_at timestamptz, disabled boolean, is_super boolean)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
BEGIN
  IF auth.uid() IS NULL OR NOT public.is_super_admin() THEN
    RAISE EXCEPTION 'Réservé au super-admin' USING ERRCODE = '42501';
  END IF;
  RETURN QUERY
    SELECT p.id, p.pseudo, p.display_name, p.role, f.name, p.created_at,
           EXISTS (SELECT 1 FROM private.disabled_accounts d WHERE d.user_id = p.id),
           EXISTS (SELECT 1 FROM public.super_admins s WHERE s.user_id = p.id)
      FROM public.profiles p
      LEFT JOIN public.families f ON f.id = p.family_id
     ORDER BY p.created_at DESC
     LIMIT 500;
END $$;

REVOKE ALL ON FUNCTION public.moderation_comments(integer)       FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.moderation_delete_comment(uuid)    FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.moderation_accounts()              FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.moderation_comments(integer)    TO authenticated;
GRANT EXECUTE ON FUNCTION public.moderation_delete_comment(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.moderation_accounts()           TO authenticated;
