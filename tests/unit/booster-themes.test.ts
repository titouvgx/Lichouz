import { describe, it, expect } from 'vitest'
import { availableThemes, isFestiveSeason, BOOSTER_THEMES } from '../../src/lib/boosterThemes'
import { pickBooster } from '../../src/lib/booster'
import { ORIGINES } from '../../src/lib/etiquettes'

const r = (id: string, extra: Record<string, unknown> = {}) =>
  ({ id, title: id, category_id: null, key: id, diets: [], themes: [], origin: null, budget: null, prep_time_min: null, ...extra }) as any

describe('Boosters à thème', () => {
  it('un thème n’apparaît qu’avec au moins 3 recettes', () => {
    const index = [r('a', { budget: 1 }), r('b', { budget: 1 }), r('c', { prep_time_min: 15 }), r('d', { prep_time_min: 20 }), r('e', { prep_time_min: 10 })]
    const keys = availableThemes(index, new Date(2026, 10, 17)).map((t) => t.theme.key)
    expect(keys).toEqual(['express'])
  })
  it('Tour du monde : il faut 3 origines différentes', () => {
    const same = [r('a', { origin: 'italie' }), r('b', { origin: 'italie' }), r('c', { origin: 'italie' })]
    expect(availableThemes(same, new Date(2026, 10, 17)).length).toBe(0)
    const mix = [...same, r('d', { origin: 'japon' }), r('e', { origin: 'inde' }), r('f', { origin: 'france' })]
    const monde = availableThemes(mix, new Date(2026, 10, 17)).find((t) => t.theme.key === 'monde')!
    expect(monde.ids).not.toContain('f') // la France n'est pas « Monde »
  })
  it('Les fêtes : seulement du 1er décembre au 6 janvier', () => {
    expect(isFestiveSeason(new Date(2026, 10, 30))).toBe(false)
    expect(isFestiveSeason(new Date(2026, 11, 1))).toBe(true)
    expect(isFestiveSeason(new Date(2027, 0, 6))).toBe(true)
    expect(isFestiveSeason(new Date(2027, 0, 7))).toBe(false)
  })
  it('un par groupe : jamais deux recettes de la même origine', () => {
    const origin: Record<string, string> = { a: 'it', b: 'it', c: 'jp', d: 'jp', e: 'in', f: 'mx', g: 'mx' }
    const picked = pickBooster(Object.keys(origin), new Set(), new Map(), 5, 's', (id) => origin[id])
    expect(new Set(picked.map((id) => origin[id])).size).toBe(picked.length)
    expect(picked).toHaveLength(4)
  })
  it('chaque thème a un dessin et une couleur en variable CSS', () => {
    for (const t of BOOSTER_THEMES) expect(t.tone).toMatch(/^var\(--/)
    expect(ORIGINES.some((o) => o.groupe === 'Monde')).toBe(true)
  })
})
