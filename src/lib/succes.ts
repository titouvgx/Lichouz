// Succès / trophées (v2.7.0, migration 32). Les COMPTEURS et l'obtention sont
// calculés par la base (achievement_progress / refresh_my_achievements) ; ici,
// seulement les textes, les raretés et les points. Seuils = achievement_tiers()
// de la migration (test qui compare).

import type { IconName } from '../components/Icon.svelte'

export type Rarity = 'commun' | 'rare' | 'epique' | 'legendaire'

export const RARITY_LABEL: Record<Rarity, string> = {
  commun: 'Commun',
  rare: 'Rare',
  epique: 'Épique',
  legendaire: 'Légendaire',
}

/** Points de niveau par rareté */
export const RARITY_POINTS: Record<Rarity, number> = { commun: 10, rare: 25, epique: 50, legendaire: 100 }

/** Évolutifs : bronze = commun, argent = rare, or = épique */
export const TIER_RARITY: readonly Rarity[] = ['commun', 'rare', 'epique']
export const TIER_LABEL = ['Bronze', 'Argent', 'Or'] as const

export interface Achievement {
  key: string
  name: string
  /** Ce qu'il faut faire (pour un secret : montré seulement une fois obtenu) */
  desc: string
  /** Unité du compteur, pour la barre de progression (« repas », « min »…) */
  unit?: string
  tiers: readonly number[]
  secret?: boolean
  /** Rareté d'un secret (les évolutifs suivent TIER_RARITY) */
  rarity?: Rarity
  /** Icône dans la médaille (Icon.svelte) */
  icon: IconName
}

