// Chats d'erreur (v2.1.0) : le bon dessin pour la bonne erreur.
import { describe, expect, it } from 'vitest'
import { errorMood, isTechnical, MOOD_TEXT } from '../../src/lib/errorMood'

describe('errorMood', () => {
  it.each([
    [new TypeError('Failed to fetch'), 'hors-ligne'],
    [{ code: '42501', message: 'new row violates row-level security policy' }, 'interdit'],
    [{ code: 'PGRST116', message: 'no rows' }, 'introuvable'],
    ['Recette introuvable.', 'introuvable'],
    [{ status: 503, message: 'Service Unavailable' }, 'serveur'],
    [new Error('quelque chose de bizarre'), 'inconnu'],
    [undefined, 'inconnu'],
  ])('%o → %s', (e, mood) => {
    expect(errorMood(e)).toBe(mood)
  })
  it('chaque chat a un titre et un message clairs', () => {
    for (const t of Object.values(MOOD_TEXT)) {
      expect(t.title.length).toBeGreaterThan(3)
      expect(t.message.length).toBeGreaterThan(20)
    }
  })
  it('cache les messages techniques', () => {
    expect(isTechnical('no rows')).toBe(true)
    expect(isTechnical('TypeError: Failed to fetch')).toBe(true)
    expect(isTechnical('Recette introuvable.')).toBe(false)
  })
})
