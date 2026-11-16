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

const byKey = (list: readonly Etiquette[]) => new Map(list.map((e) => [e.key, e.label]))
const REGIME_LABELS = byKey(REGIMES)
const ORIGINE_LABELS = byKey(ORIGINES)
const THEME_LABELS = byKey(THEMES)

export const regimeLabel = (k: string) => REGIME_LABELS.get(k) ?? k
export const origineLabel = (k: string) => ORIGINE_LABELS.get(k) ?? k
export const themeLabel = (k: string) => THEME_LABELS.get(k) ?? k
export const budgetLabel = (v: number | null | undefined) => BUDGETS.find((b) => b.value === v)?.label ?? ''

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
}

/** Filtres choisis sur l'écran Recettes. */
export interface TagFilters {
  diets: string[] // la recette doit avoir TOUS ces régimes
  origins: string[] // une de ces origines (vide = toutes)
  themes: string[] // au moins un de ces thèmes (vide = tous)
  budgetMax: number | null // budget connu et ≤ (null = tous)
}

export const NO_FILTERS: TagFilters = { diets: [], origins: [], themes: [], budgetMax: null }

export function countFilters(f: TagFilters): number {
  return f.diets.length + f.origins.length + f.themes.length + (f.budgetMax ? 1 : 0)
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
