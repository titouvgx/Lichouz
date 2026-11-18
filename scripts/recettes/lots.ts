// Lots de recettes du catalogue (supabase/recettes/lots/lot-NN.json).
//
//   npm run recettes   (génère aussi les migrations des lots)
//
// Un lot = 1 fichier JSON (recettes + étiquettes + photo) → 1 migration de recettes
// (+ 1 migration de photos quand au moins une photo est choisie). Les migrations
// déjà appliquées (16, 18, 25 bis) ne sont JAMAIS régénérées : chaque lot a les siennes.
// Ajout seulement : une recette dont le titre existe déjà n'est pas touchée. Idempotent.

import { readdirSync, readFileSync, writeFileSync } from 'node:fs'
import { join } from 'node:path'
import { fileURLToPath } from 'node:url'
import { cleTitre, valider, type FichierRecettes, type Recette } from './format.ts'
import { DOSSIER_MIGRATIONS, DOSSIER_RECETTES, URL_PHOTO, insertContenu, lireRecettes, q } from './generer.ts'
import { MAX_THEMES, ORIGINES, REGIMES, THEMES } from '../../src/lib/etiquettes.ts'

export const DOSSIER_LOTS = join(DOSSIER_RECETTES, 'lots')

export interface EtiquettesLot { diets: string[]; origin: string | null; themes: string[]; budget: 1 | 2 | 3 | null }
export interface PhotoLot { url: string; photographe: string; verifiee: boolean; note: string }
export interface RecetteLot extends Recette { etiquettes: EtiquettesLot; photo: PhotoLot | null }
export interface Lot { nom: string; migration: string; migration_photos: string; recettes: RecetteLot[] }

export function lireLots(): { lots: Lot[]; erreurs: string[] } {
  const erreurs: string[] = []
  const lots: Lot[] = []
  const { corrections, nouvelles } = lireRecettes()
  const vus = new Set([...corrections, ...nouvelles].map((r) => cleTitre(r.title)))
  const regimes = new Set(REGIMES.map((e) => e.key))
  const origines = new Set(ORIGINES.map((e) => e.key))
  const themes = new Set(THEMES.map((e) => e.key))
  const noms = readdirSync(DOSSIER_LOTS).filter((f) => /^lot-\d+\.json$/.test(f)).sort()
  for (const nom of noms) {
    const brut = JSON.parse(readFileSync(join(DOSSIER_LOTS, nom), 'utf8')) as Lot & { kind: 'nouvelles' }
    erreurs.push(...valider({ kind: brut.kind, recettes: brut.recettes } as FichierRecettes, nom))
    if (!/^\d{14}_recettes_lot_\d+\.sql$/.test(brut.migration ?? '')) erreurs.push(`${nom} : nom de migration invalide`)
    if (!/^\d{14}_recettes_lot_\d+_photos\.sql$/.test(brut.migration_photos ?? '')) erreurs.push(`${nom} : nom de migration photos invalide`)
    for (const r of brut.recettes) {
      const t = `${nom} › ${r.title}`
      if (vus.has(cleTitre(r.title))) erreurs.push(`${t} : titre déjà présent au catalogue ou dans un autre lot`)
      vus.add(cleTitre(r.title))
      const e = r.etiquettes
      if (!e) { erreurs.push(`${t} : étiquettes manquantes`); continue }
      if (!e.diets.every((x) => regimes.has(x)) || new Set(e.diets).size !== e.diets.length) erreurs.push(`${t} : régime invalide`)
      if (e.diets.includes('vegan') && !e.diets.includes('vegetarien')) erreurs.push(`${t} : vegan sans végétarien`)
      if (e.origin !== null && !origines.has(e.origin)) erreurs.push(`${t} : origine invalide`)
      if (!e.themes.every((x) => themes.has(x)) || new Set(e.themes).size !== e.themes.length || e.themes.length > MAX_THEMES) erreurs.push(`${t} : thèmes invalides`)
      if (e.budget !== null && ![1, 2, 3].includes(e.budget)) erreurs.push(`${t} : budget invalide`)
      if (r.photo && (!URL_PHOTO.test(r.photo.url) || r.photo.verifiee !== true)) erreurs.push(`${t} : photo au mauvais format ou non vérifiée`)
    }
    brut.nom = nom.replace(/\.json$/, '')
    lots.push(brut)
  }
  return { lots, erreurs }
}

