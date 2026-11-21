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

import { publicationInfo, REFUSAL_REASONS, MAX_PENDING_REQUESTS } from '../../src/lib/publication'

describe('Publication publique : ce que voit l’auteur', () => {
  it('non demandée : on peut publier', () => {
    expect(publicationInfo({ public_status: null, visibility: 'famille' })).toMatchObject({ badge: null, action: 'demander' })
  })
  it('en attente : on peut retirer la demande', () => {
    expect(publicationInfo({ public_status: 'en_attente' })).toMatchObject({ badge: 'En attente de validation', action: 'retirer' })
  })
  it('validée : on peut dépublier', () => {
    expect(publicationInfo({ public_status: 'validee' })).toMatchObject({ badge: 'Publique', action: 'depublier' })
  })
  it('refusée : motif affiché, on peut redemander', () => {
    const i = publicationInfo({ public_status: 'refusee', public_refusal_reason: 'doublon' })
    expect(i.action).toBe('redemander')
    expect(i.note).toContain('Recette en double')
  })
  it('archivée ou catalogue : rien à faire', () => {
    expect(publicationInfo({ public_status: null, archived_at: '2026-11-21T10:00:00Z' }).action).toBeNull()
    expect(publicationInfo({ public_status: null, visibility: 'catalogue' }).action).toBeNull()
  })
  it('motifs et limite : mêmes valeurs que la base', () => {
    expect(REFUSAL_REASONS.map((m) => m.code)).toEqual(['contenu_inapproprie', 'recette_incomplete', 'copie_suspecte', 'photo_inadaptee', 'doublon', 'autre'])
    expect(MAX_PENDING_REQUESTS).toBe(3)
  })
})
