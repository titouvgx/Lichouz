// Boosters à thème (v2.5.0) : petits plus à côté du booster du jour.
// Chaque thème s'ouvre une fois par jour (sur ce téléphone), avec le même
// tirage que le booster du jour (foyer + date + thème, recettes récentes
// écartées, mieux notées favorisées). Un thème n'apparaît que s'il a au
// moins MIN_CANDIDATES recettes. Tout vient des étiquettes : aucune migration.
import { ORIGINES } from './etiquettes'
import type { RecipeIndexEntry } from './api/recipes'

/** Dessins disponibles pour les paquets (voir BoosterArt.svelte) */
export type BoosterArtKey = 'jour' | 'express' | 'budget' | 'monde' | 'vert' | 'reconfort' | 'enfants' | 'fetes'

export interface BoosterTheme {
  key: string
  /** Nom écrit en grand sur le paquet */
  name: string
  /** Petite phrase sous le nom */
  sub: string
  art: BoosterArtKey
  /** Couleur du paquet : variable CSS de app.css */
  tone: string
  match: (r: RecipeIndexEntry) => boolean
  /** Une seule recette par origine (Tour du monde) */
  distinctOrigin?: boolean
  /** Visible seulement à certaines dates */
  season?: (d: Date) => boolean
}

export const MIN_CANDIDATES = 3

const MONDE = new Set(ORIGINES.filter((o) => o.groupe === 'Monde').map((o) => o.key))

/** Du 1er décembre au 6 janvier, comme le thème Noël */
export function isFestiveSeason(d: Date): boolean {
  const m = d.getMonth(), day = d.getDate()
  return m === 11 || (m === 0 && day <= 6)
}

export const BOOSTER_THEMES: readonly BoosterTheme[] = [
  {
    key: 'express', name: 'Express', sub: '20 min max', art: 'express', tone: 'var(--cat-entree)',
    match: (r) => r.prep_time_min != null && r.prep_time_min <= 20,
  },
  {
    key: 'budget', name: 'Petit budget', sub: 'Bon et pas cher', art: 'budget', tone: 'var(--cat-accomp)',
    match: (r) => r.budget === 1,
  },
  {
    key: 'monde', name: 'Tour du monde', sub: '5 pays, 5 assiettes', art: 'monde', tone: 'var(--cat-plat)',
    match: (r) => !!r.origin && MONDE.has(r.origin), distinctOrigin: true,
  },
  {
    key: 'vert', name: 'Tout vert', sub: 'Végétarien', art: 'vert', tone: 'var(--cat-accomp)',
    match: (r) => !!r.diets?.some((d) => d === 'vegetarien' || d === 'vegan'),
  },
  {
    key: 'reconfort', name: 'Réconfort', sub: 'Plats doudous', art: 'reconfort', tone: 'var(--cat-dessert)',
    match: (r) => !!r.themes?.some((t) => t === 'reconfort' || t === 'hiver'),
  },
  {
    key: 'enfants', name: 'Les petits', sub: 'Les enfants adorent', art: 'enfants', tone: 'var(--cat-dessert)',
    match: (r) => !!r.themes?.includes('enfants'),
  },
  {
    key: 'fetes', name: 'Les fêtes', sub: 'Grandes tablées', art: 'fetes', tone: 'var(--accent)',
    match: (r) => !!r.themes?.includes('fetes'), season: isFestiveSeason,
  },
]

/** Thèmes proposés aujourd'hui, avec leurs recettes possibles */
export function availableThemes(
  index: readonly RecipeIndexEntry[],
  today: Date,
  themes: readonly BoosterTheme[] = BOOSTER_THEMES,
): { theme: BoosterTheme; ids: string[] }[] {
  return themes
    .filter((t) => !t.season || t.season(today))
    .map((theme) => {
      const rows = index.filter(theme.match)
      const enough = theme.distinctOrigin
        ? new Set(rows.map((r) => r.origin)).size >= MIN_CANDIDATES
        : rows.length >= MIN_CANDIDATES
      return enough ? { theme, ids: rows.map((r) => r.id) } : null
    })
    .filter((x): x is { theme: BoosterTheme; ids: string[] } => !!x)
}
