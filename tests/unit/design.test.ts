// Refonte « Brutal beurre » (v1.9.0) : fond animé et couleurs de catégories.
import { describe, expect, it } from 'vitest'
import { makeRain, FOOD_MOTIFS } from '../../src/lib/motifs'
import { categoryColor, NEUTRAL_CATEGORY_COLOR } from '../../src/lib/categoryColors'

/** Générateur pseudo-aléatoire reproductible */
function seeded(seed: number) {
  return () => {
    seed = (seed * 1664525 + 1013904223) % 4294967296
    return seed / 4294967296
  }
}

function contrast(hexA: string, hexB: string): number {
  const lum = (hex: string) => {
    const c = [1, 3, 5].map((i) => parseInt(hex.slice(i, i + 2), 16) / 255)
      .map((x) => (x <= 0.03928 ? x / 12.92 : ((x + 0.055) / 1.055) ** 2.4))
    return 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2]
  }
  const [a, b] = [lum(hexA), lum(hexB)].sort((x, y) => y - x)
  return (a + 0.05) / (b + 0.05)
}

describe('pluie lente (makeRain)', () => {
  const rain = makeRain(12, seeded(42))

  it('tire le nombre demandé d’aliments, tous dessinés', () => {
    expect(rain).toHaveLength(12)
    for (const it of rain) expect(FOOD_MOTIFS).toContain(it.motif)
  })

  it('garde chaque aliment dans son couloir : jamais deux au même endroit', () => {
    const lane = 100 / 12
    rain.forEach((it, i) => {
      expect(it.x).toBeGreaterThanOrEqual(i * lane)
      expect(it.x).toBeLessThan((i + 1) * lane)
    })
  })

  it('reste lent et déjà en cours au démarrage', () => {
    for (const it of rain) {
      expect(it.duration).toBeGreaterThanOrEqual(18)
      expect(it.duration).toBeLessThanOrEqual(32)
      expect(it.delay).toBeLessThanOrEqual(0)
      expect(-it.delay).toBeLessThanOrEqual(it.duration)
      expect(it.y).toBeGreaterThanOrEqual(0)
      expect(it.y).toBeLessThanOrEqual(100)
    }
  })

  it('ne contient que des dessins au trait (aucun script, aucun lien)', () => {
    for (const m of FOOD_MOTIFS) {
      expect(m).not.toMatch(/script|href|on[a-z]+=|url\(/i)
      expect(m).toMatch(/^<(path|circle|ellipse)/)
    }
  })
})

describe('couleurs des catégories', () => {
  it('reconnaît les catégories de la base, quelle que soit la casse', () => {
    for (const name of ['Entrée', 'Plat', 'Accompagnement', 'Dessert', 'Apéritif', 'Sauce', 'Petit-déj & goûter', 'Boisson & cocktail', 'Boissons']) {
      expect(categoryColor(name)).not.toBe(NEUTRAL_CATEGORY_COLOR)
      expect(categoryColor(name.toUpperCase())).toBe(categoryColor(name))
    }
  })

  it('couleur neutre pour une catégorie absente ou inconnue', () => {
    expect(categoryColor(null)).toBe(NEUTRAL_CATEGORY_COLOR)
    expect(categoryColor('Inconnue')).toBe(NEUTRAL_CATEGORY_COLOR)
  })

  it('texte noir lisible sur chaque aplat (contraste ≥ 7:1)', () => {
    for (const name of ['Entrée', 'Plat', 'Accompagnement', 'Dessert', 'Apéritif', 'Sauce', 'Petit-déj & goûter', 'Boisson & cocktail', 'x']) {
      expect(contrast('#1A1A1A', categoryColor(name))).toBeGreaterThanOrEqual(7)
    }
  })
})
