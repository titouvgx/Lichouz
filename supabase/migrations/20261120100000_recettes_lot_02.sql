-- ============================================================
-- Migration : recettes du catalogue — lot-02
-- ============================================================
-- FICHIER GÉNÉRÉ par scripts/recettes/lots.ts à partir de
-- supabase/recettes/lots/lot-02.json — NE PAS MODIFIER À LA MAIN (npm run recettes).
--
-- 10 recettes ajoutées au catalogue commun (visibility = 'catalogue',
-- étiquettes comprises), seulement si aucune recette ne porte déjà le même titre.
-- Rattachées au foyer et au compte des recettes de démo (sinon : premier foyer, premier compte).
-- Recettes rédigées pour l'appli (pas de texte copié) ; quantités vérifiées sur des
-- références publiques (liste dans le JSON). Photos : migration séparée.
-- Nécessite les migrations 17 (visibility) et 25 (étiquettes). Idempotente.
-- ============================================================

DO $$
DECLARE
  v_family uuid;
  v_user   uuid;
  v_rid    uuid;
  v_added  integer := 0;
BEGIN
  SELECT family_id, created_by INTO v_family, v_user
    FROM public.recipes WHERE title = 'Bœuf bourguignon' ORDER BY created_at LIMIT 1;
  IF v_family IS NULL THEN
    SELECT id INTO v_family FROM public.families ORDER BY created_at LIMIT 1;
  END IF;
  IF v_user IS NULL THEN
    SELECT id INTO v_user FROM auth.users ORDER BY created_at LIMIT 1;
  END IF;
  IF v_family IS NULL THEN
    RAISE EXCEPTION 'recettes (lot-02) : il faut au moins 1 foyer avant cette migration';
  END IF;

  -- ── Nouvelle : Moscow Mule ──
  IF NOT EXISTS (SELECT 1 FROM public.recipes WHERE lower(title) = lower('Moscow Mule')) THEN
    INSERT INTO public.recipes (family_id, title, category_id, prep_time_min, default_portions, created_by,
                                visibility, diets, origin, themes, budget)
    VALUES (v_family, 'Moscow Mule', (SELECT id FROM public.recipe_categories WHERE name = 'Boisson & cocktail'),
            5, 1, v_user,
            'catalogue', ARRAY['vegetarien', 'vegan', 'sans_lactose', 'sans_porc']::text[], 'etats_unis',
            ARRAY['ete', 'fetes']::text[], 1)
    RETURNING id INTO v_rid;
  INSERT INTO public.recipe_ingredients (recipe_id, name, quantity, unit, shopping_category_id, position) VALUES
    (v_rid, 'Vodka', 4, 'cl', (SELECT id FROM public.shopping_categories WHERE name = 'Boissons'), 0),
    (v_rid, 'Ginger beer', 12, 'cl', (SELECT id FROM public.shopping_categories WHERE name = 'Boissons'), 1),
    (v_rid, 'Citron vert', 0.5, 'pièce', (SELECT id FROM public.shopping_categories WHERE name = 'Fruits & légumes'), 2),
    (v_rid, 'Menthe fraîche', 1, 'branche', (SELECT id FROM public.shopping_categories WHERE name = 'Fruits & légumes'), 3),
    (v_rid, 'Glaçons', NULL, NULL, (SELECT id FROM public.shopping_categories WHERE name = 'Surgelés'), 4);
  INSERT INTO public.recipe_steps (recipe_id, position, instruction) VALUES
    (v_rid, 0, 'Remplir un grand verre (ou une timbale en cuivre) de glaçons jusqu''au bord. Plus le verre est froid, plus le cocktail reste pétillant.'),
    (v_rid, 1, 'Couper une rondelle dans le demi-citron vert pour la décoration, puis presser le reste (environ 1,5 cl de jus) dans le verre. Verser la vodka par-dessus.'),
    (v_rid, 2, 'Compléter avec la ginger beer bien froide et remuer une seule fois, doucement, pour garder les bulles. La ginger beer est plus épicée qu''un ginger ale : c''est elle qui donne son caractère au cocktail.'),
    (v_rid, 3, 'Décorer avec la rondelle de citron vert et la branche de menthe, froissée entre les doigts pour libérer son parfum. Servir aussitôt.');
    v_added := v_added + 1;
  END IF;

  -- ── Nouvelle : White Russian ──
  IF NOT EXISTS (SELECT 1 FROM public.recipes WHERE lower(title) = lower('White Russian')) THEN
    INSERT INTO public.recipes (family_id, title, category_id, prep_time_min, default_portions, created_by,
                                visibility, diets, origin, themes, budget)
    VALUES (v_family, 'White Russian', (SELECT id FROM public.recipe_categories WHERE name = 'Boisson & cocktail'),
            5, 1, v_user,
            'catalogue', ARRAY['vegetarien', 'sans_porc']::text[], 'etats_unis',
            ARRAY['films', 'hiver', 'fetes']::text[], 2)
    RETURNING id INTO v_rid;
  INSERT INTO public.recipe_ingredients (recipe_id, name, quantity, unit, shopping_category_id, position) VALUES
    (v_rid, 'Vodka', 4, 'cl', (SELECT id FROM public.shopping_categories WHERE name = 'Boissons'), 0),
    (v_rid, 'Liqueur de café', 2, 'cl', (SELECT id FROM public.shopping_categories WHERE name = 'Boissons'), 1),
    (v_rid, 'Crème liquide', 2, 'cl', (SELECT id FROM public.shopping_categories WHERE name = 'Produits laitiers & œufs'), 2),
    (v_rid, 'Glaçons', NULL, NULL, (SELECT id FROM public.shopping_categories WHERE name = 'Surgelés'), 3);
  INSERT INTO public.recipe_steps (recipe_id, position, instruction) VALUES
    (v_rid, 0, 'Remplir à moitié un verre court (type verre à whisky) de glaçons.'),
    (v_rid, 1, 'Verser la vodka puis la liqueur de café sur la glace et remuer quelques secondes avec une cuillère.'),
    (v_rid, 2, 'Verser la crème liquide très doucement en la faisant couler sur le dos d''une cuillère : elle reste en surface et dessine une belle couche blanche.'),
    (v_rid, 3, 'Servir tel quel et remuer au moment de boire, pour mélanger la crème au café. À savourer en fin de repas, comme un dessert.');
    v_added := v_added + 1;
  END IF;

  -- ── Nouvelle : Sex on the Beach ──
  IF NOT EXISTS (SELECT 1 FROM public.recipes WHERE lower(title) = lower('Sex on the Beach')) THEN
    INSERT INTO public.recipes (family_id, title, category_id, prep_time_min, default_portions, created_by,
                                visibility, diets, origin, themes, budget)
    VALUES (v_family, 'Sex on the Beach', (SELECT id FROM public.recipe_categories WHERE name = 'Boisson & cocktail'),
            5, 1, v_user,
            'catalogue', ARRAY['vegetarien', 'vegan', 'sans_lactose', 'sans_porc']::text[], 'etats_unis',
            ARRAY['ete', 'fetes']::text[], 2)
    RETURNING id INTO v_rid;
  INSERT INTO public.recipe_ingredients (recipe_id, name, quantity, unit, shopping_category_id, position) VALUES
    (v_rid, 'Vodka', 4, 'cl', (SELECT id FROM public.shopping_categories WHERE name = 'Boissons'), 0),
    (v_rid, 'Liqueur de pêche', 2, 'cl', (SELECT id FROM public.shopping_categories WHERE name = 'Boissons'), 1),
    (v_rid, 'Jus d''orange', 4, 'cl', (SELECT id FROM public.shopping_categories WHERE name = 'Boissons'), 2),
    (v_rid, 'Jus de cranberry', 4, 'cl', (SELECT id FROM public.shopping_categories WHERE name = 'Boissons'), 3),
    (v_rid, 'Orange', 1, 'tranche', (SELECT id FROM public.shopping_categories WHERE name = 'Fruits & légumes'), 4),
    (v_rid, 'Glaçons', NULL, NULL, (SELECT id FROM public.shopping_categories WHERE name = 'Surgelés'), 5);
  INSERT INTO public.recipe_steps (recipe_id, position, instruction) VALUES
    (v_rid, 0, 'Remplir un grand verre de glaçons.'),
    (v_rid, 1, 'Verser la vodka, la liqueur de pêche et le jus d''orange, puis remuer doucement.'),
    (v_rid, 2, 'Verser le jus de cranberry en dernier, lentement : il descend et colore le fond du verre en rouge.'),
    (v_rid, 3, 'Décorer avec la tranche d''orange posée sur le bord du verre. Servir bien frais, avec une paille.');
    v_added := v_added + 1;
  END IF;

  -- ── Nouvelle : Fajitas au bœuf ──
  IF NOT EXISTS (SELECT 1 FROM public.recipes WHERE lower(title) = lower('Fajitas au bœuf')) THEN
    INSERT INTO public.recipes (family_id, title, category_id, prep_time_min, default_portions, created_by,
                                visibility, diets, origin, themes, budget)
    VALUES (v_family, 'Fajitas au bœuf', (SELECT id FROM public.recipe_categories WHERE name = 'Plat'),
            30, 4, v_user,
            'catalogue', ARRAY['sans_porc']::text[], 'mexique',
            ARRAY['enfants', 'fetes']::text[], 2)
    RETURNING id INTO v_rid;
  INSERT INTO public.recipe_ingredients (recipe_id, name, quantity, unit, shopping_category_id, position) VALUES
    (v_rid, 'Bavette ou rumsteck', 500, 'g', (SELECT id FROM public.shopping_categories WHERE name = 'Viandes & poissons'), 0),
    (v_rid, 'Poivron rouge', 1, 'pièce', (SELECT id FROM public.shopping_categories WHERE name = 'Fruits & légumes'), 1),
    (v_rid, 'Poivron vert', 1, 'pièce', (SELECT id FROM public.shopping_categories WHERE name = 'Fruits & légumes'), 2),
    (v_rid, 'Oignon', 2, 'pièce', (SELECT id FROM public.shopping_categories WHERE name = 'Fruits & légumes'), 3),
    (v_rid, 'Citron vert', 1, 'pièce', (SELECT id FROM public.shopping_categories WHERE name = 'Fruits & légumes'), 4),
    (v_rid, 'Ail', 2, 'gousse', (SELECT id FROM public.shopping_categories WHERE name = 'Fruits & légumes'), 5),
    (v_rid, 'Paprika', 2, 'c. à café', (SELECT id FROM public.shopping_categories WHERE name = 'Condiments & épices'), 6),
    (v_rid, 'Cumin moulu', 1, 'c. à café', (SELECT id FROM public.shopping_categories WHERE name = 'Condiments & épices'), 7),
    (v_rid, 'Piment en poudre', 1, 'c. à café', (SELECT id FROM public.shopping_categories WHERE name = 'Condiments & épices'), 8),
    (v_rid, 'Huile d''olive', 3, 'c. à soupe', (SELECT id FROM public.shopping_categories WHERE name = 'Condiments & épices'), 9),
    (v_rid, 'Tortillas de blé', 8, 'pièce', (SELECT id FROM public.shopping_categories WHERE name = 'Épicerie salée'), 10),
    (v_rid, 'Crème fraîche épaisse', 150, 'g', (SELECT id FROM public.shopping_categories WHERE name = 'Produits laitiers & œufs'), 11),
    (v_rid, 'Avocat', 1, 'pièce', (SELECT id FROM public.shopping_categories WHERE name = 'Fruits & légumes'), 12),
    (v_rid, 'Coriandre fraîche', 0.5, 'botte', (SELECT id FROM public.shopping_categories WHERE name = 'Fruits & légumes'), 13),
    (v_rid, 'Sel', NULL, NULL, (SELECT id FROM public.shopping_categories WHERE name = 'Condiments & épices'), 14),
    (v_rid, 'Poivre', NULL, NULL, (SELECT id FROM public.shopping_categories WHERE name = 'Condiments & épices'), 15);
  INSERT INTO public.recipe_steps (recipe_id, position, instruction) VALUES
    (v_rid, 0, 'Préparer la marinade : presser le citron vert, écraser l''ail, puis mélanger avec 2 c. à soupe d''huile, le paprika, le cumin, le piment, du sel et du poivre.'),
    (v_rid, 1, 'Couper la viande en bandes d''environ 1 cm d''épaisseur en travaillant en travers des fibres, la mélanger à la marinade et laisser reposer au frais de 30 min à 2 h.'),
    (v_rid, 2, 'Couper les poivrons et les oignons en lanières. Les faire revenir 8 à 10 min dans une grande poêle avec le reste d''huile, à feu vif, jusqu''à ce qu''ils soient dorés mais encore croquants. Les réserver.'),
    (v_rid, 3, 'Dans la même poêle bien chaude, saisir la viande 2 à 3 min en la remuant, jusqu''à ce qu''elle soit dorée. Remettre les légumes pour les réchauffer 1 min.'),
    (v_rid, 4, 'Réchauffer les tortillas quelques secondes à la poêle sèche ou au four, écraser l''avocat à la fourchette et ciseler la coriandre.'),
    (v_rid, 5, 'Servir la viande et les légumes dans les tortillas, avec la crème fraîche, l''avocat et la coriandre. Chacun garnit et roule sa fajita à table.');
    v_added := v_added + 1;
  END IF;

  -- ── Nouvelle : Rougail saucisses ──
  IF NOT EXISTS (SELECT 1 FROM public.recipes WHERE lower(title) = lower('Rougail saucisses')) THEN
    INSERT INTO public.recipes (family_id, title, category_id, prep_time_min, default_portions, created_by,
                                visibility, diets, origin, themes, budget)
    VALUES (v_family, 'Rougail saucisses', (SELECT id FROM public.recipe_categories WHERE name = 'Plat'),
            55, 4, v_user,
            'catalogue', '{}'::text[], 'antilles',
            ARRAY['reconfort']::text[], 1)
    RETURNING id INTO v_rid;
  INSERT INTO public.recipe_ingredients (recipe_id, name, quantity, unit, shopping_category_id, position) VALUES
    (v_rid, 'Saucisses fumées', 4, 'pièce', (SELECT id FROM public.shopping_categories WHERE name = 'Viandes & poissons'), 0),
    (v_rid, 'Tomate', 600, 'g', (SELECT id FROM public.shopping_categories WHERE name = 'Fruits & légumes'), 1),
    (v_rid, 'Oignon', 2, 'pièce', (SELECT id FROM public.shopping_categories WHERE name = 'Fruits & légumes'), 2),
    (v_rid, 'Ail', 4, 'gousse', (SELECT id FROM public.shopping_categories WHERE name = 'Fruits & légumes'), 3),
    (v_rid, 'Gingembre frais', 20, 'g', (SELECT id FROM public.shopping_categories WHERE name = 'Fruits & légumes'), 4),
    (v_rid, 'Piment frais', 1, 'pièce', (SELECT id FROM public.shopping_categories WHERE name = 'Fruits & légumes'), 5),
    (v_rid, 'Thym', 2, 'branche', (SELECT id FROM public.shopping_categories WHERE name = 'Condiments & épices'), 6),
    (v_rid, 'Huile', 2, 'c. à soupe', (SELECT id FROM public.shopping_categories WHERE name = 'Condiments & épices'), 7),
    (v_rid, 'Riz blanc', 300, 'g', (SELECT id FROM public.shopping_categories WHERE name = 'Épicerie salée'), 8),
    (v_rid, 'Sel', NULL, NULL, (SELECT id FROM public.shopping_categories WHERE name = 'Condiments & épices'), 9),
    (v_rid, 'Poivre', NULL, NULL, (SELECT id FROM public.shopping_categories WHERE name = 'Condiments & épices'), 10);
  INSERT INTO public.recipe_steps (recipe_id, position, instruction) VALUES
    (v_rid, 0, 'Plonger les saucisses 5 min dans de l''eau bouillante pour enlever l''excès de gras et de sel, puis les égoutter et les couper en tronçons de 3 à 4 cm.'),
    (v_rid, 1, 'Éplucher et émincer les oignons, écraser l''ail, râper le gingembre. Couper les tomates en petits dés (ou les écraser grossièrement). Épépiner et hacher le piment : il est très fort, en mettre moins si les enfants mangent.'),
    (v_rid, 2, 'Faire dorer les tronçons de saucisse 5 min dans l''huile, à feu moyen, puis les retirer et les garder de côté.'),
    (v_rid, 3, 'Dans la même cocotte, faire revenir les oignons 5 min, puis ajouter l''ail, le gingembre et le piment pour 1 min.'),
    (v_rid, 4, 'Ajouter les tomates, le thym, un peu de sel et de poivre (peu de sel : les saucisses sont déjà salées). Remettre les saucisses, couvrir et laisser mijoter 20 min à feu doux.'),
    (v_rid, 5, 'Découvrir et laisser réduire 10 min, jusqu''à ce que la sauce soit épaisse. Pendant ce temps, cuire le riz selon le paquet.'),
    (v_rid, 6, 'Servir le rougail sur le riz. À la Réunion, on l''accompagne souvent de lentilles ou de haricots rouges.');
    v_added := v_added + 1;
  END IF;

  -- ── Nouvelle : Paella ──
  IF NOT EXISTS (SELECT 1 FROM public.recipes WHERE lower(title) = lower('Paella')) THEN
    INSERT INTO public.recipes (family_id, title, category_id, prep_time_min, default_portions, created_by,
                                visibility, diets, origin, themes, budget)
    VALUES (v_family, 'Paella', (SELECT id FROM public.recipe_categories WHERE name = 'Plat'),
            70, 6, v_user,
            'catalogue', ARRAY['sans_lactose', 'sans_porc']::text[], 'espagne',
            ARRAY['fetes', 'ete']::text[], 3)
    RETURNING id INTO v_rid;
  INSERT INTO public.recipe_ingredients (recipe_id, name, quantity, unit, shopping_category_id, position) VALUES
    (v_rid, 'Riz rond spécial paella', 400, 'g', (SELECT id FROM public.shopping_categories WHERE name = 'Épicerie salée'), 0),
    (v_rid, 'Cuisses de poulet', 4, 'pièce', (SELECT id FROM public.shopping_categories WHERE name = 'Viandes & poissons'), 1),
    (v_rid, 'Crevettes crues', 300, 'g', (SELECT id FROM public.shopping_categories WHERE name = 'Viandes & poissons'), 2),
    (v_rid, 'Moules', 500, 'g', (SELECT id FROM public.shopping_categories WHERE name = 'Viandes & poissons'), 3),
    (v_rid, 'Calamars', 200, 'g', (SELECT id FROM public.shopping_categories WHERE name = 'Viandes & poissons'), 4),
    (v_rid, 'Poivron rouge', 1, 'pièce', (SELECT id FROM public.shopping_categories WHERE name = 'Fruits & légumes'), 5),
    (v_rid, 'Tomate', 2, 'pièce', (SELECT id FROM public.shopping_categories WHERE name = 'Fruits & légumes'), 6),
    (v_rid, 'Oignon', 1, 'pièce', (SELECT id FROM public.shopping_categories WHERE name = 'Fruits & légumes'), 7),
    (v_rid, 'Ail', 3, 'gousse', (SELECT id FROM public.shopping_categories WHERE name = 'Fruits & légumes'), 8),
    (v_rid, 'Petits pois surgelés', 150, 'g', (SELECT id FROM public.shopping_categories WHERE name = 'Surgelés'), 9),
    (v_rid, 'Bouillon de volaille', 1, 'l', (SELECT id FROM public.shopping_categories WHERE name = 'Épicerie salée'), 10),
    (v_rid, 'Safran', 1, 'pincée', (SELECT id FROM public.shopping_categories WHERE name = 'Condiments & épices'), 11),
    (v_rid, 'Paprika doux', 1, 'c. à café', (SELECT id FROM public.shopping_categories WHERE name = 'Condiments & épices'), 12),
    (v_rid, 'Huile d''olive', 4, 'c. à soupe', (SELECT id FROM public.shopping_categories WHERE name = 'Condiments & épices'), 13),
    (v_rid, 'Citron', 1, 'pièce', (SELECT id FROM public.shopping_categories WHERE name = 'Fruits & légumes'), 14),
    (v_rid, 'Sel', NULL, NULL, (SELECT id FROM public.shopping_categories WHERE name = 'Condiments & épices'), 15);
  INSERT INTO public.recipe_steps (recipe_id, position, instruction) VALUES
    (v_rid, 0, 'Chauffer le bouillon et y faire infuser le safran. Gratter et rincer les moules, jeter celles qui restent ouvertes quand on les tapote. Couper les calamars en anneaux. Couper le poivron en lanières, les tomates en dés, hacher l''oignon et l''ail.'),
    (v_rid, 1, 'Dans une très grande poêle ou un grand plat à paella, chauffer l''huile et faire dorer les cuisses de poulet 10 min en les retournant. Saler légèrement.'),
    (v_rid, 2, 'Ajouter l''oignon, le poivron, l''ail et les calamars, et cuire 5 min. Ajouter les tomates et le paprika, et laisser compoter 5 min.'),
    (v_rid, 3, 'Verser le riz et le remuer 2 min pour qu''il s''enrobe de gras et devienne translucide.'),
    (v_rid, 4, 'Verser le bouillon chaud au safran, mélanger une dernière fois pour répartir le riz, puis ne plus remuer. Cuire 10 min à feu assez vif, puis 10 min à feu doux.'),
    (v_rid, 5, 'Disposer les crevettes, les moules (charnière vers le bas) et les petits pois sur le riz. Cuire encore 5 à 8 min, jusqu''à ce que les moules s''ouvrent et que le riz ait absorbé le liquide. Jeter les moules restées fermées.'),
    (v_rid, 6, 'Retirer du feu, couvrir d''un torchon et laisser reposer 5 min. Servir directement dans le plat, avec des quartiers de citron.');
    v_added := v_added + 1;
  END IF;

  -- ── Nouvelle : Salade lyonnaise ──
  IF NOT EXISTS (SELECT 1 FROM public.recipes WHERE lower(title) = lower('Salade lyonnaise')) THEN
    INSERT INTO public.recipes (family_id, title, category_id, prep_time_min, default_portions, created_by,
                                visibility, diets, origin, themes, budget)
    VALUES (v_family, 'Salade lyonnaise', (SELECT id FROM public.recipe_categories WHERE name = 'Entrée'),
            30, 4, v_user,
            'catalogue', ARRAY['sans_lactose']::text[], 'lyonnais',
            ARRAY['reconfort']::text[], 1)
    RETURNING id INTO v_rid;
  INSERT INTO public.recipe_ingredients (recipe_id, name, quantity, unit, shopping_category_id, position) VALUES
    (v_rid, 'Frisée', 1, 'pièce', (SELECT id FROM public.shopping_categories WHERE name = 'Fruits & légumes'), 0),
    (v_rid, 'Lardons fumés', 200, 'g', (SELECT id FROM public.shopping_categories WHERE name = 'Viandes & poissons'), 1),
    (v_rid, 'Œufs', 4, 'pièce', (SELECT id FROM public.shopping_categories WHERE name = 'Produits laitiers & œufs'), 2),
    (v_rid, 'Pain rassis', 4, 'tranche', (SELECT id FROM public.shopping_categories WHERE name = 'Épicerie salée'), 3),
    (v_rid, 'Ail', 1, 'gousse', (SELECT id FROM public.shopping_categories WHERE name = 'Fruits & légumes'), 4),
    (v_rid, 'Échalote', 1, 'pièce', (SELECT id FROM public.shopping_categories WHERE name = 'Fruits & légumes'), 5),
    (v_rid, 'Moutarde de Dijon', 1, 'c. à soupe', (SELECT id FROM public.shopping_categories WHERE name = 'Condiments & épices'), 6),
    (v_rid, 'Vinaigre de vin', 2, 'c. à soupe', (SELECT id FROM public.shopping_categories WHERE name = 'Condiments & épices'), 7),
    (v_rid, 'Huile', 4, 'c. à soupe', (SELECT id FROM public.shopping_categories WHERE name = 'Condiments & épices'), 8),
    (v_rid, 'Vinaigre blanc', 1, 'c. à soupe', (SELECT id FROM public.shopping_categories WHERE name = 'Condiments & épices'), 9),
    (v_rid, 'Sel', NULL, NULL, (SELECT id FROM public.shopping_categories WHERE name = 'Condiments & épices'), 10),
    (v_rid, 'Poivre', NULL, NULL, (SELECT id FROM public.shopping_categories WHERE name = 'Condiments & épices'), 11);
  INSERT INTO public.recipe_steps (recipe_id, position, instruction) VALUES
    (v_rid, 0, 'Laver la frisée, garder surtout les parties claires et tendres, l''essorer et la mettre dans un grand saladier.'),
    (v_rid, 1, 'Frotter les tranches de pain avec l''ail, les couper en dés et les dorer 4 à 5 min dans une poêle avec 1 c. à soupe d''huile. Les réserver.'),
    (v_rid, 2, 'Faire revenir les lardons à sec 5 à 6 min, jusqu''à ce qu''ils soient dorés. Les égoutter en gardant 1 c. à soupe de leur gras dans la poêle.'),
    (v_rid, 3, 'Préparer la vinaigrette : mélanger la moutarde, le vinaigre de vin, l''échalote hachée très fin, le reste d''huile, du poivre et un peu de sel. Y ajouter le gras de cuisson tiède.'),
    (v_rid, 4, 'Faire frémir de l''eau avec le vinaigre blanc. Casser chaque œuf dans une tasse, puis le glisser dans l''eau. Pocher 3 min, jusqu''à ce que le blanc soit pris et le jaune coulant, puis égoutter sur du papier absorbant.'),
    (v_rid, 5, 'Mélanger la frisée avec la vinaigrette, répartir dans les assiettes, ajouter les lardons et les croûtons, et poser un œuf poché sur chaque assiette. Servir tout de suite.');
    v_added := v_added + 1;
  END IF;

  -- ── Nouvelle : Crumble pommes-poires ──
  IF NOT EXISTS (SELECT 1 FROM public.recipes WHERE lower(title) = lower('Crumble pommes-poires')) THEN
    INSERT INTO public.recipes (family_id, title, category_id, prep_time_min, default_portions, created_by,
                                visibility, diets, origin, themes, budget)
    VALUES (v_family, 'Crumble pommes-poires', (SELECT id FROM public.recipe_categories WHERE name = 'Dessert'),
            55, 6, v_user,
            'catalogue', ARRAY['vegetarien']::text[], 'royaume_uni',
            ARRAY['reconfort', 'hiver', 'enfants']::text[], 1)
    RETURNING id INTO v_rid;
  INSERT INTO public.recipe_ingredients (recipe_id, name, quantity, unit, shopping_category_id, position) VALUES
    (v_rid, 'Pomme', 3, 'pièce', (SELECT id FROM public.shopping_categories WHERE name = 'Fruits & légumes'), 0),
    (v_rid, 'Poire', 3, 'pièce', (SELECT id FROM public.shopping_categories WHERE name = 'Fruits & légumes'), 1),
    (v_rid, 'Farine', 150, 'g', (SELECT id FROM public.shopping_categories WHERE name = 'Épicerie salée'), 2),
    (v_rid, 'Beurre', 110, 'g', (SELECT id FROM public.shopping_categories WHERE name = 'Produits laitiers & œufs'), 3),
    (v_rid, 'Sucre roux', 80, 'g', (SELECT id FROM public.shopping_categories WHERE name = 'Épicerie sucrée'), 4),
    (v_rid, 'Sucre en poudre', 30, 'g', (SELECT id FROM public.shopping_categories WHERE name = 'Épicerie sucrée'), 5),
    (v_rid, 'Cannelle', 1, 'c. à café', (SELECT id FROM public.shopping_categories WHERE name = 'Condiments & épices'), 6),
    (v_rid, 'Sel', 1, 'pincée', (SELECT id FROM public.shopping_categories WHERE name = 'Condiments & épices'), 7);
  INSERT INTO public.recipe_steps (recipe_id, position, instruction) VALUES
    (v_rid, 0, 'Préchauffer le four à 180 °C. Beurrer un plat à gratin d''environ 24 cm avec 10 g de beurre.'),
    (v_rid, 1, 'Éplucher les pommes et les poires, retirer les cœurs et couper la chair en dés. Les mélanger avec le sucre en poudre et la cannelle, puis les étaler dans le plat.'),
    (v_rid, 2, 'Préparer la pâte à crumble : dans un saladier, mélanger la farine, le sucre roux et le sel. Ajouter le reste de beurre froid coupé en petits dés.'),
    (v_rid, 3, 'Du bout des doigts, sabler la pâte rapidement jusqu''à obtenir de grosses miettes irrégulières. Ne pas trop la travailler, sinon elle devient une boule.'),
    (v_rid, 4, 'Répartir les miettes sur les fruits sans tasser. Enfourner 30 à 35 min, jusqu''à ce que le dessus soit bien doré et que les fruits bouillonnent sur les bords.'),
    (v_rid, 5, 'Laisser tiédir 10 min avant de servir, seul ou avec une boule de glace à la vanille.');
    v_added := v_added + 1;
  END IF;

  -- ── Nouvelle : Butter chicken ──
  IF NOT EXISTS (SELECT 1 FROM public.recipes WHERE lower(title) = lower('Butter chicken')) THEN
    INSERT INTO public.recipes (family_id, title, category_id, prep_time_min, default_portions, created_by,
                                visibility, diets, origin, themes, budget)
    VALUES (v_family, 'Butter chicken', (SELECT id FROM public.recipe_categories WHERE name = 'Plat'),
            60, 4, v_user,
            'catalogue', ARRAY['sans_porc']::text[], 'inde',
            ARRAY['reconfort', 'fetes']::text[], 2)
    RETURNING id INTO v_rid;
  INSERT INTO public.recipe_ingredients (recipe_id, name, quantity, unit, shopping_category_id, position) VALUES
    (v_rid, 'Blancs de poulet', 600, 'g', (SELECT id FROM public.shopping_categories WHERE name = 'Viandes & poissons'), 0),
    (v_rid, 'Yaourt nature', 150, 'g', (SELECT id FROM public.shopping_categories WHERE name = 'Produits laitiers & œufs'), 1),
    (v_rid, 'Garam masala', 2, 'c. à café', (SELECT id FROM public.shopping_categories WHERE name = 'Condiments & épices'), 2),
    (v_rid, 'Paprika', 1, 'c. à café', (SELECT id FROM public.shopping_categories WHERE name = 'Condiments & épices'), 3),
    (v_rid, 'Cumin moulu', 1, 'c. à café', (SELECT id FROM public.shopping_categories WHERE name = 'Condiments & épices'), 4),
    (v_rid, 'Piment en poudre', 0.5, 'c. à café', (SELECT id FROM public.shopping_categories WHERE name = 'Condiments & épices'), 5),
    (v_rid, 'Gingembre frais', 15, 'g', (SELECT id FROM public.shopping_categories WHERE name = 'Fruits & légumes'), 6),
    (v_rid, 'Ail', 3, 'gousse', (SELECT id FROM public.shopping_categories WHERE name = 'Fruits & légumes'), 7),
    (v_rid, 'Citron', 0.5, 'pièce', (SELECT id FROM public.shopping_categories WHERE name = 'Fruits & légumes'), 8),
    (v_rid, 'Oignon', 2, 'pièce', (SELECT id FROM public.shopping_categories WHERE name = 'Fruits & légumes'), 9),
    (v_rid, 'Beurre', 40, 'g', (SELECT id FROM public.shopping_categories WHERE name = 'Produits laitiers & œufs'), 10),
    (v_rid, 'Tomates concassées', 1, 'boîte', (SELECT id FROM public.shopping_categories WHERE name = 'Épicerie salée'), 11),
    (v_rid, 'Crème liquide', 15, 'cl', (SELECT id FROM public.shopping_categories WHERE name = 'Produits laitiers & œufs'), 12),
    (v_rid, 'Sucre', 1, 'c. à café', (SELECT id FROM public.shopping_categories WHERE name = 'Épicerie sucrée'), 13),
    (v_rid, 'Riz basmati', 300, 'g', (SELECT id FROM public.shopping_categories WHERE name = 'Épicerie salée'), 14),
    (v_rid, 'Coriandre fraîche', 0.5, 'botte', (SELECT id FROM public.shopping_categories WHERE name = 'Fruits & légumes'), 15),
    (v_rid, 'Sel', NULL, NULL, (SELECT id FROM public.shopping_categories WHERE name = 'Condiments & épices'), 16);
  INSERT INTO public.recipe_steps (recipe_id, position, instruction) VALUES
    (v_rid, 0, 'Couper le poulet en cubes de 3 cm. Dans un saladier, mélanger le yaourt, le jus du demi-citron, la moitié des épices (garam masala, paprika, cumin, piment), 1 gousse d''ail écrasée et du sel. Ajouter le poulet et laisser mariner au frais au moins 30 min (idéalement quelques heures).'),
    (v_rid, 1, 'Faire cuire le poulet mariné 8 à 10 min dans une poêle bien chaude, en le retournant, jusqu''à ce qu''il soit doré et cuit à cœur. Réserver.'),
    (v_rid, 2, 'Dans une sauteuse, faire fondre le beurre et faire revenir les oignons émincés 8 min, jusqu''à ce qu''ils soient tendres et dorés.'),
    (v_rid, 3, 'Ajouter le reste de l''ail, le gingembre râpé et le reste des épices, et cuire 1 min en remuant. Verser les tomates concassées et le sucre, puis laisser mijoter 15 min.'),
    (v_rid, 4, 'Mixer la sauce jusqu''à ce qu''elle soit lisse, la remettre dans la sauteuse avec le poulet et la crème. Laisser mijoter 10 min à feu doux, en goûtant pour rectifier le sel.'),
    (v_rid, 5, 'Pendant ce temps, cuire le riz basmati selon le paquet.'),
    (v_rid, 6, 'Servir le poulet sur le riz, parsemé de coriandre ciselée. Se marie très bien avec du pain naan.');
    v_added := v_added + 1;
  END IF;

  -- ── Nouvelle : Bibimbap ──
  IF NOT EXISTS (SELECT 1 FROM public.recipes WHERE lower(title) = lower('Bibimbap')) THEN
    INSERT INTO public.recipes (family_id, title, category_id, prep_time_min, default_portions, created_by,
                                visibility, diets, origin, themes, budget)
    VALUES (v_family, 'Bibimbap', (SELECT id FROM public.recipe_categories WHERE name = 'Plat'),
            60, 4, v_user,
            'catalogue', ARRAY['sans_porc', 'sans_lactose']::text[], 'coree',
            ARRAY['reconfort']::text[], 2)
    RETURNING id INTO v_rid;
  INSERT INTO public.recipe_ingredients (recipe_id, name, quantity, unit, shopping_category_id, position) VALUES
    (v_rid, 'Riz rond', 300, 'g', (SELECT id FROM public.shopping_categories WHERE name = 'Épicerie salée'), 0),
    (v_rid, 'Bœuf haché', 250, 'g', (SELECT id FROM public.shopping_categories WHERE name = 'Viandes & poissons'), 1),
    (v_rid, 'Sauce soja', 3, 'c. à soupe', (SELECT id FROM public.shopping_categories WHERE name = 'Condiments & épices'), 2),
    (v_rid, 'Huile de sésame', 2, 'c. à soupe', (SELECT id FROM public.shopping_categories WHERE name = 'Condiments & épices'), 3),
    (v_rid, 'Gochujang', 3, 'c. à soupe', (SELECT id FROM public.shopping_categories WHERE name = 'Épicerie salée'), 4),
    (v_rid, 'Sucre', 2, 'c. à café', (SELECT id FROM public.shopping_categories WHERE name = 'Épicerie sucrée'), 5),
    (v_rid, 'Ail', 2, 'gousse', (SELECT id FROM public.shopping_categories WHERE name = 'Fruits & légumes'), 6),
    (v_rid, 'Carotte', 2, 'pièce', (SELECT id FROM public.shopping_categories WHERE name = 'Fruits & légumes'), 7),
    (v_rid, 'Courgette', 1, 'pièce', (SELECT id FROM public.shopping_categories WHERE name = 'Fruits & légumes'), 8),
    (v_rid, 'Champignon shiitake', 150, 'g', (SELECT id FROM public.shopping_categories WHERE name = 'Fruits & légumes'), 9),
    (v_rid, 'Épinards frais', 200, 'g', (SELECT id FROM public.shopping_categories WHERE name = 'Fruits & légumes'), 10),
    (v_rid, 'Germes de soja', 150, 'g', (SELECT id FROM public.shopping_categories WHERE name = 'Fruits & légumes'), 11),
    (v_rid, 'Œufs', 4, 'pièce', (SELECT id FROM public.shopping_categories WHERE name = 'Produits laitiers & œufs'), 12),
    (v_rid, 'Huile neutre', 3, 'c. à soupe', (SELECT id FROM public.shopping_categories WHERE name = 'Condiments & épices'), 13),
    (v_rid, 'Graines de sésame', 1, 'c. à soupe', (SELECT id FROM public.shopping_categories WHERE name = 'Épicerie salée'), 14),
    (v_rid, 'Sel', NULL, NULL, (SELECT id FROM public.shopping_categories WHERE name = 'Condiments & épices'), 15);
  INSERT INTO public.recipe_steps (recipe_id, position, instruction) VALUES
    (v_rid, 0, 'Rincer le riz à l''eau froide jusqu''à ce que l''eau soit claire, puis le cuire selon le paquet. Le garder au chaud sous couvercle.'),
    (v_rid, 1, 'Mélanger le bœuf haché avec 2 c. à soupe de sauce soja, 1 gousse d''ail écrasée, 1 c. à café de sucre et 1 c. à soupe d''huile de sésame. Laisser mariner 15 min.'),
    (v_rid, 2, 'Préparer la sauce : mélanger le gochujang, le reste de sauce soja, de sucre et d''huile de sésame avec 1 c. à soupe d''eau. Goûter : c''est piquant, en mettre moins pour les enfants.'),
    (v_rid, 3, 'Couper les carottes en bâtonnets fins, la courgette en demi-rondelles et les shiitakes en lamelles. Les faire sauter séparément 2 à 3 min chacun dans un peu d''huile, avec une pincée de sel, et les réserver dans des petits tas.'),
    (v_rid, 4, 'Plonger les épinards 30 s dans l''eau bouillante salée, les égoutter, les presser et les assaisonner d''une goutte d''huile de sésame. Faire de même 2 min avec les germes de soja.'),
    (v_rid, 5, 'Faire sauter le bœuf mariné 4 à 5 min à feu vif, en l''émiettant, jusqu''à ce qu''il soit bien cuit. Faire cuire les œufs au plat, jaune coulant.'),
    (v_rid, 6, 'Servir le riz dans de grands bols, disposer dessus les légumes, le bœuf et l''œuf. Parsemer de sésame et servir avec la sauce : on mélange tout à table.');
    v_added := v_added + 1;
  END IF;

  RAISE NOTICE 'recettes (lot-02) : % ajoutée(s)', v_added;
END $$;
