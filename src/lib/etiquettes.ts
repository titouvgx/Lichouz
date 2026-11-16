// Étiquettes des recettes (v1.8.0, migration 25) : LISTE FIXE.
//
// Source unique côté appli. La base refuse toute autre valeur (contraintes CHECK de
// la migration 25) ; le test tests/unit/etiquettes.test.ts vérifie que les deux listes
// sont identiques. Ajouter une valeur = l'ajouter ici ET dans une nouvelle migration.
// Pas d'import ici : le script scripts/recettes/generer.ts lit aussi ce fichier.

export interface Etiquette {
  key: string
  label: string
}

export interface Origine extends Etiquette {
  groupe: 'France' | 'Monde'
}

/** Régimes, posés à la main (indicatifs : en cas d'allergie, vérifier les emballages). */
export const REGIMES: readonly Etiquette[] = [
  { key: 'vegetarien', label: 'Végétarien' },
  { key: 'vegan', label: 'Vegan' },
  { key: 'sans_gluten', label: 'Sans gluten' },
  { key: 'sans_lactose', label: 'Sans lactose' },
  { key: 'sans_porc', label: 'Sans porc' },
]

/** Origine : une seule par recette (région de France ou pays / zone du monde). */
export const ORIGINES: readonly Origine[] = [
  { key: 'france', label: 'France (classique)', groupe: 'France' },
  { key: 'alsace', label: 'Alsace', groupe: 'France' },
  { key: 'auvergne', label: 'Auvergne', groupe: 'France' },
  { key: 'bourgogne', label: 'Bourgogne', groupe: 'France' },
  { key: 'bretagne', label: 'Bretagne', groupe: 'France' },
  { key: 'corse', label: 'Corse', groupe: 'France' },
  { key: 'dauphine', label: 'Dauphiné', groupe: 'France' },
  { key: 'limousin', label: 'Limousin', groupe: 'France' },
  { key: 'lorraine', label: 'Lorraine', groupe: 'France' },
  { key: 'lyonnais', label: 'Lyonnais', groupe: 'France' },
  { key: 'nord', label: 'Nord', groupe: 'France' },
  { key: 'normandie', label: 'Normandie', groupe: 'France' },
  { key: 'pays_basque', label: 'Pays basque', groupe: 'France' },
  { key: 'provence', label: 'Provence et Côte d’Azur', groupe: 'France' },
  { key: 'savoie', label: 'Savoie', groupe: 'France' },
  { key: 'sud_ouest', label: 'Sud-Ouest', groupe: 'France' },
  { key: 'antilles', label: 'Antilles et Réunion', groupe: 'France' },
  { key: 'italie', label: 'Italie', groupe: 'Monde' },
  { key: 'espagne', label: 'Espagne', groupe: 'Monde' },
  { key: 'portugal', label: 'Portugal', groupe: 'Monde' },
  { key: 'grece', label: 'Grèce', groupe: 'Monde' },
  { key: 'belgique', label: 'Belgique', groupe: 'Monde' },
  { key: 'royaume_uni', label: 'Royaume-Uni', groupe: 'Monde' },
  { key: 'europe_est', label: 'Europe de l’Est', groupe: 'Monde' },
  { key: 'maghreb', label: 'Maghreb', groupe: 'Monde' },
  { key: 'moyen_orient', label: 'Liban et Moyen-Orient', groupe: 'Monde' },
  { key: 'afrique', label: 'Afrique', groupe: 'Monde' },
  { key: 'inde', label: 'Inde', groupe: 'Monde' },
  { key: 'chine', label: 'Chine', groupe: 'Monde' },
  { key: 'japon', label: 'Japon', groupe: 'Monde' },
  { key: 'coree', label: 'Corée', groupe: 'Monde' },
  { key: 'asie_sud_est', label: 'Thaïlande et Vietnam', groupe: 'Monde' },
  { key: 'etats_unis', label: 'États-Unis', groupe: 'Monde' },
  { key: 'mexique', label: 'Mexique et Tex-Mex', groupe: 'Monde' },
  { key: 'amerique_sud', label: 'Amérique du Sud', groupe: 'Monde' },
]

/** Thèmes : plusieurs par recette. « Films » = clin d'œil, sans image ni logo de film. */
export const THEMES: readonly Etiquette[] = [
  { key: 'films', label: 'Inspirées de films' },
  { key: 'fetes', label: 'Fêtes et grandes tablées' },
  { key: 'etudiant', label: 'Spécial étudiants' },
  { key: 'enfants', label: 'Les enfants adorent' },
  { key: 'reconfort', label: 'Réconfortant' },
  { key: 'leger', label: 'Léger' },
  { key: 'ete', label: 'Été' },
  { key: 'hiver', label: 'Hiver' },
  { key: 'pique_nique', label: 'Pique-nique' },
  { key: 'barbecue', label: 'Barbecue' },
]

/** Budget : 1 = €, 2 = €€, 3 = €€€ (ordre de grandeur, pas un prix). */
export const BUDGETS: readonly { value: 1 | 2 | 3; label: string; long: string }[] = [
  { value: 1, label: '€', long: 'Petit budget' },
  { value: 2, label: '€€', long: 'Budget moyen' },
  { value: 3, label: '€€€', long: 'Pour les grandes occasions' },
]

