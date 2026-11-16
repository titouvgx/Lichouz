// Lecture d'une page de recette (v1.99.0, lot V1-3) : on ne garde que les
// FAITS publiés par le site au format standard schema.org/Recipe (balise
// <script type="application/ld+json">) : titre, ingrédients, étapes, portions,
// temps. Jamais la photo ni les textes d'introduction.
// Aucune dépendance : utilisé par la fonction serveur (Deno) ET testé dans Node.

export interface RecetteImportee {
  titre: string
  ingredients: string[]
  etapes: string[]
  portions: number | null
  minutes: number | null
  source: string
}

// Limites de la base (migration 22, src/lib/limits.ts)
const TITRE_MAX = 120
const INGREDIENT_MAX = 80 + 40 // quantité + nom : redécoupé ensuite par l'appli
const ETAPE_MAX = 1000
const INGREDIENTS_MAX = 60
const ETAPES_MAX = 40

/** Texte brut : entités HTML décodées, balises retirées, espaces resserrés. */
export function texte(v: unknown): string {
  if (typeof v !== 'string') return ''
  return v
    .replace(/<[^>]*>/g, ' ')
    .replace(/&nbsp;|&#160;/gi, ' ')
    .replace(/&amp;/gi, '&')
    .replace(/&lt;/gi, '<')
    .replace(/&gt;/gi, '>')
    .replace(/&quot;/gi, '"')
    .replace(/&#0?39;|&apos;|&rsquo;|&#8217;/gi, '’')
    .replace(/&#(\d+);/g, (_, n) => String.fromCodePoint(Number(n)))
    .replace(/&#x([0-9a-f]+);/gi, (_, n) => String.fromCodePoint(parseInt(n, 16)))
    .replace(/\s+/g, ' ')
    .trim()
}

/** Durée ISO 8601 (« PT1H30M », « P0DT0H45M ») en minutes. */
export function minutesIso(v: unknown): number | null {
  if (typeof v !== 'string') return null
  const m = v.trim().match(/^P(?:(\d+)D)?(?:T(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?)?$/i)
  if (!m) return null
  const total = Number(m[1] ?? 0) * 1440 + Number(m[2] ?? 0) * 60 + Number(m[3] ?? 0) + Math.round(Number(m[4] ?? 0) / 60)
  return total > 0 && total < 7 * 1440 ? total : null
}

function portions(v: unknown): number | null {
  const s = Array.isArray(v) ? v[0] : v
  const n = typeof s === 'number' ? s : Number(String(s ?? '').match(/\d+/)?.[0])
  return Number.isFinite(n) && n >= 1 && n <= 50 ? Math.round(n) : null
}

const estRecette = (o: unknown): o is Record<string, unknown> => {
  if (!o || typeof o !== 'object') return false
  const t = (o as Record<string, unknown>)['@type']
  return t === 'Recipe' || (Array.isArray(t) && t.includes('Recipe'))
}

/** Cherche un objet Recipe dans un JSON-LD (objet, tableau ou @graph, imbriqués). */
function trouverRecette(n: unknown, profondeur = 0): Record<string, unknown> | null {
  if (profondeur > 6 || !n || typeof n !== 'object') return null
  if (estRecette(n)) return n
  const liste = Array.isArray(n) ? n : [(n as Record<string, unknown>)['@graph'], (n as Record<string, unknown>).mainEntity].filter(Boolean)
  for (const x of liste) {
    const r = trouverRecette(x, profondeur + 1)
    if (r) return r
  }
  return null
}

/** Étapes : texte, HowToStep, HowToSection (avec itemListElement), listes imbriquées. */
function etapes(v: unknown, sortie: string[] = [], profondeur = 0): string[] {
  if (profondeur > 4 || sortie.length >= ETAPES_MAX) return sortie
  if (typeof v === 'string') {
    // Certains sites mettent toutes les étapes dans un seul texte, une par ligne
    for (const ligne of v.split(/\r?\n|<br\s*\/?>/i)) {
      const t = texte(ligne)
      if (t) sortie.push(t)
    }
  } else if (Array.isArray(v)) {
    for (const x of v) etapes(x, sortie, profondeur + 1)
  } else if (v && typeof v === 'object') {
    const o = v as Record<string, unknown>
    if (o.itemListElement) etapes(o.itemListElement, sortie, profondeur + 1)
    else etapes(o.text ?? o.name, sortie, profondeur + 1)
  }
  return sortie
}

const couper = (s: string, max: number) => (s.length > max ? s.slice(0, max - 1).trimEnd() + '…' : s)

/** Recette lue dans le HTML d'une page, ou null si la page n'en publie pas. */
export function lireRecette(html: string, source: string): RecetteImportee | null {
  const blocs = html.matchAll(/<script[^>]*type\s*=\s*["']?application\/ld\+json["']?[^>]*>([\s\S]*?)<\/script>/gi)
  for (const b of blocs) {
    let json: unknown
    try {
      json = JSON.parse(b[1].trim())
    } catch {
      continue
    }
    const r = trouverRecette(json)
    if (!r) continue
    const titre = couper(texte(r.name), TITRE_MAX)
    const ingredients = (Array.isArray(r.recipeIngredient) ? r.recipeIngredient : Array.isArray(r.ingredients) ? r.ingredients : [])
      .map(texte)
      .filter(Boolean)
      .slice(0, INGREDIENTS_MAX)
      .map((i) => couper(i, INGREDIENT_MAX))
    const listeEtapes = etapes(r.recipeInstructions).slice(0, ETAPES_MAX).map((e) => couper(e, ETAPE_MAX))
    if (!titre || (ingredients.length === 0 && listeEtapes.length === 0)) continue
    return {
      titre,
      ingredients,
      etapes: listeEtapes,
      portions: portions(r.recipeYield),
      minutes: minutesIso(r.totalTime) ?? minutesIso(r.prepTime),
      source,
    }
  }
  return null
}
