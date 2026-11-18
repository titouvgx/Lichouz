-- ============================================================
-- Migration : photos des recettes du catalogue — lot-02
-- ============================================================
-- FICHIER GÉNÉRÉ par scripts/recettes/lots.ts — NE PAS MODIFIER À LA MAIN (npm run recettes).
-- Photos Unsplash (licence Unsplash : usage libre ; pas de photo « Unsplash+ »).
-- Ne touche que les recettes du catalogue qui n'ont pas encore de photo. Idempotente.
-- ============================================================

DO $$
DECLARE
  v_n integer;
BEGIN
  WITH p(title, url) AS (VALUES
    ('Moscow Mule', 'https://images.unsplash.com/photo-1527628126150-086ff233b951?w=800&h=600&fit=crop&auto=format'),
    ('Sex on the Beach', 'https://images.unsplash.com/photo-1625321643320-5321f48312b2?w=800&h=600&fit=crop&auto=format'),
    ('Paella', 'https://images.unsplash.com/photo-1623961990059-28356e226a77?w=800&h=600&fit=crop&auto=format'),
    ('Salade lyonnaise', 'https://images.unsplash.com/photo-1742054292299-7b8850c8f899?w=800&h=600&fit=crop&auto=format'),
    ('Crumble pommes-poires', 'https://images.unsplash.com/photo-1605698802040-b783f33b49a5?w=800&h=600&fit=crop&auto=format'),
    ('Butter chicken', 'https://images.unsplash.com/photo-1603894584373-5ac82b2ae398?w=800&h=600&fit=crop&auto=format'),
    ('Bibimbap', 'https://images.unsplash.com/photo-1590301157890-4810ed352733?w=800&h=600&fit=crop&auto=format')
  ), upd AS (
    UPDATE public.recipes r SET image_url = p.url
      FROM p
     WHERE r.title = p.title AND r.visibility = 'catalogue' AND r.image_url IS NULL
    RETURNING 1
  )
  SELECT count(*) INTO v_n FROM upd;
  RAISE NOTICE 'photos (lot-02) : % recette(s) mise(s) à jour', v_n;
END $$;
