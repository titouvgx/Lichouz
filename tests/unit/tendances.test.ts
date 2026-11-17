import { describe, it, expect } from 'vitest'
import { rankByStars, countCooked, slotDate } from '../../src/lib/tendances'

describe('Tendances : classement par étoiles', () => {
  const recipes = [
    { id: 'a', title: 'Tarte' },
    { id: 'b', title: 'Gratin' },
    { id: 'c', title: 'Soupe' },
    { id: 'd', title: 'Crêpes' },
  ]
  const stats = new Map([
    ['a', { average: 4.5, votes: 2 }],
    ['b', { average: 5, votes: 1 }],
    ['c', { average: 5, votes: 3 }],
  ])
  it('moyenne, puis nombre de votes ; sans vote = absent', () => {
    expect(rankByStars(recipes, stats, 25).map((r) => r.id)).toEqual(['c', 'b', 'a'])
  })
  it('respecte la limite', () => {
    expect(rankByStars(recipes, stats, 2)).toHaveLength(2)
  })
  it('à égalité parfaite : ordre du titre', () => {
    const s = new Map([['a', { average: 4, votes: 2 }], ['b', { average: 4, votes: 2 }]])
    expect(rankByStars(recipes, s, 5).map((r) => r.id)).toEqual(['b', 'a'])
  })
})

describe('Tendances : plus cuisinées du mois', () => {
  it('date du créneau = lundi + jour', () => {
    expect(slotDate('2026-10-26', 6)).toBe('2026-11-01')
  })
  it('compte le mois en cours jusqu’à aujourd’hui, sans les restes', () => {
    const today = new Date(2026, 10, 17) // 17 novembre 2026
    const slots = [
      { week_start: '2026-10-26', day_of_week: 5, recipe_id: 'x' }, // 31 oct : hors mois
      { week_start: '2026-10-26', day_of_week: 6, recipe_id: 'x' }, // 1er nov
      { week_start: '2026-11-16', day_of_week: 1, recipe_id: 'x' }, // 17 nov : aujourd'hui
      { week_start: '2026-11-16', day_of_week: 2, recipe_id: 'y' }, // 18 nov : futur
      { week_start: '2026-11-09', day_of_week: 0, recipe_id: 'y' },
      { week_start: '2026-11-09', day_of_week: 1, recipe_id: 'y', leftover_of: 's1' }, // reste
    ]
    expect(countCooked(slots, today, 10)).toEqual([
      { recipeId: 'x', count: 2 },
      { recipeId: 'y', count: 1 },
    ])
  })
})
