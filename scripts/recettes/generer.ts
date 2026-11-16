// Génère la migration des recettes livrées avec l'appli à partir de supabase/recettes/*.json.
//
//   npm run recettes            (= node --experimental-strip-types scripts/recettes/generer.ts)
//
// - corrections (kind "corrections") : remplace le contenu d'une recette de démo,
//   SEULEMENT si elle est encore exactement dans son état d'origine (empreinte md5
//   calculée ici en rejouant les migrations précédentes dans PGlite). Une recette
//   modifiée par la famille dans l'appli n'est jamais écrasée.
// - nouvelles (kind "nouvelles") : ajoutées si aucune recette ne porte déjà ce titre.
// Le fichier produit est déterministe : le test tests/unit/recettes.test.ts vérifie
// qu'il est à jour (on ne le modifie jamais à la main).

import { mkdtempSync, readdirSync, readFileSync, copyFileSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { fileURLToPath } from 'node:url'
import { cleTitre, valider, type FichierRecettes, type Recette } from './format.ts'
import { MAX_THEMES, ORIGINES, REGIMES, THEMES } from '../../src/lib/etiquettes.ts'

const ROOT = fileURLToPath(new URL('../../', import.meta.url))
export const DOSSIER_RECETTES = process.env.RECETTES_DIR || join(ROOT, 'supabase', 'recettes')
export const DOSSIER_MIGRATIONS = join(ROOT, 'supabase', 'migrations')
export const FICHIER_MIGRATION = '20261113170000_recettes_v1.sql'
export const FICHIER_PHOTOS = 'photos.json'
export const FICHIER_MIGRATION_PHOTOS = '20261114110000_recettes_photos.sql'
export const FICHIER_ETIQUETTES = 'etiquettes.json'
export const FICHIER_MIGRATION_ETIQUETTES = '20261116170100_recettes_etiquettes.sql'

/** Photo Unsplash (même règle que la contrainte recipes_image_url_origin, format figé). */
export const URL_PHOTO = /^https:\/\/images\.unsplash\.com\/photo-[A-Za-z0-9_-]+\?w=800&h=600&fit=crop&auto=format$/

export interface PhotoRecette {
  title: string
  url: string | null
  photographe?: string
  verifiee?: boolean
  note?: string
  remplace_ancienne?: boolean
}

/** Empreinte d'une recette en base (même expression ici et dans la migration). */
const EMPREINTE_SQL = (rid: string) => `md5(concat_ws('§',
      (SELECT r.title || '|' || coalesce(r.prep_time_min::text, '') || '|' || r.default_portions::text
         FROM public.recipes r WHERE r.id = ${rid}),
      (SELECT string_agg(concat_ws('|', i.name, i.quantity::text, i.unit, sc.name), '¶' ORDER BY i.position, i.name)
         FROM public.recipe_ingredients i LEFT JOIN public.shopping_categories sc ON sc.id = i.shopping_category_id
        WHERE i.recipe_id = ${rid}),
      (SELECT string_agg(s.instruction, '¶' ORDER BY s.position)
         FROM public.recipe_steps s WHERE s.recipe_id = ${rid})))`

export function lireRecettes(): { corrections: Recette[]; nouvelles: Recette[]; erreurs: string[] } {
  const corrections: Recette[] = []
  const nouvelles: Recette[] = []
  const erreurs: string[] = []
  const fichiers = readdirSync(DOSSIER_RECETTES).filter((f) => f.endsWith('.json') && f !== FICHIER_PHOTOS && f !== FICHIER_ETIQUETTES).sort()
  for (const f of fichiers) {
    const contenu = JSON.parse(readFileSync(join(DOSSIER_RECETTES, f), 'utf8')) as FichierRecettes
    erreurs.push(...valider(contenu, f))
    ;(contenu.kind === 'corrections' ? corrections : nouvelles).push(...contenu.recettes)
  }
  // Titres uniques entre fichiers (nouvelles entre elles et face aux titres corrigés)
  const vus = new Map<string, string>()
  for (const r of [...corrections, ...nouvelles]) {
    const k = cleTitre(r.title)
    if (vus.has(k)) erreurs.push(`Titre en double entre fichiers : « ${r.title} »`)
    vus.set(k, r.title)
  }
  return { corrections, nouvelles, erreurs }
}

const q = (s: string) => `'${s.replace(/'/g, "''")}'`
const num = (n: number | null) => (n === null ? 'NULL' : String(n))

function insertContenu(r: Recette): string {
  const ings = r.ingredients
    .map(
      (i, p) =>
        `    (v_rid, ${q(i.name)}, ${num(i.quantity)}, ${i.unit === null ? 'NULL' : q(i.unit)}, (SELECT id FROM public.shopping_categories WHERE name = ${q(i.rayon)}), ${p})`,
    )
    .join(',\n')
  const steps = r.steps.map((s, p) => `    (v_rid, ${p}, ${q(s)})`).join(',\n')
  return `  INSERT INTO public.recipe_ingredients (recipe_id, name, quantity, unit, shopping_category_id, position) VALUES
${ings};
  INSERT INTO public.recipe_steps (recipe_id, position, instruction) VALUES
${steps};`
}

/** Empreintes des recettes de démo telles que créées par les migrations précédentes. */
export async function empreintesOrigine(titres: string[]): Promise<Map<string, string>> {
  const dir = mkdtempSync(join(tmpdir(), 'recettes-'))
  for (const f of readdirSync(DOSSIER_MIGRATIONS)) {
    if (f.endsWith('.sql') && f < FICHIER_MIGRATION) copyFileSync(join(DOSSIER_MIGRATIONS, f), join(dir, f))
  }
  process.env.RLS_MIGRATIONS_DIR = dir
  const { createBench } = await import('../../tests/rls/harness.ts')
  const bench = await createBench({ fixtures: false })
  const res = new Map<string, string>()
  for (const t of titres) {
    const rows = await bench.db.query<{ id: string }>(`SELECT id FROM public.recipes WHERE title = $1`, [t])
    if (rows.rows.length !== 1) throw new Error(`Recette de démo « ${t} » : ${rows.rows.length} ligne(s) en base (1 attendue)`)
    const fp = await bench.db.query<{ fp: string }>(`SELECT ${EMPREINTE_SQL('$1::uuid')} AS fp`, [rows.rows[0].id])
    res.set(t, fp.rows[0].fp)
  }
  await bench.close()
  return res
}

export async function genererSQL(): Promise<string> {
  const { corrections, nouvelles, erreurs } = lireRecettes()
  if (erreurs.length) throw new Error('Recettes invalides :\n' + erreurs.join('\n'))
  const fps = await empreintesOrigine(corrections.map((r) => r.original_title!))

  const blocsCorr = corrections
    .map(
      (r) => `
  -- ── Correction : ${r.original_title} ──
  v_rid := NULL;
  SELECT rc.id INTO v_rid FROM public.recipes rc
   WHERE rc.title = ${q(r.original_title!)} AND ${EMPREINTE_SQL('rc.id')} = ${q(fps.get(r.original_title!)!)}
   LIMIT 1;
  IF v_rid IS NULL THEN
    v_skipped := v_skipped + 1;
    RAISE NOTICE 'recettes : « % » absente ou modifiée dans l''appli : non touchée', ${q(r.original_title!)};
  ELSE
    UPDATE public.recipes
       SET title = ${q(r.title)}, prep_time_min = ${r.prep_time_min}, default_portions = ${r.default_portions},
           category_id = (SELECT id FROM public.recipe_categories WHERE name = ${q(r.category)})
     WHERE id = v_rid;
    DELETE FROM public.recipe_ingredients WHERE recipe_id = v_rid;
    DELETE FROM public.recipe_steps WHERE recipe_id = v_rid;
${insertContenu(r)}
    v_fixed := v_fixed + 1;
  END IF;`,
    )
    .join('\n')

  const blocsNouv = nouvelles
    .map(
      (r) => `
  -- ── Nouvelle : ${r.title} ──
  IF NOT EXISTS (SELECT 1 FROM public.recipes WHERE lower(title) = lower(${q(r.title)})) THEN
    INSERT INTO public.recipes (family_id, title, category_id, prep_time_min, default_portions, created_by)
    VALUES (v_family, ${q(r.title)}, (SELECT id FROM public.recipe_categories WHERE name = ${q(r.category)}),
            ${r.prep_time_min}, ${r.default_portions}, v_user)
    RETURNING id INTO v_rid;
${insertContenu(r)}
    v_added := v_added + 1;
  END IF;`,
    )
    .join('\n')

  return `-- ============================================================
-- Migration : recettes livrées avec l'appli — v1
-- ============================================================
-- FICHIER GÉNÉRÉ par scripts/recettes/generer.ts à partir de
-- supabase/recettes/*.json — NE PAS MODIFIER À LA MAIN (npm run recettes).
--
-- • ${corrections.length} recettes de démo corrigées (temps réalistes, quantités, rayons,
--   précautions sanitaires). Une recette n'est corrigée que si elle est encore
--   EXACTEMENT dans son état d'origine (empreinte) : si la famille l'a modifiée
--   dans l'appli, elle n'est pas touchée (message NOTICE).
-- • ${nouvelles.length} nouvelles recettes, ajoutées seulement si aucune recette ne porte
--   déjà le même titre. Rattachées au foyer et au compte des recettes de démo
--   (sinon : premier foyer, premier compte).
-- Recettes rédigées pour l'appli (pas de texte copié) ; quantités vérifiées
-- sur des références publiques (liste dans supabase/recettes/*.json).
--
-- Idempotente : relancée, elle ne change plus rien.
-- ============================================================

DO $$
DECLARE
  v_family  uuid;
  v_user    uuid;
  v_rid     uuid;
  v_fixed   integer := 0;
  v_skipped integer := 0;
  v_added   integer := 0;
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
    RAISE EXCEPTION 'recettes : il faut au moins 1 foyer avant cette migration';
  END IF;
${blocsCorr}
${blocsNouv}

  RAISE NOTICE 'recettes : % corrigée(s), % non touchée(s), % ajoutée(s)', v_fixed, v_skipped, v_added;
END $$;
`
}

/** Photos des recettes du catalogue (supabase/recettes/photos.json). */
export function lirePhotos(): { photos: PhotoRecette[]; erreurs: string[] } {
  const erreurs: string[] = []
  let photos: PhotoRecette[] = []
  try {
    photos = (JSON.parse(readFileSync(join(DOSSIER_RECETTES, FICHIER_PHOTOS), 'utf8')) as { photos: PhotoRecette[] }).photos
  } catch {
    return { photos: [], erreurs: [`${FICHIER_PHOTOS} absent ou illisible`] }
  }
  const { corrections, nouvelles } = lireRecettes()
  const titres = new Set([...corrections, ...nouvelles].map((r) => r.title))
  const vusT = new Set<string>()
  const vusU = new Set<string>()
  for (const p of photos) {
    if (!titres.has(p.title)) erreurs.push(`photo pour un titre inconnu : « ${p.title} »`)
    if (vusT.has(p.title)) erreurs.push(`deux photos pour « ${p.title} »`)
    vusT.add(p.title)
    if (p.url !== null) {
      if (!URL_PHOTO.test(p.url)) erreurs.push(`URL au mauvais format pour « ${p.title} »`)
      if (vusU.has(p.url)) erreurs.push(`même photo utilisée deux fois (« ${p.title} »)`)
      vusU.add(p.url)
      if (p.verifiee !== true) erreurs.push(`photo non vérifiée pour « ${p.title} »`)
    }
  }
  for (const t of titres) if (!vusT.has(t)) erreurs.push(`pas d'entrée photo pour « ${t} »`)
  return { photos, erreurs }
}

export function genererPhotosSQL(): string {
  const { photos, erreurs } = lirePhotos()
  if (erreurs.length) throw new Error('Photos invalides :\n' + erreurs.join('\n'))
  const avec = photos.filter((p) => p.url)
  const lignes = avec.map((p) => `    (${q(p.title)}, ${q(p.url!)})`).join(',\n')
  return `-- ============================================================
-- Migration : photos des recettes du catalogue commun
-- ============================================================
-- FICHIER GÉNÉRÉ par scripts/recettes/generer.ts à partir de
-- supabase/recettes/photos.json — NE PAS MODIFIER À LA MAIN (npm run recettes).
--
-- ${avec.length} photos Unsplash (licence Unsplash : usage gratuit, attribution non
-- obligatoire), chacune vérifiée à l'œil. Ne touche QUE les recettes du
-- catalogue (visibility = 'catalogue') sans photo ou avec une photo Unsplash :
-- une photo envoyée dans l'appli (chemin de notre stockage) n'est jamais remplacée.
-- Les recettes ajoutées par les familles ne sont pas concernées.
-- Nécessite la migration 17 (colonne visibility). Idempotente.
-- ============================================================

DO $$
DECLARE
  v_n integer;
BEGIN
  WITH photos(title, url) AS (
    VALUES
${lignes}
  ), upd AS (
    UPDATE public.recipes r
       SET image_url = p.url
      FROM photos p
     WHERE r.title = p.title
       AND r.visibility = 'catalogue'
       AND (r.image_url IS NULL OR r.image_url LIKE 'https://images.unsplash.com/%')
       AND r.image_url IS DISTINCT FROM p.url
    RETURNING 1
  )
  SELECT count(*) INTO v_n FROM upd;
  RAISE NOTICE 'recettes_photos : % photo(s) mise(s) à jour', v_n;
END $$;
`
}

export interface EtiquettesRecette {
  title: string
  diets: string[]
  origin: string | null
  themes: string[]
  budget: number | null
}

/** Étiquettes des recettes du catalogue (supabase/recettes/etiquettes.json). */
export function lireEtiquettes(): { etiquettes: EtiquettesRecette[]; erreurs: string[] } {
  let etiquettes: EtiquettesRecette[] = []
  try {
    etiquettes = (JSON.parse(readFileSync(join(DOSSIER_RECETTES, FICHIER_ETIQUETTES), 'utf8')) as { etiquettes: EtiquettesRecette[] }).etiquettes
  } catch {
    return { etiquettes: [], erreurs: [`${FICHIER_ETIQUETTES} absent ou illisible`] }
  }
  const erreurs: string[] = []
  const { corrections, nouvelles } = lireRecettes()
  const titres = new Set([...corrections, ...nouvelles].map((r) => r.title))
  const regimes = new Set(REGIMES.map((e) => e.key))
  const origines = new Set(ORIGINES.map((e) => e.key))
  const themes = new Set(THEMES.map((e) => e.key))
  const vus = new Set<string>()
  for (const e of etiquettes) {
    const t = `« ${e.title} »`
    if (!titres.has(e.title)) erreurs.push(`étiquettes pour un titre inconnu : ${t}`)
    if (vus.has(e.title)) erreurs.push(`deux entrées pour ${t}`)
    vus.add(e.title)
    for (const d of e.diets) if (!regimes.has(d)) erreurs.push(`régime inconnu « ${d} » pour ${t}`)
    if (new Set(e.diets).size !== e.diets.length) erreurs.push(`régime en double pour ${t}`)
    if (e.diets.includes('vegan') && !e.diets.includes('vegetarien')) erreurs.push(`vegan sans végétarien pour ${t}`)
    if (e.origin !== null && !origines.has(e.origin)) erreurs.push(`origine inconnue « ${e.origin} » pour ${t}`)
    for (const th of e.themes) if (!themes.has(th)) erreurs.push(`thème inconnu « ${th} » pour ${t}`)
    if (new Set(e.themes).size !== e.themes.length) erreurs.push(`thème en double pour ${t}`)
    if (e.themes.length > MAX_THEMES) erreurs.push(`plus de ${MAX_THEMES} thèmes pour ${t}`)
    if (e.budget !== null && ![1, 2, 3].includes(e.budget)) erreurs.push(`budget invalide pour ${t}`)
  }
  for (const t of titres) if (!vus.has(t)) erreurs.push(`pas d'entrée d'étiquettes pour « ${t} »`)
  return { etiquettes, erreurs }
}

export function genererEtiquettesSQL(): string {
  const { etiquettes, erreurs } = lireEtiquettes()
  if (erreurs.length) throw new Error('Étiquettes invalides :\n' + erreurs.join('\n'))
  const arr = (a: string[]) => (a.length ? `ARRAY[${a.map(q).join(', ')}]::text[]` : `'{}'::text[]`)
  const lignes = etiquettes
    .map((e) => `    (${q(e.title)}, ${arr(e.diets)}, ${e.origin === null ? 'NULL::text' : q(e.origin)}, ${arr(e.themes)}, ${e.budget === null ? 'NULL::smallint' : `${e.budget}::smallint`})`)
    .join(',\n')
  return `-- ============================================================
-- Migration : étiquettes des recettes du catalogue commun
-- ============================================================
-- FICHIER GÉNÉRÉ par scripts/recettes/generer.ts à partir de
-- supabase/recettes/etiquettes.json — NE PAS MODIFIER À LA MAIN (npm run recettes).
--
-- ${etiquettes.length} recettes. Ne touche QUE les recettes du catalogue
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
${lignes}
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
`
}

// Exécution directe : écrit la migration
if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) {
  const sql = await genererSQL()
  writeFileSync(join(DOSSIER_MIGRATIONS, FICHIER_MIGRATION), sql)
  console.log(`Écrit : supabase/migrations/${FICHIER_MIGRATION}`)
  if (lirePhotos().photos.length) {
    writeFileSync(join(DOSSIER_MIGRATIONS, FICHIER_MIGRATION_PHOTOS), genererPhotosSQL())
    console.log(`Écrit : supabase/migrations/${FICHIER_MIGRATION_PHOTOS}`)
  }
  if (lireEtiquettes().etiquettes.length) {
    writeFileSync(join(DOSSIER_MIGRATIONS, FICHIER_MIGRATION_ETIQUETTES), genererEtiquettesSQL())
    console.log(`Écrit : supabase/migrations/${FICHIER_MIGRATION_ETIQUETTES}`)
  }
}
