// Quel chat pour quelle erreur (v2.1.0). Les textes restent clairs : le dessin amuse,
// le message dit quoi faire.
export type CatMood = 'hors-ligne' | 'serveur' | 'interdit' | 'introuvable' | 'inconnu'

export const MOOD_TEXT: Record<CatMood, { title: string; message: string }> = {
  'hors-ligne': {
    title: 'Pas de réseau',
    message: 'Ton téléphone n’est pas connecté. Ce qui est déjà chargé reste visible ; réessaie quand le réseau revient.',
  },
  serveur: {
    title: 'Le serveur ne répond pas',
    message: 'Ça ne vient pas de toi. Réessaie dans quelques minutes ; si ça dure, préviens Titouan.',
  },
  interdit: {
    title: 'Pas le droit d’entrer',
    message: 'Cette action est réservée à d’autres personnes du foyer (un admin, ou l’auteur).',
  },
  introuvable: {
    title: 'Introuvable',
    message: 'Cette page ou cet élément n’existe pas (ou plus). Il a peut-être été supprimé.',
  },
  inconnu: {
    title: 'Quelque chose s’est emmêlé',
    message: 'Une erreur inattendue est arrivée. Réessaie ; si ça recommence, envoie un mot depuis « Idées et retours ».',
  },
}

/** Devine le type d'erreur (réseau, droits, introuvable, serveur, autre). */
export function errorMood(error: unknown): CatMood {
  if (typeof navigator !== 'undefined' && navigator.onLine === false) return 'hors-ligne'
  const e = (error ?? {}) as { code?: unknown; status?: unknown; message?: unknown; name?: unknown }
  const msg = typeof e.message === 'string' ? e.message : typeof error === 'string' ? error : ''
  const code = typeof e.code === 'string' ? e.code : ''
  const status = typeof e.status === 'number' ? e.status : 0
  if (/failed to fetch|networkerror|network request failed|load failed|pas de réseau/i.test(msg)) return 'hors-ligne'
  if (code === '42501' || status === 401 || status === 403 || /permission|interdit|refus/i.test(msg)) return 'interdit'
  if (code === 'PGRST116' || status === 404 || /introuvable|not found|no rows|n’existe|n'existe/i.test(msg)) return 'introuvable'
  if (status >= 500 || /^5\d\d$/.test(code) || /timeout|unavailable|service/i.test(msg)) return 'serveur'
  return 'inconnu'
}

/** Message technique (anglais, codes) : on montre plutôt le texte clair du chat. */
export function isTechnical(message: string | null | undefined): boolean {
  return !!message && /no rows|failed to fetch|networkerror|load failed|jwt|pgrst|violates|permission denied|syntax|undefined|null|timeout|status \d{3}/i.test(message)
}
