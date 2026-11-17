import { describe, it, expect } from 'vitest'
import { pickWeightedSeeded } from '../../src/lib/random'
import { boosterWeight, pickBooster, recentRecipeIds } from '../../src/lib/booster'

const ids = Array.from({ length: 30 }, (_, i) => `r${i}`)

describe('Booster : tirage', () => {
  it('reproductible avec la même graine, différent avec une autre', () => {
    const a = pickBooster(ids, new Set(), new Map(), 5, 'foyer:2026-11-17')
    expect(a).toEqual(pickBooster(ids, new Set(), new Map(), 5, 'foyer:2026-11-17'))
    expect(new Set(a).size).toBe(5)
    expect(a).not.toEqual(pickBooster(ids, new Set(), new Map(), 5, 'foyer:2026-11-18'))
  })
  it('écarte les recettes récentes', () => {
    const recent = new Set(ids.slice(0, 25))
    const a = pickBooster(ids, recent, new Map(), 5, 'x')
    expect(a.sort()).toEqual(ids.slice(25).sort())
  })
  it('complète avec les récentes s’il en manque (jamais à moitié vide)', () => {
    const recent = new Set(ids.slice(0, 28))
    const a = pickBooster(ids, recent, new Map(), 5, 'x')
    expect(a).toHaveLength(5)
    expect(a.slice(0, 2).sort()).toEqual(['r28', 'r29'])
  })
  it('moins de recettes que 5 : toutes', () => {
    expect(pickBooster(['a', 'b'], new Set(), new Map(), 5, 'x').sort()).toEqual(['a', 'b'])
  })
  it('poids : sans vote = 1,5 ; 5 étoiles = 2,5 ; 1 étoile = 0,5', () => {
    expect(boosterWeight(undefined)).toBe(1.5)
    expect(boosterWeight({ average: 5, votes: 2 })).toBe(2.5)
    expect(boosterWeight({ average: 1, votes: 1 })).toBe(0.5)
  })
  it('les mieux notées sortent plus souvent (sur 2000 tirages)', () => {
    const items = ['top', 'bof']
    let top = 0
    for (let d = 0; d < 2000; d++) {
      if (pickWeightedSeeded(items, (x) => (x === 'top' ? 2.5 : 0.5), 1, `j${d}`)[0] === 'top') top++
    }
    expect(top / 2000).toBeGreaterThan(0.75) // attendu ≈ 2,5 / 3 = 83 %
  })
})

describe('Booster : recettes à écarter', () => {
  it('de J-14 à J+7 seulement', () => {
    const today = new Date(2026, 10, 17)
    const set = recentRecipeIds([
      { week_start: '2026-11-02', day_of_week: 0, recipe_id: 'trop-vieux' }, // 2 nov
      { week_start: '2026-11-02', day_of_week: 1, recipe_id: 'j-14' },       // 3 nov
      { week_start: '2026-11-23', day_of_week: 1, recipe_id: 'j+7' },        // 24 nov
      { week_start: '2026-11-23', day_of_week: 2, recipe_id: 'trop-loin' },  // 25 nov
    ], today)
    expect([...set].sort()).toEqual(['j+7', 'j-14'])
  })
})

describe('Booster : tirage mémorisé pour la journée', () => {
  it('relit le tirage du jour, ignore celui de la veille', async () => {
    const store = new Map<string, string>()
    ;(globalThis as any).localStorage = {
      getItem: (k: string) => store.get(k) ?? null,
      setItem: (k: string, v: string) => void store.set(k, v),
    }
    const { readCachedDraw, saveCachedDraw } = await import('../../src/lib/booster')
    saveCachedDraw('u1', 'jour', '2026-11-17', ['a', 'b'])
    expect(readCachedDraw('u1', 'jour', '2026-11-17')).toEqual(['a', 'b'])
    expect(readCachedDraw('u1', 'jour', '2026-11-18')).toBeNull()
    expect(readCachedDraw('u1', 'monde', '2026-11-17')).toBeNull()
    expect(readCachedDraw(null, 'jour', '2026-11-17')).toBeNull()
    store.set('lichouz:booster-tirage:u1:jour', 'pas du json')
    expect(readCachedDraw('u1', 'jour', '2026-11-17')).toBeNull()
  })
})
