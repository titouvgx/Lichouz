-- ============================================================
-- Migration 25 : étiquettes des recettes (v1.8.0, lot V1-2)
-- ============================================================
-- - recipes.diets   : régimes (plusieurs), posés à la main, indicatifs
-- - recipes.origin  : région de France ou pays (une seule, facultative)
-- - recipes.themes  : thèmes (5 au plus)
-- - recipes.budget  : 1 = €, 2 = €€, 3 = €€€ (facultatif)
-- LISTE FIXE : la base refuse toute autre valeur. La même liste est dans
-- src/lib/etiquettes.ts (le test tests/unit/etiquettes.test.ts compare les deux).
-- Ajouter une valeur = nouvelle migration qui recrée la contrainte + etiquettes.ts.
--
-- Droits : aucun changement. Qui peut modifier la recette peut poser ses étiquettes
-- (règles RLS existantes ; le catalogue reste réservé au super-admin).
-- Une recette partagée n'a qu'une série d'étiquettes (décision du 16/11/2026).
--
-- Types de plat : ajout de Apéritif, Sauce, Petit-déj & goûter, Boisson & cocktail,
-- et nouvel ordre d'affichage.
--
-- Les étiquettes des 50 recettes livrées sont posées par la migration GÉNÉRÉE
-- suivante (supabase/recettes/etiquettes.json → npm run recettes).
-- Idempotente.
-- ============================================================

-- Vrai si chaque valeur est dans la liste, sans doublon ni NULL.
CREATE OR REPLACE FUNCTION public.tags_in_list(p_vals text[], p_allowed text[])
RETURNS boolean LANGUAGE sql IMMUTABLE SET search_path = '' AS $$
  SELECT p_vals IS NOT NULL
     AND array_position(p_vals, NULL) IS NULL
     AND p_vals <@ p_allowed
     AND cardinality(p_vals) = (SELECT count(DISTINCT v) FROM unnest(p_vals) AS v)
$$;
-- Exécutable par tous : une contrainte CHECK appelle la fonction avec les droits de la
-- personne qui écrit (sans ce droit, plus personne ne pourrait écrire une recette).
-- Fonction pure : elle ne lit aucune table.
REVOKE ALL ON FUNCTION public.tags_in_list(text[], text[]) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.tags_in_list(text[], text[]) TO anon, authenticated, service_role;

ALTER TABLE public.recipes ADD COLUMN IF NOT EXISTS diets  text[]   NOT NULL DEFAULT '{}';
ALTER TABLE public.recipes ADD COLUMN IF NOT EXISTS origin text;
ALTER TABLE public.recipes ADD COLUMN IF NOT EXISTS themes text[]   NOT NULL DEFAULT '{}';
ALTER TABLE public.recipes ADD COLUMN IF NOT EXISTS budget smallint;

ALTER TABLE public.recipes DROP CONSTRAINT IF EXISTS recipes_diets_list;
ALTER TABLE public.recipes ADD CONSTRAINT recipes_diets_list CHECK (public.tags_in_list(diets, ARRAY[
  -- liste: diets
  'vegetarien', 'vegan', 'sans_gluten', 'sans_lactose', 'sans_porc'
  -- fin
]::text[]));

ALTER TABLE public.recipes DROP CONSTRAINT IF EXISTS recipes_origin_list;
ALTER TABLE public.recipes ADD CONSTRAINT recipes_origin_list CHECK (origin IS NULL OR origin = ANY (ARRAY[
  -- liste: origin
  'france', 'alsace', 'auvergne', 'bourgogne', 'bretagne', 'corse', 'dauphine', 'limousin',
  'lorraine', 'lyonnais', 'nord', 'normandie', 'pays_basque', 'provence', 'savoie', 'sud_ouest',
  'antilles', 'italie', 'espagne', 'portugal', 'grece', 'belgique', 'royaume_uni', 'europe_est',
  'maghreb', 'moyen_orient', 'afrique', 'inde', 'chine', 'japon', 'coree', 'asie_sud_est',
  'etats_unis', 'mexique', 'amerique_sud'
  -- fin
]::text[]));

ALTER TABLE public.recipes DROP CONSTRAINT IF EXISTS recipes_themes_list;
ALTER TABLE public.recipes ADD CONSTRAINT recipes_themes_list CHECK (cardinality(themes) <= 5 AND public.tags_in_list(themes, ARRAY[
  -- liste: themes
  'films', 'fetes', 'etudiant', 'enfants', 'reconfort', 'leger', 'ete', 'hiver', 'pique_nique', 'barbecue'
  -- fin
]::text[]));

ALTER TABLE public.recipes DROP CONSTRAINT IF EXISTS recipes_budget_range;
ALTER TABLE public.recipes ADD CONSTRAINT recipes_budget_range CHECK (budget IS NULL OR budget BETWEEN 1 AND 3);

COMMENT ON COLUMN public.recipes.diets  IS 'Régimes (liste fixe, indicatifs) — migration 25';
COMMENT ON COLUMN public.recipes.origin IS 'Origine : région de France ou pays (liste fixe) — migration 25';
COMMENT ON COLUMN public.recipes.themes IS 'Thèmes (liste fixe, 5 au plus) — migration 25';
COMMENT ON COLUMN public.recipes.budget IS '1 = €, 2 = €€, 3 = €€€ — migration 25';

-- Filtres : l'écran charge l'index complet ; ces index servent aux futures requêtes côté base.
CREATE INDEX IF NOT EXISTS recipes_diets_gin  ON public.recipes USING gin (diets);
CREATE INDEX IF NOT EXISTS recipes_themes_gin ON public.recipes USING gin (themes);

-- Types de plat --------------------------------------------------
INSERT INTO public.recipe_categories (name, color, position) VALUES
  ('Apéritif',            '#B08A3A', 0),
  ('Sauce',               '#B05A3A', 4),
  ('Petit-déj & goûter',  '#7A6AB0', 6),
  ('Boisson & cocktail',  '#3A8AA0', 7)
ON CONFLICT (name) DO NOTHING;

UPDATE public.recipe_categories c
   SET position = o.pos
  FROM (VALUES ('Apéritif', 0), ('Entrée', 1), ('Plat', 2), ('Accompagnement', 3),
               ('Sauce', 4), ('Dessert', 5), ('Petit-déj & goûter', 6), ('Boisson & cocktail', 7))
       AS o(name, pos)
 WHERE c.name = o.name AND c.position IS DISTINCT FROM o.pos;
