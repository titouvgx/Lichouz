// Couleurs des catégories de recettes dans le style « Brutal beurre » (v1.9.0).
// La base garde ses propres couleurs (recipe_categories.color, plus sombres,
// pensées pour l'ancien fond bleu nuit) : l'appli ne les affiche plus.
// Ici, des aplats vifs sur lesquels le texte est TOUJOURS noir (#1A1A1A),
// avec un contraste d'au moins 8:1, en mode clair comme en mode sombre.

const BY_NAME: Record<string, string> = {
  'entrée': '#8EC5FF',
  'plat': '#FFB627',
  'accompagnement': '#7BD389',
  'dessert': '#FF9EC7',
  'apéritif': '#C9A0FF',
  'sauce': '#FF8A65',
  'petit-déj & goûter': '#FFD6A5',
  'boisson & cocktail': '#7FDBDA',
  'boissons': '#7FDBDA',
}

/** Couleur neutre pour une catégorie inconnue ou absente. */
export const NEUTRAL_CATEGORY_COLOR = '#D9D4C7'

/** Aplat de fond pour une catégorie (texte noir dessus). */
export function categoryColor(name: string | null | undefined): string {
  if (!name) return NEUTRAL_CATEGORY_COLOR
  return BY_NAME[name.trim().toLowerCase()] ?? NEUTRAL_CATEGORY_COLOR
}