const arr = (a: string[]) => (a.length ? `ARRAY[${a.map(q).join(', ')}]::text[]` : `'{}'::text[]`)

export function genererLotSQL(lot: Lot): string {
  const blocs = lot.recettes
    .map(
      (r) => `
  -- ── Nouvelle : ${r.title} ──
  IF NOT EXISTS (SELECT 1 FROM public.recipes WHERE lower(title) = lower(${q(r.title)})) THEN
    INSERT INTO public.recipes (family_id, title, category_id, prep_time_min, default_portions, created_by,
                                visibility, diets, origin, themes, budget)
    VALUES (v_family, ${q(r.title)}, (SELECT id FROM public.recipe_categories WHERE name = ${q(r.category)}),
            ${r.prep_time_min}, ${r.default_portions}, v_user,
            'catalogue', ${arr(r.etiquettes.diets)}, ${r.etiquettes.origin === null ? 'NULL' : q(r.etiquettes.origin)},
            ${arr(r.etiquettes.themes)}, ${r.etiquettes.budget === null ? 'NULL' : r.etiquettes.budget})
    RETURNING id INTO v_rid;
${insertContenu(r)}
    v_added := v_added + 1;
  END IF;`,
    )
    .join('\n')
  return `-- ============================================================
-- Migration : recettes du catalogue — ${lot.nom}
-- ============================================================
-- FICHIER GÉNÉRÉ par scripts/recettes/lots.ts à partir de
-- supabase/recettes/lots/${lot.nom}.json — NE PAS MODIFIER À LA MAIN (npm run recettes).
--
-- ${lot.recettes.length} recettes ajoutées au catalogue commun (visibility = 'catalogue',
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
    RAISE EXCEPTION 'recettes (${lot.nom}) : il faut au moins 1 foyer avant cette migration';
  END IF;
${blocs}

  RAISE NOTICE 'recettes (${lot.nom}) : % ajoutée(s)', v_added;
END $$;
`
}

/** null = aucune photo choisie dans ce lot (pas de migration de photos). */
export function genererLotPhotosSQL(lot: Lot): string | null {
  const avec = lot.recettes.filter((r) => r.photo)
  if (!avec.length) return null
  const lignes = avec.map((r) => `    (${q(r.title)}, ${q(r.photo!.url)})`).join(',\n')
  return `-- ============================================================
-- Migration : photos des recettes du catalogue — ${lot.nom}
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
${lignes}
  ), upd AS (
    UPDATE public.recipes r SET image_url = p.url
      FROM p
     WHERE r.title = p.title AND r.visibility = 'catalogue' AND r.image_url IS NULL
    RETURNING 1
  )
  SELECT count(*) INTO v_n FROM upd;
  RAISE NOTICE 'photos (${lot.nom}) : % recette(s) mise(s) à jour', v_n;
END $$;
`
}

if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) {
  const { lots, erreurs } = lireLots()
  if (erreurs.length) throw new Error('Lots invalides :\n' + erreurs.join('\n'))
  for (const lot of lots) {
    writeFileSync(join(DOSSIER_MIGRATIONS, lot.migration), genererLotSQL(lot))
    console.log(`Écrit : supabase/migrations/${lot.migration}`)
    const ph = genererLotPhotosSQL(lot)
    if (ph) {
      writeFileSync(join(DOSSIER_MIGRATIONS, lot.migration_photos), ph)
      console.log(`Écrit : supabase/migrations/${lot.migration_photos}`)
    }
  }
}
