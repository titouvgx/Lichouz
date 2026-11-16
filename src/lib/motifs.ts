// Dessins au trait des aliments du fond « pluie lente » (AppBackdrop).
// Dessinés pour Lichouz (pas des émojis), dans une grille de 24 × 24,
// trait carré : même esprit que les icônes de l'appli, en plus brut.

export const FOOD_MOTIFS: readonly string[] = [
  // pomme
  '<path d="M12 7c-3-2-8-1-8 5 0 5 3 9 5 9 1 0 2-1 3-1s2 1 3 1c2 0 5-4 5-9 0-6-5-7-8-5z"/><path d="M12 7c0-2 1-4 3-4"/>',
  // poire
  '<path d="M12 4c-2 0-3 2-3 4 0 2-4 4-4 8a7 7 0 0 0 14 0c0-4-4-6-4-8 0-2-1-4-3-4z"/><path d="M12 4V1"/>',
  // carotte
  '<path d="M16 8 3 21l3-10 7-6z"/><path d="M16 8l2-5M16 8l5-2M16 8l4-4"/>',
  // citron
  '<ellipse cx="12" cy="12" rx="8" ry="6" transform="rotate(-30 12 12)"/><path d="M19 6l2-2M5 18l-2 2"/>',
  // cerises
  '<circle cx="7" cy="17" r="3.5"/><circle cx="16" cy="18" r="3.5"/><path d="M7 13.5C8 8 11 5 15 3M16 14.5C16 9 15 6 15 3"/>',
  // champignon
  '<path d="M3 12a9 7 0 0 1 18 0z"/><path d="M9 12v6a3 3 0 0 0 6 0v-6"/>',
  // tomate
  '<circle cx="12" cy="14" r="7"/><path d="M9 7l3 2 3-2M12 9V5"/>',
  // œuf
  '<path d="M12 3c-4 0-7 6-7 11a7 7 0 0 0 14 0c0-5-3-11-7-11z"/>',
  // baguette
  '<path d="M4 18 18 4c2-1 3 0 2 2L6 20c-2 1-3 0-2-2z"/><path d="M9 11l2 2M12 8l2 2M6 14l2 2"/>',
  // poisson
  '<path d="M3 12c4-5 10-5 14 0-4 5-10 5-14 0z"/><path d="M17 12l4-4v8z"/>',
  // fromage
  '<path d="M3 17 21 9v8z"/><path d="M3 17 13 5l8 4"/><circle cx="14" cy="14" r="1"/>',
  // banane
  '<path d="M4 14c4 6 13 5 16-6-3 4-9 6-14 4z"/>',
  // oignon
  '<path d="M12 4c0 3-7 6-7 11a7 6 0 0 0 14 0c0-5-7-8-7-11z"/><path d="M12 21v-3"/>',
]

export interface FallingItem {
  motif: string
  /** position horizontale, en % de la largeur */
  x: number
  /** position verticale quand le mouvement est coupé, en % de la hauteur */
  y: number
  size: number
  /** durée d'une chute complète, en secondes */
  duration: number
  /** décalage de départ (négatif : déjà en cours de chute à l'ouverture) */
  delay: number
  rotStart: number
  rotEnd: number
  accent: boolean
}

/**
 * Tire une pluie d'aliments : un aliment par « couloir » vertical, pour qu'ils
 * restent espacés et ne se chevauchent jamais. `random` est injectable (tests).
 */
export function makeRain(count: number, random: () => number = Math.random): FallingItem[] {
  const items: FallingItem[] = []
  const lane = 100 / count
  // Ordre des motifs mélangé, pour ne pas avoir deux fois le même côte à côte
  const order = FOOD_MOTIFS.map((_, i) => i).sort(() => random() - 0.5)
  for (let i = 0; i < count; i++) {
    const duration = 18 + random() * 14
    items.push({
      motif: FOOD_MOTIFS[order[i % order.length]],
      x: i * lane + random() * (lane * 0.55),
      y: 6 + ((i * 37) % 88) + random() * 4,
      size: Math.round(30 + random() * 16),
      duration: Math.round(duration * 10) / 10,
      delay: -Math.round(random() * duration * 10) / 10,
      rotStart: Math.round(random() * 40 - 20),
      rotEnd: Math.round(random() * 240 - 120),
      accent: random() < 0.2,
    })
  }
  return items
}
