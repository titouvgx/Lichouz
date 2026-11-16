// Filtres de l'écran Recettes gardés pendant la session (v1.8.0), et ouverture
// de Recettes avec un seul filtre depuis une étiquette de la fiche (v1.99.0).

import { NO_FILTERS, filtersFor, sanitizeFilters, type TagFilters, type TagRef } from './etiquettes'

export type { TagRef }
import { navigate } from './router.svelte'

export const FILTERS_KEY = 'lichouz:filtres-recettes'

export function loadRecipeFilters(): TagFilters {
  try {
    return sanitizeFilters(JSON.parse(sessionStorage.getItem(FILTERS_KEY) ?? 'null'))
  } catch {
    return { ...NO_FILTERS }
  }
}

export function saveRecipeFilters(f: TagFilters): void {
  try { sessionStorage.setItem(FILTERS_KEY, JSON.stringify(f)) } catch { /* stockage indisponible : tant pis */ }
}

/** Ouvre Recettes filtré sur cette seule étiquette. */
export function openRecipesWithTag(tag: TagRef): void {
  saveRecipeFilters(filtersFor(tag))
  navigate('recettes')
}
