import { describe, it, expect } from 'vitest'
import { groupMyRecipes } from '../../src/lib/api/recipes'

describe('Mes recettes : rangement', () => {
  it('archivées à part, puis partagées / famille ; le catalogue est ignoré', () => {
    const g = groupMyRecipes([
      { id: 'a', visibility: 'famille', archived_at: null },
      { id: 'b', visibility: 'super_famille', archived_at: null },
      { id: 'c', visibility: 'super_famille', archived_at: '2026-11-16T10:00:00Z' },
      { id: 'd', visibility: 'catalogue', archived_at: null },
      { id: 'e', visibility: 'famille' },
    ] as any)
    expect(g.famille.map((r: any) => r.id)).toEqual(['a', 'e'])
    expect(g.super_famille.map((r: any) => r.id)).toEqual(['b'])
    expect(g.archivee.map((r: any) => r.id)).toEqual(['c'])
  })
})