export const ACHIEVEMENTS: readonly Achievement[] = [
  // ── Évolutifs ──
  { key: 'chef', name: 'Chef du foyer', desc: 'Cuisiner des repas (« Qui cuisine ? » = toi)', unit: 'repas', tiers: [10, 50, 200], icon: 'chef' },
  { key: 'plume', name: 'Plume en cuisine', desc: 'Créer des recettes', unit: 'recettes', tiers: [1, 10, 30], icon: 'pencil' },
  { key: 'critique', name: 'Critique gastronomique', desc: 'Donner des étoiles aux recettes', unit: 'notes', tiers: [10, 50, 150], icon: 'star' },
  { key: 'pipelette', name: 'Pipelette', desc: 'Écrire des commentaires', unit: 'commentaires', tiers: [5, 25, 100], icon: 'mail' },
  { key: 'chariot', name: 'Roi du chariot', desc: 'Cocher des articles pendant les courses', unit: 'articles', tiers: [50, 300, 1000], icon: 'cart' },
  { key: 'globe', name: 'Globe-trotteur', desc: 'Cuisiner des recettes d’origines différentes', unit: 'origines', tiers: [5, 12, 25], icon: 'tag' },
  { key: 'toque', name: 'Toque d’or', desc: 'Passer du temps en mode « En cuisine »', unit: 'min', tiers: [120, 600, 3000], icon: 'clock' },
  { key: 'planificateur', name: 'Planificateur', desc: 'Semaines du foyer avec au moins 5 repas prévus', unit: 'semaines', tiers: [4, 12, 40], icon: 'calendar' },
  { key: 'regulier', name: 'Régulier', desc: 'Semaines d’affilée où tu as cuisiné au moins une fois', unit: 'semaines', tiers: [2, 4, 10], icon: 'refresh' },
  { key: 'explorateur', name: 'Explorateur du catalogue', desc: 'Cuisiner des recettes différentes du catalogue', unit: 'recettes', tiers: [5, 20, 50], icon: 'book' },
  { key: 'fetes', name: 'Maître des fêtes', desc: 'Créer des événements', unit: 'événements', tiers: [1, 5, 15], icon: 'flame' },
  { key: 'anti_gaspi', name: 'Anti-gaspi', desc: 'Prévoir des restes de tes plats', unit: 'restes', tiers: [3, 15, 50], icon: 'plate' },
  { key: 'touche', name: 'Touche-à-tout', desc: 'Cuisiner des catégories de plats différentes', unit: 'catégories', tiers: [4, 6, 8], icon: 'list' },
  { key: 'photographe', name: 'Photographe', desc: 'Ajouter une photo à tes recettes', unit: 'photos', tiers: [1, 10, 30], icon: 'camera' },
  { key: 'ambassadeur', name: 'Ambassadeur', desc: 'Faire entrer quelqu’un avec ton lien d’invitation', unit: 'invitations', tiers: [1, 3, 10], icon: 'link' },
  { key: 'benevole', name: 'Bénévole', desc: 'Prendre des tâches dans les événements', unit: 'tâches', tiers: [3, 10, 30], icon: 'user-plus' },
  { key: 'partant', name: 'Toujours partant', desc: 'Répondre « oui » aux événements', unit: 'oui', tiers: [3, 10, 25], icon: 'check-circle' },
  { key: 'accro', name: 'Accro au booster', desc: 'Ouvrir des boosters', unit: 'boosters', tiers: [7, 30, 100], icon: 'image' },
  { key: 'collectionneur', name: 'Collectionneur', desc: 'Obtenir des cartes différentes dans les boosters', unit: 'cartes', tiers: [10, 50, 150], icon: 'archive' },
  // ── Secrets ──
  { key: 'gros_panier', name: 'Gros panier', desc: 'Une liste de courses de plus de 100 articles', tiers: [101], secret: true, rarity: 'epique', icon: 'cart' },
  { key: 'exotique', name: 'Semaine exotique', desc: '7 jours d’affilée, 7 plats tous différents', tiers: [1], secret: true, rarity: 'epique', icon: 'sun' },
  { key: 'flemmard', name: 'Flemmard', desc: 'La même recette 4 fois dans la même semaine', tiers: [1], secret: true, rarity: 'rare', icon: 'moon' },
  { key: 'cocktail', name: 'Cocktail master', desc: 'Toutes les recettes Cocktail du catalogue', tiers: [1], secret: true, rarity: 'legendaire', icon: 'star' },
  { key: 'brise_glace', name: 'Brise-glace', desc: 'Le tout premier commentaire d’une recette', tiers: [1], secret: true, rarity: 'commun', icon: 'mail' },
  { key: 'coup_coeur', name: 'Coup de cœur', desc: 'Une de tes recettes reçoit 5 notes de 4 étoiles ou plus', tiers: [5], secret: true, rarity: 'legendaire', icon: 'heart' },
  { key: 'reveillon', name: 'Réveillon', desc: 'Cuisiner un 24 ou un 31 décembre', tiers: [1], secret: true, rarity: 'rare', icon: 'flame' },
  { key: 'fait_maison', name: 'Fait maison', desc: 'Cuisiner une recette que tu as créée', tiers: [1], secret: true, rarity: 'commun', icon: 'home' },
  { key: 'double_service', name: 'Double service', desc: 'Cuisiner le midi et le soir le même jour', tiers: [1], secret: true, rarity: 'commun', icon: 'plate' },
  { key: 'gouteur', name: 'Le goûteur', desc: 'Noter 5 recettes le même jour', tiers: [1], secret: true, rarity: 'commun', icon: 'star' },
  { key: 'curieux', name: 'Curieux', desc: 'Cuisiner une recette d’un autre foyer la semaine de sa création', tiers: [1], secret: true, rarity: 'commun', icon: 'eye' },
  { key: 'presse', name: 'Pressé', desc: '3 recettes de 20 min max dans la même semaine', tiers: [1], secret: true, rarity: 'commun', icon: 'clock' },
  { key: 'repas_complet', name: 'Repas complet', desc: 'Entrée, plat et dessert du même repas, tous par toi', tiers: [1], secret: true, rarity: 'rare', icon: 'chef' },
  { key: 'tour_france', name: 'Tour de France', desc: 'Cuisiner 5 régions françaises différentes', tiers: [5], secret: true, rarity: 'rare', icon: 'tag' },
  { key: 'retour_sources', name: 'Retour aux sources', desc: 'Recuisiner une recette oubliée depuis plus de 6 mois', tiers: [1], secret: true, rarity: 'rare', icon: 'refresh' },
  { key: 'grand_chef', name: 'Grand chef', desc: '3 recettes de plus de 90 min de préparation', tiers: [3], secret: true, rarity: 'rare', icon: 'chef' },
  { key: 'marathon', name: 'Marathon', desc: 'Cuisiner 7 jours d’affilée', tiers: [7], secret: true, rarity: 'epique', icon: 'flame' },
  { key: 'semaine_verte', name: 'Semaine verte', desc: 'Une semaine d’au moins 5 repas, tous végétariens', tiers: [1], secret: true, rarity: 'epique', icon: 'sun' },
  { key: 'courses_eclair', name: 'Courses éclair', desc: 'Cocher une liste de 20 articles ou plus en moins de 15 minutes', tiers: [1], secret: true, rarity: 'epique', icon: 'cart' },
  { key: 'grande_tablee', name: 'Grande tablée', desc: 'Un événement que tu as créé reçoit 10 « oui »', tiers: [10], secret: true, rarity: 'epique', icon: 'users' },
  { key: 'vieux', name: 'Vieux de la vieille', desc: 'Un an sur Lichouz', tiers: [1], secret: true, rarity: 'legendaire', icon: 'shield' },
]

