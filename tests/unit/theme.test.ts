// Thème Classique / Noël (v1.99.3) : période des fêtes et choix de la personne.
import { describe, expect, it } from 'vitest'
import { isHolidaySeason, resolveTheme } from '../../src/lib/theme.svelte'
import { NOEL_MOTIFS, makeRain } from '../../src/lib/motifs'

const d = (iso: string) => new Date(`${iso}T12:00:00`)

describe('période des fêtes (1er décembre → 6 janvier)', () => {
  it('bornes incluses', () => {
    expect(isHolidaySeason(d('2026-11-30'))).toBe(false)
    expect(isHolidaySeason(d('2026-12-01'))).toBe(true)
    expect(isHolidaySeason(d('2026-12-25'))).toBe(true)
    expect(isHolidaySeason(d('2027-01-06'))).toBe(true)
    expect(isHolidaySeason(d('2027-01-07'))).toBe(false)
    expect(isHolidaySeason(d('2027-07-14'))).toBe(false)
  })
})

describe('thème appliqué', () => {
  it('automatique suit la période, le choix de la personne l’emporte', () => {
    expect(resolveTheme('auto', d('2026-12-10'))).toBe('noel')
    expect(resolveTheme('auto', d('2026-11-17'))).toBe('classique')
    expect(resolveTheme('classique', d('2026-12-24'))).toBe('classique')
    expect(resolveTheme('noel', d('2026-06-01'))).toBe('noel')
  })
})

describe('motifs de Noël', () => {
  it('8 dessins distincts, utilisés par la pluie', () => {
    expect(new Set(NOEL_MOTIFS).size).toBe(8)
    const rain = makeRain(12, Math.random, NOEL_MOTIFS)
    for (const it of rain) expect(NOEL_MOTIFS).toContain(it.motif)
  })
})
