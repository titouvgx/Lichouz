-- ═══════════════════════════════════════════════════════════════
-- Migration 24 — Invitation liée à une adresse e-mail + petites incohérences (v1.7.0)
-- ═══════════════════════════════════════════════════════════════
-- 1. Invitation liée à une adresse e-mail (FACULTATIF, décision du 16/11/2026)
--    - create_invitation(…, p_email) : si l'admin donne une adresse, seule cette
--      adresse pourra créer le compte avec le lien. Sans adresse : comme avant.
--    - On ne garde PAS l'adresse : seulement son empreinte (sha256 de l'adresse
--      en minuscules) et un indice affichable « m•••@gmail.com ».
--    - consume_invitation compare l'adresse du compte qui vient d'être créé
--      (auth.users) à l'empreinte. Différente → refus, et tout est annulé : le
--      lien reste utilisable par la bonne personne, la fonction serveur supprime
--      le compte créé (comportement existant). Pas besoin de la redéployer.
--    - invitation_info renvoie aussi l'indice (la page « Rejoindre » le montre).
--    - Liens déjà envoyés (sans adresse) : valables jusqu'à leur expiration.
-- 2. « Coché par » : en MODIFICATION, on ne peut se mettre que soi-même
--    (avant : n'importe quel membre du foyer). À l'INSERTION (recalcul de la
--    liste), l'auteur d'origine reste conservé, toujours limité au foyer.
-- 3. Photos « orphelines » (dossier d'une recette qui n'existe plus) : visibles
--    et supprimables seulement par la personne qui les a envoyées ou le
--    super-admin (avant : par n'importe quel membre de n'importe quelle famille).
-- Contrôle : supabase/tests/controle_24_invitation_email.sql

-- ── 1. Invitations liées à une adresse ───────────────────────
ALTER TABLE public.invitations ADD COLUMN IF NOT EXISTS email_hash text;
ALTER TABLE public.invitations ADD COLUMN IF NOT EXISTS email_hint text;
ALTER TABLE public.invitations DROP CONSTRAINT IF EXISTS invitations_email_shape;
ALTER TABLE public.invitations ADD CONSTRAINT invitations_email_shape CHECK (
  (email_hash IS NULL AND email_hint IS NULL)
  OR (email_hash ~ '^[0-9a-f]{64}$' AND char_length(email_hint) BETWEEN 3 AND 80)
);
COMMENT ON COLUMN public.invitations.email_hash IS
  'sha256 de l''adresse e-mail (minuscules) à qui le lien est réservé ; NULL = lien ouvert. L''adresse n''est pas gardée.';

-- Empreinte et indice d'une adresse (calcul pur, réservé aux fonctions ci-dessous)
CREATE OR REPLACE FUNCTION public.invitation_email_hash(p_email text)
RETURNS text LANGUAGE sql IMMUTABLE SET search_path = '' AS $$
  SELECT encode(sha256(convert_to(lower(btrim(p_email)), 'UTF8')), 'hex')
$$;
REVOKE ALL ON FUNCTION public.invitation_email_hash(text) FROM PUBLIC, anon, authenticated;

-- Ancienne signature (4 arguments) remplacée : sans ce DROP, deux versions
-- coexisteraient et l'API ne saurait pas laquelle appeler. L'ancien site
-- (4 arguments nommés) appelle la nouvelle grâce à la valeur par défaut.
DROP FUNCTION IF EXISTS public.create_invitation(text, uuid, text, text);
CREATE OR REPLACE FUNCTION public.create_invitation(
  p_kind text, p_family_id uuid DEFAULT NULL, p_role text DEFAULT NULL, p_label text DEFAULT NULL,
  p_email text DEFAULT NULL
)
RETURNS TABLE (id uuid, token text, expires_at timestamptz)
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_token   text;
  v_id      uuid;
  v_expires timestamptz := now() + interval '7 days';
  v_email   text := lower(btrim(coalesce(p_email, '')));
  v_hash    text;
  v_hint    text;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Connexion requise' USING ERRCODE = '42501';
  END IF;
  IF p_kind = 'fondateur' THEN
    IF NOT public.is_super_admin() THEN
      RAISE EXCEPTION 'Réservé au super-admin' USING ERRCODE = '42501';
    END IF;
    p_family_id := NULL; p_role := NULL;
  ELSIF p_kind = 'membre' THEN
    IF p_family_id IS NULL OR p_role IS NULL OR p_role NOT IN ('admin', 'member') THEN
      RAISE EXCEPTION 'Famille et rôle requis' USING ERRCODE = '22023';
    END IF;
    IF NOT public.can_invite(p_family_id) THEN
      RAISE EXCEPTION 'Tu ne peux pas inviter dans cette famille' USING ERRCODE = '42501';
    END IF;
  ELSE
    RAISE EXCEPTION 'Type d''invitation inconnu' USING ERRCODE = '22023';
  END IF;
  IF v_email <> '' THEN
    IF char_length(v_email) > 254 OR v_email !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' THEN
      RAISE EXCEPTION 'Adresse e-mail invalide' USING ERRCODE = '22023';
    END IF;
    v_hash := public.invitation_email_hash(v_email);
    v_hint := left(left(v_email, 1) || '•••@' || split_part(v_email, '@', 2), 80);
  END IF;
  -- Anti-abus : 20 liens en attente au maximum par personne (verrou : deux
  -- demandes simultanées ne dépassent pas la limite)
  PERFORM pg_advisory_xact_lock(hashtext('create_invitation:' || auth.uid()::text));
  IF (SELECT count(*) FROM public.invitations i
      WHERE i.created_by = auth.uid() AND i.used_at IS NULL AND i.revoked_at IS NULL
        AND i.expires_at > now()) >= 20 THEN
    RAISE EXCEPTION 'Trop de liens en attente : annule ceux qui ne servent plus' USING ERRCODE = 'check_violation';
  END IF;
  -- 2 × 122 bits aléatoires (gen_random_uuid, générateur cryptographique)
  v_token := replace(gen_random_uuid()::text, '-', '') || replace(gen_random_uuid()::text, '-', '');
  INSERT INTO public.invitations (token_hash, kind, family_id, role, label, created_by, expires_at, email_hash, email_hint)
  VALUES (encode(sha256(convert_to(v_token, 'UTF8')), 'hex'), p_kind, p_family_id, p_role,
          NULLIF(btrim(left(p_label, 60)), ''), auth.uid(), v_expires, v_hash, v_hint)
  RETURNING invitations.id INTO v_id;
  RETURN QUERY SELECT v_id, v_token, v_expires;
END;
$$;
REVOKE ALL ON FUNCTION public.create_invitation(text, uuid, text, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_invitation(text, uuid, text, text, text) TO authenticated;

-- invitation_info : même contenu + l'indice d'adresse (type de retour changé → DROP)
DROP FUNCTION IF EXISTS public.invitation_info(text);
CREATE FUNCTION public.invitation_info(p_token text)
RETURNS TABLE (status text, kind text, role text, family_name text, email_hint text)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT
    CASE
      WHEN i.id IS NULL THEN 'inconnue'
      WHEN i.revoked_at IS NOT NULL THEN 'annulee'
      WHEN i.used_at IS NOT NULL THEN 'utilisee'
      WHEN i.expires_at <= now() THEN 'expiree'
      ELSE 'valide'
    END,
    i.kind, i.role, f.name, i.email_hint
  FROM (SELECT 1) AS one
  LEFT JOIN public.invitations i
    ON i.token_hash = encode(sha256(convert_to(coalesce(p_token, ''), 'UTF8')), 'hex')
  LEFT JOIN public.families f ON f.id = i.family_id
$$;
REVOKE ALL ON FUNCTION public.invitation_info(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.invitation_info(text) TO anon, authenticated;

-- consume_invitation : reprise de la migration 17 + vérification de l'adresse
CREATE OR REPLACE FUNCTION public.consume_invitation(
  p_token text, p_user_id uuid, p_display_name text, p_family_name text DEFAULT NULL
)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v      public.invitations;
  v_name text := btrim(coalesce(p_display_name, ''));
  v_fam  text := btrim(coalesce(p_family_name, ''));
  v_sf   uuid;
  v_fid  uuid;
BEGIN
  IF char_length(v_name) NOT BETWEEN 1 AND 40 THEN
    RAISE EXCEPTION 'Prénom ou nom invalide' USING ERRCODE = '22023';
  END IF;
  IF EXISTS (SELECT 1 FROM public.profiles WHERE id = p_user_id) THEN
    RAISE EXCEPTION 'Ce compte a déjà une famille' USING ERRCODE = '22023';
  END IF;
  UPDATE public.invitations
     SET used_at = now(), used_by = p_user_id
   WHERE token_hash = encode(sha256(convert_to(coalesce(p_token, ''), 'UTF8')), 'hex')
     AND used_at IS NULL AND revoked_at IS NULL AND expires_at > now()
  RETURNING * INTO v;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Lien d''invitation invalide, expiré ou déjà utilisé' USING ERRCODE = '22023';
  END IF;
  -- Lien réservé à une adresse : l'erreur annule tout (le lien reste valable)
  IF v.email_hash IS NOT NULL AND v.email_hash IS DISTINCT FROM (
    SELECT public.invitation_email_hash(u.email) FROM auth.users u WHERE u.id = p_user_id
  ) THEN
    RAISE EXCEPTION 'Ce lien est réservé à une autre adresse e-mail (%). Utilise celle-là, ou demande un nouveau lien.',
      v.email_hint USING ERRCODE = '22023';
  END IF;

  IF v.kind = 'fondateur' THEN
    IF char_length(v_fam) NOT BETWEEN 1 AND 60 THEN
      RAISE EXCEPTION 'Nom de famille invalide' USING ERRCODE = '22023';
    END IF;
    INSERT INTO public.super_families (name, founder_id) VALUES (v_fam, p_user_id) RETURNING id INTO v_sf;
    INSERT INTO public.families (name, super_family_id) VALUES (v_fam, v_sf) RETURNING id INTO v_fid;
    INSERT INTO public.profiles (id, family_id, display_name, role) VALUES (p_user_id, v_fid, v_name, 'admin');
  ELSE
    v_fid := v.family_id;
    INSERT INTO public.profiles (id, family_id, display_name, role) VALUES (p_user_id, v_fid, v_name, v.role);
  END IF;
  RETURN jsonb_build_object('kind', v.kind, 'family_id', v_fid);
END;
$$;
REVOKE ALL ON FUNCTION public.consume_invitation(text, uuid, text, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.consume_invitation(text, uuid, text, text) TO service_role;

-- ── 2. « Coché par » : soi-même en modification ──────────────
-- Reprise de la migration 22 + règle de modification.
CREATE OR REPLACE FUNCTION public.guard_item_checked_by()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
BEGIN
  IF NEW.source_recipe_id IS NOT NULL AND auth.uid() IS NOT NULL AND NOT public.is_super_admin()
     AND (TG_OP = 'INSERT' OR NEW.source_recipe_id IS DISTINCT FROM OLD.source_recipe_id)
     AND NOT public.can_read_recipe(NEW.source_recipe_id) THEN
    RAISE EXCEPTION 'Recette d''origine inaccessible' USING ERRCODE = '42501';
  END IF;
  IF cardinality(NEW.source_recipe_ids) > 0 AND auth.uid() IS NOT NULL AND NOT public.is_super_admin()
     AND (TG_OP = 'INSERT' OR NEW.source_recipe_ids IS DISTINCT FROM OLD.source_recipe_ids)
     AND EXISTS (SELECT 1 FROM unnest(NEW.source_recipe_ids) AS r(id) WHERE NOT public.can_read_recipe(r.id)) THEN
    RAISE EXCEPTION 'Recette d''origine inaccessible' USING ERRCODE = '42501';
  END IF;
  -- En modification, on ne coche qu'en son propre nom
  IF TG_OP = 'UPDATE' AND NEW.checked_by IS NOT NULL AND NEW.checked_by IS DISTINCT FROM OLD.checked_by
     AND auth.uid() IS NOT NULL AND NOT public.is_super_admin()
     AND NEW.checked_by <> auth.uid() THEN
    RAISE EXCEPTION '« Coché par » : seulement toi-même' USING ERRCODE = '42501';
  END IF;
  IF NEW.checked_by IS NOT NULL AND auth.uid() IS NOT NULL AND NOT public.is_super_admin()
     AND (TG_OP = 'INSERT' OR NEW.checked_by IS DISTINCT FROM OLD.checked_by)
     AND NOT EXISTS (
       SELECT 1 FROM public.profiles p JOIN public.shopping_lists sl ON sl.family_id = p.family_id
       WHERE p.id = NEW.checked_by AND sl.id = NEW.shopping_list_id
     ) THEN
    RAISE EXCEPTION '« Coché par » doit être un membre du foyer' USING ERRCODE = '42501';
  END IF;
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION public.guard_item_checked_by() FROM PUBLIC, anon, authenticated;

-- ── 3. Photos orphelines : seulement leur auteur ou le super-admin ─
DROP POLICY IF EXISTS "recipe_photos_select" ON storage.objects;
CREATE POLICY "recipe_photos_select" ON storage.objects FOR SELECT TO authenticated
  USING (
    bucket_id = 'recipe-photos' AND public.is_member()
    AND (
      (NOT public.recipe_exists((storage.foldername(name))[1])
        AND (owner = auth.uid() OR public.is_super_admin()))
      OR EXISTS (SELECT 1 FROM public.recipes r
                 WHERE r.id::text = (storage.foldername(name))[1] AND public.can_read_recipe(r.id))
    )
  );
DROP POLICY IF EXISTS "recipe_photos_delete" ON storage.objects;
CREATE POLICY "recipe_photos_delete" ON storage.objects FOR DELETE TO authenticated
  USING (
    bucket_id = 'recipe-photos'
    AND public.is_member()
    AND (
      EXISTS (SELECT 1 FROM public.recipes r
              WHERE r.id::text = (storage.foldername(name))[1] AND public.can_edit_recipe(r.id))
      OR (NOT public.recipe_exists((storage.foldername(name))[1])
          AND (owner = auth.uid() OR public.is_super_admin()))
    )
  );
