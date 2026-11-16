// Minuteurs du mode « En cuisine » (v1.99.0) : durées repérées dans le texte des étapes.
import { describe, expect, it } from 'vitest'
import { clockLabel, durationLabel, findDurations } from '../../src/lib/timers'

const secs = (t: string) => findDurations(t).map((d) => d.seconds)

describe('findDurations', () => {
  it('minutes', () => {
    expect(secs('Cuire 25 min à 180 °C.')).toEqual([1500])
    expect(secs('Laisser reposer 10 minutes.')).toEqual([600])
    expect(secs('Faire revenir 5 mn')).toEqual([300])
  })
  it('heures, heures et minutes, demi-heure', () => {
    expect(secs('Cuire 1 h à feu doux')).toEqual([3600])
    expect(secs('Mijoter 2 heures')).toEqual([7200])
    expect(secs('Cuire 1 h 30 au four')).toEqual([5400])
    expect(secs('Cuire 1h30')).toEqual([5400])
    expect(secs('Cuire 1 h 15 min')).toEqual([4500])
    expect(secs('Laisser lever 1 heure et demie')).toEqual([5400])
    expect(secs('Compter 1,5 h')).toEqual([5400])
  })
  it('secondes', () => {
    expect(secs('Mixer 30 secondes')).toEqual([30])
    expect(secs('Chauffer 45 s au micro-ondes')).toEqual([45])
  })
  it('une fourchette donne la durée la plus longue', () => {
    expect(secs('Cuire 10 à 15 min')).toEqual([900])
    expect(secs('Cuire 10-12 minutes')).toEqual([720])
  })
  it('plusieurs durées, dans l’ordre, sans doublon, 3 au plus', () => {
    expect(secs('Cuire 10 min, retourner, encore 10 min puis 5 min, puis 2 min')).toEqual([600, 300, 120])
  })
  it('ne prend pas les températures, quantités ou mots qui commencent pareil', () => {
    expect(secs('Préchauffer le four à 200 °C, ajouter 200 g de farine')).toEqual([])
    expect(secs('Ajouter 3 minces tranches et 2 hachis')).toEqual([])
    expect(secs('Prévoir 4 heureux convives')).toEqual([])
    expect(secs('Ajouter 2 s')).toEqual([]) // moins de 5 s : pas de minuteur
  })
})

describe('libellés', () => {
  it('durationLabel', () => {
    expect(durationLabel(1500)).toBe('25 min')
    expect(durationLabel(5400)).toBe('1 h 30')
    expect(durationLabel(3600)).toBe('1 h')
    expect(durationLabel(45)).toBe('45 s')
    expect(durationLabel(90)).toBe('1 min 30')
  })
  it('clockLabel', () => {
    expect(clockLabel(545)).toBe('9:05')
    expect(clockLabel(3750)).toBe('1:02:30')
    expect(clockLabel(0.2)).toBe('0:01')
    expect(clockLabel(-3)).toBe('0:00')
  })
})
