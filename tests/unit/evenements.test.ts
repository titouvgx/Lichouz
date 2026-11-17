// Événements (v1.999.0) : modèles, dates, compte à rebours, lien de playlist.
import { describe, expect, it } from 'vitest'
import {
  EVENT_TEMPLATES, cleanPlaylistUrl, countRsvps, countdownLabel, daysUntil, defaultDate, isUpcoming, templateOf,
} from '../../src/lib/evenements'

const d = (iso: string) => new Date(`${iso}T10:00:00`)

describe('modèles', () => {
  it('Noël propose ses pôles, inconnu → Autre', () => {
    expect(templateOf('noel').poles).toContain('Desserts')
    expect(templateOf('pirate').kind).toBe('autre')
    expect(new Set(EVENT_TEMPLATES.map((t) => t.kind)).size).toBe(EVENT_TEMPLATES.length)
  })
  it('date par défaut : 24 décembre à venir', () => {
    expect(defaultDate('noel', d('2026-11-17'))).toBe('2026-12-24')
    expect(defaultDate('noel', d('2026-12-24'))).toBe('2026-12-24')
    expect(defaultDate('noel', d('2026-12-26'))).toBe('2027-12-24')
    expect(defaultDate('fete', d('2026-12-28'))).toBe('2027-01-04')
  })
})

describe('compte à rebours et page éphémère', () => {
  const today = d('2026-12-22')
  it('jours restants', () => {
    expect(daysUntil('2026-12-24', today)).toBe(2)
    expect(daysUntil('2026-12-22', today)).toBe(0)
    expect(countdownLabel('2026-12-23', today)).toBe('C’est demain')
    expect(countdownLabel('2026-12-22', today)).toBe('C’est aujourd’hui !')
    expect(countdownLabel('2026-12-30', today)).toBe('Dans 8 jours')
  })
  it('reste « à venir » jusqu’à 3 jours après', () => {
    expect(isUpcoming('2026-12-19', today)).toBe(true)
    expect(isUpcoming('2026-12-18', today)).toBe(false)
  })
})

describe('playlist et réponses', () => {
  it('https seulement', () => {
    expect(cleanPlaylistUrl('  ')).toBeNull()
    expect(cleanPlaylistUrl(' https://open.spotify.com/playlist/x ')).toBe('https://open.spotify.com/playlist/x')
    expect(cleanPlaylistUrl('http://deezer.com')).toBe('')
    expect(cleanPlaylistUrl('javascript:alert(1)')).toBe('')
  })
  it('compte des réponses', () => {
    expect(countRsvps([{ answer: 'oui' }, { answer: 'oui' }, { answer: 'non' }])).toEqual({ oui: 2, peut_etre: 0, non: 1 })
  })
})
