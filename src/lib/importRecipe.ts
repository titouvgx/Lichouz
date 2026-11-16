// Import d'une recette par lien (v1.99.0, lot V1-3) — côté appli.
//
// ⚠️ DÉSACTIVÉ. Décision de Titouan (16/11/2026) : le bouton « Importer depuis
// un lien » existe et l'infrastructure est prête (fonction serveur
// supabase/functions/importer-recette), mais RIEN n'est importé tant que la
// question juridique n'est pas tranchée (à éclaircir après la v1.99.0).
// Pour activer un jour : IMPORT_ENABLED = true ici, ET secrets IMPORT_ENABLED /
// IMPORT_SITES de la fonction (voir supabase/functions/README.md).

import { supabase } from './supabase'
import { INGREDIENT_NAME_MAX, INGREDIENT_UNIT_MAX } from './limits'

export const IMPORT_ENABLED = false

/** Ce que renvoie la fonction serveur (voir lire.ts). */
export interface ImportedRecipe {
  titre: string
  ingredients: string[]
  etapes: string[]
  portions: number | null
  minutes: number | null
  source: string
}

export interface ImportedForm {
  title: string
  portions: number
  minutes: number | null
  ingredients: { qty: string; unit: string; name: string }[]
  steps: string[]
}

// Unités reconnues en tête de ligne → forme écrite dans le formulaire
const UNITS: [RegExp, string][] = [
  [/^(?:cuill(?:è|e)res?|cuil\.?|c\.?)\s*(?:à|a)\s*(?:soupe|s\.?)|^c\.?\s*à\s*s\.?|^cas\b|^càs\b/i, 'c. à soupe'],
  [/^(?:cuill(?:è|e)res?|cuil\.?|c\.?)\s*(?:à|a)\s*(?:café|cafe|c\.?)|^c\.?\s*à\s*c\.?|^cac\b|^càc\b/i, 'c. à café'],
  [/^(?:kg|kilos?|kilogrammes?)\b/i, 'kg'],
  [/^(?:mg)\b/i, 'mg'],
  [/^(?:g|gr|grammes?)\b/i, 'g'],
  [/^(?:ml|millilitres?)\b/i, 'ml'],
  [/^(?:cl|centilitres?)\b/i, 'cl'],
  [/^(?:dl|décilitres?)\b/i, 'dl'],
  [/^(?:l|litres?)\b/i, 'l'],
  [/^(pincées?|gousses?|tranches?|boîtes?|boites?|sachets?|verres?|tasses?|brins?|feuilles?|bottes?|pots?|morceaux?|bouquets?|branches?|filets?|noix|poignées?)\b/i, ''],
]

const FRACTIONS: Record<string, number> = { '½': 0.5, '¼': 0.25, '¾': 0.75, '⅓': 1 / 3, '⅔': 2 / 3 }

const frNumber = (n: number) => String(Math.round(n * 100) / 100).replace('.', ',')

/** « 200 g de farine » → { qty: '200', unit: 'g', name: 'farine' } (au mieux ; sinon tout en nom). */
export function splitIngredientLine(raw: string): { qty: string; unit: string; name: string } {
  let line = raw.replace(/\s+/g, ' ').trim()
  let qty: number | null = null

  // Quantité : 2, 1,5, 1.5, 1/2, 1 1/2, ½, 1 ½ ; « 2 à 3 » / « 2-3 » → la plus grande
  let used = 0
  let v = 0
  const mixed = line.match(/^(\d+)\s+(\d+)\/(\d+)/)
  const frac = line.match(/^(\d+)\/(\d+)/)
  const dec = line.match(/^(\d+(?:[.,]\d+)?)?\s*([½¼¾⅓⅔])?/)
  if (mixed && Number(mixed[3])) {
    v = Number(mixed[1]) + Number(mixed[2]) / Number(mixed[3])
    used = mixed[0].length
  } else if (frac && Number(frac[2])) {
    v = Number(frac[1]) / Number(frac[2])
    used = frac[0].length
  } else if (dec && (dec[1] || dec[2])) {
    v = (dec[1] ? Number(dec[1].replace(',', '.')) : 0) + (dec[2] ? FRACTIONS[dec[2]] : 0)
    used = dec[0].length
  }
  if (v > 0) {
    const range = line.slice(used).match(/^\s*(?:à|a|-|–|ou)\s*(\d+(?:[.,]\d+)?)/)
    if (range) {
      v = Math.max(v, Number(range[1].replace(',', '.')))
      used += range[0].length
    }
    qty = v
    line = line.slice(used).trim()
  }

  let unit = ''
  if (qty !== null) {
    for (const [re, label] of UNITS) {
      const u = line.match(re)
      if (u) {
        unit = label || u[0].toLowerCase()
        line = line.slice(u[0].length).trim()
        break
      }
    }
  }
  // « de farine », « d’ail », « d'huile »
  line = line.replace(/^(?:de |d’|d')\s*/i, '').trim()

  return {
    qty: qty === null ? '' : frNumber(qty),
    unit: unit.slice(0, INGREDIENT_UNIT_MAX),
    name: (line || raw.trim()).slice(0, INGREDIENT_NAME_MAX),
  }
}

/** Recette importée → valeurs du formulaire. */
export function toFormRecipe(r: ImportedRecipe): ImportedForm {
  return {
    title: r.titre,
    portions: r.portions ?? 4,
    minutes: r.minutes,
    ingredients: r.ingredients.map(splitIngredientLine),
    steps: r.etapes,
  }
}

/** Appelle la fonction serveur (jamais tant que IMPORT_ENABLED est faux). */
export async function importFromUrl(url: string): Promise<ImportedRecipe> {
  if (!IMPORT_ENABLED) throw new Error('L’import par lien n’est pas encore activé.')
  if (!supabase) throw new Error('Supabase non configuré')
  const { data, error } = await supabase.functions.invoke('importer-recette', { body: { url: url.trim() } })
  if (error) {
    let message = 'La recette n’a pas pu être importée.'
    try {
      const corps = await (error as { context?: Response }).context?.json()
      if (corps?.erreur) message = corps.erreur
    } catch { /* message par défaut */ }
    throw new Error(message)
  }
  return (data as { recette: ImportedRecipe }).recette
}
