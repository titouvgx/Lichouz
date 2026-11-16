// Minuteurs du mode « En cuisine » (v1.99.0, lot V1-4).
// On repère les durées écrites dans le texte d'une étape (« cuire 25 min »,
// « 1 h 30 », « laisser reposer 2 heures », « 30 secondes ») pour proposer
// un bouton « Minuteur ». Une fourchette (« 10 à 15 min ») donne la plus longue.

export interface FoundDuration {
  /** Durée en secondes */
  seconds: number
  /** Libellé court pour le bouton : « 25 min », « 1 h 30 », « 45 s » */
  label: string
}

const MAX_SECONDS = 24 * 3600

/** Libellé court d'une durée en secondes. */
export function durationLabel(total: number): string {
  const h = Math.floor(total / 3600)
  const m = Math.floor((total % 3600) / 60)
  const s = total % 60
  if (h > 0) return m > 0 ? `${h} h ${String(m).padStart(2, '0')}` : `${h} h`
  if (m > 0) return s > 0 ? `${m} min ${String(s).padStart(2, '0')}` : `${m} min`
  return `${s} s`
}

/** Affichage du temps restant : « 9:05 » ou « 1:02:30 ». */
export function clockLabel(total: number): string {
  const t = Math.max(0, Math.ceil(total))
  const h = Math.floor(t / 3600)
  const m = Math.floor((t % 3600) / 60)
  const s = t % 60
  const ss = String(s).padStart(2, '0')
  return h > 0 ? `${h}:${String(m).padStart(2, '0')}:${ss}` : `${m}:${ss}`
}

const num = (v: string) => Number(v.replace(',', '.'))

// « 1 h 30 », « 1h30 », « 2 heures », « 1 heure et demie », « 1,5 h »
const HOURS = /(\d+(?:[.,]\d+)?)\s*(?:h|heures?)(?:\s*(?:et\s+)?(demie?|\d{1,2}(?!\d))(?!\s*(?:min|mn|s\b|sec)))?(?![a-zà-ÿ])/gi
// « 10 min », « 10 minutes », « 10 à 15 min », « 10-15 mn »
const MINUTES = /(?:(\d+(?:[.,]\d+)?)\s*(?:à|a|-|–|ou)\s*)?(\d+(?:[.,]\d+)?)\s*(?:min(?:utes?)?|mn)(?![a-zà-ÿ])/gi
// « 30 secondes », « 45 s », « 20 sec »
const SECONDS = /(?:(\d+)\s*(?:à|a|-|–|ou)\s*)?(\d+)\s*(?:s|sec(?:ondes?)?)(?![a-zà-ÿ])/gi

/** Durées trouvées dans un texte, dans l'ordre, sans doublon. */
export function findDurations(text: string): FoundDuration[] {
  const found: { at: number; seconds: number }[] = []
  const used: [number, number][] = []
  const free = (a: number, b: number) => used.every(([x, y]) => b <= x || a >= y)

  for (const m of text.matchAll(HOURS)) {
    const at = m.index ?? 0
    let seconds = num(m[1]) * 3600
    if (m[2]) seconds += /^demie?$/i.test(m[2]) ? 1800 : Number(m[2]) * 60
    // « 1 h 30 min » : la partie minutes suit
    const rest = text.slice(at + m[0].length).match(/^\s*(\d{1,2})\s*(?:min(?:utes?)?|mn)(?![a-zà-ÿ])/i)
    let end = at + m[0].length
    if (!m[2] && rest) {
      seconds += Number(rest[1]) * 60
      end += rest[0].length
    }
    used.push([at, end])
    found.push({ at, seconds })
  }
  for (const m of text.matchAll(MINUTES)) {
    const at = m.index ?? 0
    if (!free(at, at + m[0].length)) continue
    const a = m[1] ? num(m[1]) : 0
    const b = num(m[2])
    used.push([at, at + m[0].length])
    found.push({ at, seconds: Math.max(a, b) * 60 })
  }
  for (const m of text.matchAll(SECONDS)) {
    const at = m.index ?? 0
    if (!free(at, at + m[0].length)) continue
    const a = m[1] ? Number(m[1]) : 0
    const b = Number(m[2])
    used.push([at, at + m[0].length])
    found.push({ at, seconds: Math.max(a, b) })
  }

  const out: FoundDuration[] = []
  for (const f of found.sort((x, y) => x.at - y.at)) {
    const seconds = Math.round(f.seconds)
    if (seconds < 5 || seconds > MAX_SECONDS) continue
    if (out.some((o) => o.seconds === seconds)) continue
    out.push({ seconds, label: durationLabel(seconds) })
  }
  return out.slice(0, 3)
}