export const MAX_THEMES = 5

/** Temps de préparation (v1.99.0) : « au plus », en minutes. */
export const TEMPS: readonly { value: number; label: string }[] = [
  { value: 15, label: '15 min' },
  { value: 30, label: '30 min' },
  { value: 45, label: '45 min' },
  { value: 60, label: '1 h' },
]

const byKey = (list: readonly Etiquette[]) => new Map(list.map((e) => [e.key, e.label]))
const REGIME_LABELS = byKey(REGIMES)
const ORIGINE_LABELS = byKey(ORIGINES)
const THEME_LABELS = byKey(THEMES)

export const regimeLabel = (k: string) => REGIME_LABELS.get(k) ?? k
export const origineLabel = (k: string) => ORIGINE_LABELS.get(k) ?? k
export const themeLabel = (k: string) => THEME_LABELS.get(k) ?? k
export const budgetLabel = (v: number | null | undefined) => BUDGETS.find((b) => b.value === v)?.label ?? ''
export const tempsLabel = (v: number | null | undefined) => TEMPS.find((t) => t.value === v)?.label ?? ''

/** Relit des filtres venant d'un stockage (valeurs inconnues ignorées). */
export function sanitizeFilters(f: unknown): TagFilters {
  if (!f || typeof f !== 'object') return { ...NO_FILTERS }
  const o = f as Record<string, unknown>
  const arr = (v: unknown) => (Array.isArray(v) ? v.filter((x): x is string => typeof x === 'string') : [])
  return {
    diets: cleanKeys(arr(o.diets), REGIMES),
    origins: cleanKeys(arr(o.origins), ORIGINES),
    themes: cleanKeys(arr(o.themes), THEMES),
    budgetMax: BUDGETS.some((b) => b.value === o.budgetMax) ? (o.budgetMax as number) : null,
    timeMax: TEMPS.some((t) => t.value === o.timeMax) ? (o.timeMax as number) : null,
  }
}

/** Garde l'ordre de la liste de référence, sans doublon ni valeur inconnue. */
export function cleanKeys(keys: readonly string[], list: readonly Etiquette[]): string[] {
  const set = new Set(keys)
  return list.filter((e) => set.has(e.key)).map((e) => e.key)
}

/** Étiquettes d'une recette (colonnes de la migration 25). */
export interface RecipeTags {
  diets: string[]
  origin: string | null
  themes: string[]
  budget: number | null
  /** Temps de préparation en minutes (colonne d'origine, pas une étiquette) */
  prep_time_min?: number | null
}

/** Filtres choisis sur l'écran Recettes. */
export interface TagFilters {
  diets: string[] // la recette doit avoir TOUS ces régimes
  origins: string[] // une de ces origines (vide = toutes)
  themes: string[] // au moins un de ces thèmes (vide = tous)
  budgetMax: number | null // budget connu et ≤ (null = tous)
  timeMax: number | null // temps de préparation connu et ≤ (null = tous), v1.99.0
}

export const NO_FILTERS: TagFilters = { diets: [], origins: [], themes: [], budgetMax: null, timeMax: null }

export function countFilters(f: TagFilters): number {
  return f.diets.length + f.origins.length + f.themes.length + (f.budgetMax ? 1 : 0) + (f.timeMax ? 1 : 0)
}

export function matchesTags(r: Partial<RecipeTags>, f: TagFilters): boolean {
  const diets = [...(r.diets ?? [])]
  // Vegan ⇒ végétarien (au cas où l'auteur n'a coché que « Vegan »)
  if (diets.includes('vegan') && !diets.includes('vegetarien')) diets.push('vegetarien')
  const themes = r.themes ?? []
  if (!f.diets.every((d) => diets.includes(d))) return false
  if (f.origins.length && (!r.origin || !f.origins.includes(r.origin))) return false
  if (f.themes.length && !f.themes.some((t) => themes.includes(t))) return false
  if (f.budgetMax && (!r.budget || r.budget > f.budgetMax)) return false
  if (f.timeMax && (!r.prep_time_min || r.prep_time_min > f.timeMax)) return false
  return true
}

/** Mots ajoutés à la clé de recherche (on trouve « vegan » ou « bretagne » en tapant). */
export function tagWords(r: Partial<RecipeTags>): string {
  return [
    ...(r.diets ?? []).map(regimeLabel),
    r.origin ? origineLabel(r.origin) : '',
    ...(r.themes ?? []).map(themeLabel),
  ].join(' ')
}

/** Une étiquette touchée sur la fiche. */
export type TagRef =
  | { kind: 'diet'; key: string }
  | { kind: 'origin'; key: string }
  | { kind: 'theme'; key: string }
  | { kind: 'budget'; value: number }

/** Filtres qui ne gardent QUE cette étiquette (les autres filtres sont retirés). */
export function filtersFor(tag: TagRef): TagFilters {
  const f: TagFilters = { ...NO_FILTERS, diets: [], origins: [], themes: [] }
  if (tag.kind === 'diet') f.diets = [tag.key]
  else if (tag.kind === 'origin') f.origins = [tag.key]
  else if (tag.kind === 'theme') f.themes = [tag.key]
  else f.budgetMax = tag.value
  return sanitizeFilters(f)
}
