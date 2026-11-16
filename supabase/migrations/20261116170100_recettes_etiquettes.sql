-- ============================================================
-- Migration : étiquettes des recettes du catalogue commun
-- ============================================================
-- FICHIER GÉNÉRÉ par scripts/recettes/generer.ts à partir de
-- supabase/recettes/etiquettes.json — NE PAS MODIFIER À LA MAIN (npm run recettes).
--
-- 50 recettes. Ne touche QUE les recettes du catalogue
-- (visibility = 'catalogue') et seulement les champs encore vides : une étiquette
-- posée dans l'appli (par le super-admin) n'est jamais écrasée.
-- Nécessite la migration 25 (colonnes diets, origin, themes, budget). Idempotente.
-- ============================================================

DO $$
DECLARE
  v_n integer;
BEGIN
  WITH e(title, diets, origin, themes, budget) AS (
    VALUES
    ('Bœuf bourguignon', '{}'::text[], 'bourgogne', ARRAY['reconfort', 'hiver', 'fetes']::text[], 3::smallint),
    ('Poulet rôti', ARRAY['sans_gluten', 'sans_porc']::text[], 'france', ARRAY['reconfort', 'fetes']::text[], 2::smallint),
    ('Quiche lorraine', '{}'::text[], 'lorraine', ARRAY['enfants', 'pique_nique']::text[], 1::smallint),
    ('Pâte à crêpes', ARRAY['vegetarien', 'sans_porc']::text[], 'bretagne', ARRAY['enfants', 'etudiant', 'fetes']::text[], 1::smallint),
    ('Gratin dauphinois', ARRAY['vegetarien', 'sans_gluten', 'sans_porc']::text[], 'dauphine', ARRAY['reconfort', 'hiver']::text[], 1::smallint),
    ('Hachis parmentier', ARRAY['sans_gluten', 'sans_porc']::text[], 'france', ARRAY['reconfort', 'enfants', 'hiver']::text[], 1::smallint),
    ('Tartiflette', ARRAY['sans_gluten']::text[], 'savoie', ARRAY['reconfort', 'hiver']::text[], 2::smallint),
    ('Mousse au chocolat', ARRAY['vegetarien', 'sans_gluten', 'sans_porc']::text[], 'france', ARRAY['enfants', 'fetes']::text[], 1::smallint),
    ('Pâtes à la carbonara', '{}'::text[], 'italie', ARRAY['etudiant']::text[], 2::smallint),
    ('Soupe à l''oignon gratinée', ARRAY['sans_porc']::text[], 'france', ARRAY['hiver', 'reconfort']::text[], 1::smallint),
    ('Ratatouille', ARRAY['vegetarien', 'vegan', 'sans_gluten', 'sans_lactose', 'sans_porc']::text[], 'provence', ARRAY['films', 'ete', 'leger']::text[], 1::smallint),
    ('Tarte aux pommes', ARRAY['vegetarien', 'sans_porc']::text[], 'france', ARRAY['enfants', 'fetes']::text[], 1::smallint),
    ('Fondant au chocolat', ARRAY['vegetarien', 'sans_porc']::text[], 'france', ARRAY['enfants', 'fetes']::text[], 1::smallint),
    ('Saumon en papillote', ARRAY['sans_gluten', 'sans_lactose', 'sans_porc']::text[], 'france', ARRAY['leger']::text[], 2::smallint),
    ('Velouté de potiron', ARRAY['sans_porc']::text[], 'france', ARRAY['hiver', 'leger']::text[], 1::smallint),
    ('Lasagnes bolognaise', ARRAY['sans_porc']::text[], 'italie', ARRAY['enfants', 'reconfort', 'fetes']::text[], 2::smallint),
    ('Salade niçoise', ARRAY['sans_gluten', 'sans_lactose', 'sans_porc']::text[], 'provence', ARRAY['ete', 'leger', 'pique_nique']::text[], 2::smallint),
    ('Croque-monsieur', '{}'::text[], 'france', ARRAY['enfants', 'etudiant']::text[], 1::smallint),
    ('Blanquette de veau', ARRAY['sans_porc']::text[], 'france', ARRAY['reconfort', 'hiver', 'fetes']::text[], 3::smallint),
    ('Omelette aux champignons', ARRAY['vegetarien', 'sans_gluten', 'sans_porc']::text[], 'france', ARRAY['etudiant', 'leger']::text[], 1::smallint),
    ('Pot-au-feu', ARRAY['sans_gluten', 'sans_lactose', 'sans_porc']::text[], 'france', ARRAY['hiver', 'reconfort']::text[], 2::smallint),
    ('Poulet basquaise', ARRAY['sans_gluten', 'sans_lactose']::text[], 'pays_basque', ARRAY['ete']::text[], 2::smallint),
    ('Chili con carne', ARRAY['sans_lactose', 'sans_porc']::text[], 'mexique', ARRAY['etudiant', 'hiver']::text[], 1::smallint),
    ('Curry de poulet au lait de coco', ARRAY['sans_gluten', 'sans_lactose', 'sans_porc']::text[], 'inde', '{}'::text[], 2::smallint),
    ('Gratin de pâtes au jambon', '{}'::text[], 'france', ARRAY['enfants', 'etudiant', 'reconfort']::text[], 1::smallint),
    ('Endives au jambon', '{}'::text[], 'nord', ARRAY['hiver', 'reconfort']::text[], 1::smallint),
    ('Boulettes de bœuf à la sauce tomate', ARRAY['sans_porc']::text[], 'italie', ARRAY['enfants']::text[], 1::smallint),
    ('Couscous au poulet et merguez', ARRAY['sans_porc']::text[], 'maghreb', ARRAY['fetes']::text[], 2::smallint),
    ('Risotto aux champignons', ARRAY['sans_porc']::text[], 'italie', ARRAY['reconfort']::text[], 2::smallint),
    ('Petit salé aux lentilles', ARRAY['sans_gluten', 'sans_lactose']::text[], 'auvergne', ARRAY['hiver']::text[], 2::smallint),
    ('Rôti de porc aux pommes de terre', '{}'::text[], 'france', ARRAY['fetes']::text[], 2::smallint),
    ('Galettes de sarrasin complètes', ARRAY['sans_gluten']::text[], 'bretagne', ARRAY['enfants']::text[], 1::smallint),
    ('Pizza maison', '{}'::text[], 'italie', ARRAY['enfants', 'fetes']::text[], 1::smallint),
    ('Moules marinières', ARRAY['sans_gluten', 'sans_porc']::text[], 'nord', ARRAY['ete']::text[], 1::smallint),
    ('Dahl de lentilles corail', ARRAY['vegetarien', 'vegan', 'sans_lactose', 'sans_porc']::text[], 'inde', ARRAY['etudiant', 'leger']::text[], 1::smallint),
    ('Cabillaud au four et sauce vierge', ARRAY['sans_gluten', 'sans_lactose', 'sans_porc']::text[], 'provence', ARRAY['leger', 'ete']::text[], 3::smallint),
    ('Wok de nouilles au poulet et aux légumes', ARRAY['sans_lactose', 'sans_porc']::text[], 'chine', '{}'::text[], 2::smallint),
    ('Tomates farcies', '{}'::text[], 'provence', ARRAY['ete', 'enfants']::text[], 1::smallint),
    ('Soupe poireaux-pommes de terre', ARRAY['vegetarien', 'sans_porc']::text[], 'france', ARRAY['hiver', 'leger']::text[], 1::smallint),
    ('Taboulé', ARRAY['vegetarien', 'vegan', 'sans_lactose', 'sans_porc']::text[], 'moyen_orient', ARRAY['ete', 'pique_nique', 'leger']::text[], 1::smallint),
    ('Œufs mimosa', ARRAY['vegetarien', 'sans_gluten', 'sans_lactose', 'sans_porc']::text[], 'france', ARRAY['pique_nique', 'fetes']::text[], 1::smallint),
    ('Salade de pâtes', ARRAY['sans_lactose', 'sans_porc']::text[], NULL::text, ARRAY['ete', 'pique_nique', 'etudiant']::text[], 1::smallint),
    ('Purée de pommes de terre', ARRAY['vegetarien', 'sans_gluten', 'sans_porc']::text[], 'france', ARRAY['enfants', 'reconfort']::text[], 1::smallint),
    ('Riz pilaf', ARRAY['sans_porc']::text[], NULL::text, '{}'::text[], 1::smallint),
    ('Légumes rôtis au four', ARRAY['vegetarien', 'vegan', 'sans_gluten', 'sans_lactose', 'sans_porc']::text[], NULL::text, ARRAY['leger', 'barbecue']::text[], 1::smallint),
    ('Gâteau au yaourt', ARRAY['vegetarien', 'sans_porc']::text[], 'france', ARRAY['enfants']::text[], 1::smallint),
    ('Clafoutis aux cerises', ARRAY['vegetarien', 'sans_porc']::text[], 'limousin', ARRAY['ete']::text[], 1::smallint),
    ('Riz au lait', ARRAY['vegetarien', 'sans_gluten', 'sans_porc']::text[], 'france', ARRAY['enfants', 'reconfort']::text[], 1::smallint),
    ('Crumble aux pommes', ARRAY['vegetarien', 'sans_porc']::text[], 'royaume_uni', ARRAY['hiver', 'reconfort']::text[], 1::smallint),
    ('Cookies aux pépites de chocolat', ARRAY['vegetarien', 'sans_porc']::text[], 'etats_unis', ARRAY['enfants', 'pique_nique']::text[], 1::smallint)
  ), upd AS (
    UPDATE public.recipes r
       SET diets  = CASE WHEN cardinality(r.diets) = 0 THEN e.diets ELSE r.diets END,
           origin = coalesce(r.origin, e.origin),
           themes = CASE WHEN cardinality(r.themes) = 0 THEN e.themes ELSE r.themes END,
           budget = coalesce(r.budget, e.budget)
      FROM e
     WHERE r.title = e.title
       AND r.visibility = 'catalogue'
       AND ((cardinality(r.diets) = 0 AND cardinality(e.diets) > 0)
         OR (r.origin IS NULL AND e.origin IS NOT NULL)
         OR (cardinality(r.themes) = 0 AND cardinality(e.themes) > 0)
         OR (r.budget IS NULL AND e.budget IS NOT NULL))
    RETURNING 1
  )
  SELECT count(*) INTO v_n FROM upd;
  RAISE NOTICE 'recettes_etiquettes : % recette(s) étiquetée(s)', v_n;
END $$;