export const BY_KEY = new Map(ACHIEVEMENTS.map((a) => [a.key, a]))

/** Rareté d'un palier obtenu */
export function rarityOf(a: Achievement, tier: number): Rarity {
  return a.secret ? (a.rarity ?? 'commun') : TIER_RARITY[Math.max(0, Math.min(2, tier - 1))]
}

export function pointsOf(a: Achievement, tier: number): number {
  return RARITY_POINTS[rarityOf(a, tier)]
}

export interface Unlocked {
  achievement: string
  tier: number
  unlocked_at: string
}

/** Total des points des paliers obtenus (les clés inconnues sont ignorées) */
export function totalPoints(unlocked: readonly Pick<Unlocked, 'achievement' | 'tier'>[]): number {
  return unlocked.reduce((sum, u) => {
    const a = BY_KEY.get(u.achievement)
    return a ? sum + pointsOf(a, u.tier) : sum
  }, 0)
}

/** Points nécessaires pour atteindre le niveau n (1 → 0, 2 → 50, 3 → 150, 4 → 300…) */
export function levelThreshold(n: number): number {
  return 25 * n * (n - 1)
}

export function levelOf(points: number): { level: number; current: number; next: number } {
  let level = 1
  while (levelThreshold(level + 1) <= points) level++
  return { level, current: levelThreshold(level), next: levelThreshold(level + 1) }
}

/** Points possibles au total (tous les paliers) */
export const MAX_POINTS = ACHIEVEMENTS.reduce(
  (s, a) => s + a.tiers.reduce((t, _, i) => t + pointsOf(a, i + 1), 0),
  0,
)

/** Plus haut palier obtenu pour chaque trophée */
export function bestTiers(unlocked: readonly Pick<Unlocked, 'achievement' | 'tier'>[]): Map<string, number> {
  const m = new Map<string, number>()
  for (const u of unlocked) m.set(u.achievement, Math.max(m.get(u.achievement) ?? 0, u.tier))
  return m
}

/** Texte du toast : « Chef du foyer — Argent » ou « Flemmard » */
export function unlockTitle(a: Achievement, tier: number): string {
  return a.secret ? a.name : `${a.name} — ${TIER_LABEL[tier - 1] ?? ''}`
}
