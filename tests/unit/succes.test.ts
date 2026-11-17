import { describe, it, expect } from 'vitest'
import { readFileSync } from 'node:fs'
import { join } from 'node:path'
import { ACHIEVEMENTS, levelOf, levelThreshold, totalPoints, MAX_POINTS, rarityOf, BY_KEY } from '../../src/lib/succes'

const M32 = readFileSync(join(__dirname, '../../supabase/migrations/20261119200000_succes.sql'), 'utf8')
const sqlTiers = JSON.parse(M32.match(/SELECT '(\{[\s\S]*?\})'::jsonb/)![1]) as Record<string, number[]>

describe('Trophées : l’appli et la base disent la même chose', () => {
  it('40 trophées, mêmes clés et mêmes seuils que achievement_tiers()', () => {
    expect(ACHIEVEMENTS).toHaveLength(40)
    expect(Object.keys(sqlTiers)).toHaveLength(40)
    for (const a of ACHIEVEMENTS) expect(sqlTiers[a.key], a.key).toEqual([...a.tiers])
  })
  it('19 évolutifs à 3 paliers, 21 secrets à 1 palier avec une rareté', () => {
    const evo = ACHIEVEMENTS.filter((a) => !a.secret)
    const sec = ACHIEVEMENTS.filter((a) => a.secret)
    expect(evo).toHaveLength(19)
    expect(sec).toHaveLength(21)
    for (const a of evo) expect(a.tiers).toHaveLength(3)
    for (const a of sec) { expect(a.tiers).toHaveLength(1); expect(a.rarity).toBeDefined() }
  })
  it('chaque compteur est calculé par la base', () => {
    for (const a of ACHIEVEMENTS) expect(M32, a.key).toContain(`'${a.key}',`)
  })
})

describe('Trophées : points et niveaux', () => {
  it('raretés : bronze commun, argent rare, or épique ; secrets selon leur rareté', () => {
    const chef = BY_KEY.get('chef')!
    expect([1, 2, 3].map((t) => rarityOf(chef, t))).toEqual(['commun', 'rare', 'epique'])
    expect(rarityOf(BY_KEY.get('vieux')!, 1)).toBe('legendaire')
  })
  it('points : clés inconnues ignorées', () => {
    expect(totalPoints([{ achievement: 'chef', tier: 1 }, { achievement: 'chef', tier: 2 }, { achievement: 'inconnu', tier: 1 }])).toBe(35)
  })
  it('niveaux : 0 → 1, 50 → 2, 149 → 2, 150 → 3', () => {
    expect(levelOf(0).level).toBe(1)
    expect(levelOf(50).level).toBe(2)
    expect(levelOf(149).level).toBe(2)
    expect(levelOf(150).level).toBe(3)
    expect(levelThreshold(4)).toBe(300)
  })
  it('tout obtenir donne un niveau à deux chiffres (environ 10)', () => {
    expect(MAX_POINTS).toBe(2425)
    expect(levelOf(MAX_POINTS).level).toBeGreaterThanOrEqual(9)
  })
})
