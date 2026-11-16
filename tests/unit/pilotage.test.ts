import { describe, it, expect, vi } from 'vitest'

// errorReport importe supabase et auth (runes) : on les remplace, seul le calcul pur est testé.
vi.mock('../../src/lib/supabase', () => ({ supabase: null }))
vi.mock('../../src/lib/auth.svelte', () => ({ auth: { user: null } }))
vi.mock('../../src/lib/version', () => ({ APP_VERSION: '1.6.0' }))

const { sanitizeErrorText, routeName, isNoise, messageOf } = await import('../../src/lib/errorReport')
const { shouldShowNews } = await import('../../src/lib/nouveautes')

describe('journal des erreurs : rien de personnel ne part', () => {
  it('masque e-mails, jetons JWT et paramètres sensibles', () => {
    const t = sanitizeErrorText(
      'Échec pour titouan.v@example.com avec eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxIn0.abc sur https://x.supabase.co/rest/v1/a?token_hash=SECRET123&x=1',
      500,
    )
    expect(t).not.toMatch(/example\.com|eyJ|SECRET123/)
    expect(t).toContain('[e-mail]')
    expect(t).toContain('[jeton]')
  })
  it('masque le jeton d\'une page d\'invitation et les longs jetons, garde les identifiants de recette', () => {
    const jeton = 'Zx9_kLmN0pQrStUvWxYz1234567890abcdEFGH'
    expect(sanitizeErrorText(`at #/rejoindre/${jeton}`, 500)).toBe('at #/rejoindre/[jeton]')
    expect(sanitizeErrorText(`clé ${jeton}`, 500)).toBe('clé [jeton]')
    const uuid = 'a0000000-0000-4000-8000-000000000071'
    expect(sanitizeErrorText(`recette ${uuid}`, 500)).toBe(`recette ${uuid}`)
  })
  it('n\'envoie jamais les détails d\'une erreur de la base (contenu de la ligne refusée)', () => {
    const pg = { code: '23514', message: 'violates check constraint', details: 'Failing row contains (Tarte secrète de mamie)', hint: null }
    expect(messageOf(pg).message).toBe('23514: violates check constraint')
    expect(JSON.stringify(messageOf(pg))).not.toContain('mamie')
    expect(messageOf({ details: 'secret' }).message).toBe('Erreur sans message')
    const e = Object.assign(new Error('boum'), { code: 'PGRST116', details: 'secret' })
    expect(messageOf(e).message).toBe('Error PGRST116: boum')
  })
  it('coupe à la longueur maximale', () => {
    expect(sanitizeErrorText('mot '.repeat(300), 500)).toHaveLength(500)
  })
  it('ne garde que le nom de la page', () => {
    expect(routeName('#/rejoindre/Zx9_kLmN0pQrStUvWxYz1234567890')).toBe('rejoindre')
    expect(routeName('#/recette/abc')).toBe('recette')
    expect(routeName('')).toBe('accueil')
    expect(routeName('#/courses?x=1')).toBe('courses')
  })
  it('ignore le bruit (réseau coupé, extensions, annulations)', () => {
    for (const m of ['Script error.', 'TypeError: Failed to fetch', 'TypeError: Load failed', 'AbortError: The user aborted', 'ResizeObserver loop limit exceeded']) {
      expect(isNoise(m), m).toBe(true)
    }
    expect(isNoise('TypeError: x is undefined')).toBe(false)
  })
})

describe('Nouveautés : une fois par version, jamais pour une première ouverture', () => {
  const notes = [{ version: '1.6.0', date: '2026-11-16', items: ['x'] }]
  it('personne habituée qui n\'a pas vu cette version : oui', () => {
    expect(shouldShowNews({ version: '1.6.0', lastSeen: '1.5.0', welcomeDone: false, notes })).toBe(true)
    expect(shouldShowNews({ version: '1.6.0', lastSeen: null, welcomeDone: true, notes })).toBe(true)
  })
  it('déjà vue, ou première ouverture (bienvenue pas finie, rien vu) : non', () => {
    expect(shouldShowNews({ version: '1.6.0', lastSeen: '1.6.0', welcomeDone: true, notes })).toBe(false)
    expect(shouldShowNews({ version: '1.6.0', lastSeen: null, welcomeDone: false, notes })).toBe(false)
  })
  it('version sans note (correctif invisible) : non', () => {
    expect(shouldShowNews({ version: '1.6.1', lastSeen: '1.6.0', welcomeDone: true, notes })).toBe(false)
  })
})
