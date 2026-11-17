// Événements (v1.999.0, migration 28) : modèles réutilisables et petites aides
// sans base de données (testées dans tests/unit/evenements.test.ts).

export type EventKind = 'noel' | 'anniversaire' | 'fete' | 'autre'
export type EventScope = 'foyer' | 'famille'
export type RsvpAnswer = 'oui' | 'peut_etre' | 'non'

export interface EventTemplate {
  kind: EventKind
  label: string
  /** Icône de l'appli (Icon.svelte) : pas d'émoji hors rayons (règle docs/design.md) */
  icon: 'star' | 'flame' | 'users' | 'calendar'
  title: string
  /** Pôles « qui fait quoi » proposés (on peut en retirer et en ajouter) */
  poles: string[]
}

export const EVENT_TEMPLATES: readonly EventTemplate[] = [
  {
    kind: 'noel',
    label: 'Noël',
    icon: 'star',
    title: 'Fête de Noël',
    poles: ['Apéritif', 'Entrées', 'Plat', 'Fromages', 'Desserts', 'Boissons', 'Décoration', 'Musique'],
  },
  {
    kind: 'anniversaire',
    label: 'Anniversaire',
    icon: 'flame',
    title: 'Anniversaire de ',
    poles: ['Gâteau', 'Boissons', 'Décoration', 'Cadeau commun', 'Jeux'],
  },
  {
    kind: 'fete',
    label: 'Fête',
    icon: 'users',
    title: 'Fête',
    poles: ['Apéritif', 'Plats', 'Desserts', 'Boissons'],
  },
  { kind: 'autre', label: 'Autre', icon: 'calendar', title: '', poles: [] },
]

export const templateOf = (k: string): EventTemplate =>
  EVENT_TEMPLATES.find((t) => t.kind === k) ?? EVENT_TEMPLATES[EVENT_TEMPLATES.length - 1]

export const RSVP_LABELS: Record<RsvpAnswer, string> = { oui: 'Je viens', peut_etre: 'Peut-être', non: 'Je ne viens pas' }

export const LIMITS = { title: 80, location: 80, theme: 80, notes: 1000, playlist: 300, task: 60, tasks: 30 }

/** Date ISO (AAAA-MM-JJ) locale, sans décalage de fuseau. */
export function isoDay(d: Date): string {
  const p = (n: number) => String(n).padStart(2, '0')
  return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}`
}

/** Date proposée par le modèle : le 24 décembre à venir pour Noël, sinon dans 7 jours. */
export function defaultDate(kind: EventKind, today: Date = new Date()): string {
  if (kind === 'noel') {
    const y = today.getMonth() === 11 && today.getDate() > 24 ? today.getFullYear() + 1 : today.getFullYear()
    return `${y}-12-24`
  }
  const d = new Date(today.getFullYear(), today.getMonth(), today.getDate() + 7)
  return isoDay(d)
}

/** « mercredi 24 décembre » (+ année si ce n'est pas l'année en cours). */
export function formatEventDate(iso: string, today: Date = new Date()): string {
  const [y, m, d] = iso.split('-').map(Number)
  const date = new Date(y, m - 1, d)
  const opts: Intl.DateTimeFormatOptions = { weekday: 'long', day: 'numeric', month: 'long' }
  if (y !== today.getFullYear()) opts.year = 'numeric'
  return date.toLocaleDateString('fr-FR', opts)
}

/** Nombre de jours avant l'événement (0 = aujourd'hui, négatif = passé). */
export function daysUntil(iso: string, today: Date = new Date()): number {
  const [y, m, d] = iso.split('-').map(Number)
  const a = Date.UTC(y, m - 1, d)
  const b = Date.UTC(today.getFullYear(), today.getMonth(), today.getDate())
  return Math.round((a - b) / 86_400_000)
}

export function countdownLabel(iso: string, today: Date = new Date()): string {
  const n = daysUntil(iso, today)
  if (n === 0) return 'C’est aujourd’hui !'
  if (n === 1) return 'C’est demain'
  if (n > 1) return `Dans ${n} jours`
  return 'C’est passé'
}

/** Page « éphémère » : l'événement reste en avant jusqu'à 3 jours après, puis passe dans « Passés ». */
export const isUpcoming = (iso: string, today: Date = new Date()) => daysUntil(iso, today) >= -3

/** Lien de playlist accepté : https seulement (la base refuse le reste). */
export function cleanPlaylistUrl(raw: string): string | null {
  const v = raw.trim()
  if (!v) return null
  if (!/^https:\/\/[^\s]+$/i.test(v) || v.length > LIMITS.playlist) return ''
  return v
}

export function countRsvps(answers: readonly { answer: RsvpAnswer }[]): Record<RsvpAnswer, number> {
  const c: Record<RsvpAnswer, number> = { oui: 0, peut_etre: 0, non: 0 }
  for (const a of answers) c[a.answer]++
  return c
}
