// « Nouveautés » (v1.6.0) : ce qui a changé, en mots simples, pour la famille.
// Le CHANGELOG reste la référence technique ; ici, seulement ce qui se voit.
// À compléter à chaque version qui change quelque chose de visible.

export interface ReleaseNote {
  version: string
  date: string
  items: string[]
}

export const RELEASE_NOTES: ReleaseNote[] = [
  {
    version: '1.7.0',
    date: '2026-11-16',
    items: [
      'Inviter : tu peux indiquer l’adresse e-mail de la personne. Seule cette adresse pourra utiliser le lien.',
      'Une coche dans la liste de courses porte toujours le nom de celui ou celle qui a coché.',
    ],
  },
  {
    version: '1.6.0',
    date: '2026-11-16',
    items: [
      'Mon compte → « Idées et retours » : envoie une idée, signale un bug.',
      'Cet écran « Nouveautés » s’affiche une fois après chaque mise à jour ; on le retrouve dans Mon compte.',
      'Les erreurs de l’appli sont signalées automatiquement (sans rien de personnel) pour être corrigées plus vite.',
    ],
  },
  {
    version: '1.5.0',
    date: '2026-11-16',
    items: ['Mon compte → « Mes recettes » : tes recettes, à partager, modifier ou archiver.'],
  },
  {
    version: '1.4.0',
    date: '2026-11-15',
    items: [
      'Liste de courses : on voit à quelles recettes sert chaque article.',
      'Bouton « Partager la liste » (WhatsApp, SMS…).',
      'Plus de « 1,5 œuf » : ce qui se compte à la pièce est arrondi.',
      'Les recettes s’archivent au lieu d’être supprimées, et se restaurent.',
    ],
  },
]

const key = (userId: string) => `lichouz:nouveautes-vue:${userId}`

/**
 * Faut-il montrer les nouveautés de cette version ? Calcul pur (testé).
 * - Déjà vues pour cette version : non.
 * - Personne nouvelle (jamais rien vu, et l'écran de bienvenue pas encore
 *   terminé) : non, elle découvre tout avec la bienvenue.
 * - Pas de note pour cette version (correctif invisible) : non.
 */
export function shouldShowNews(opts: {
  version: string
  lastSeen: string | null
  welcomeDone: boolean
  notes?: ReleaseNote[]
}): boolean {
  const notes = opts.notes ?? RELEASE_NOTES
  if (opts.lastSeen === opts.version) return false
  if (opts.lastSeen === null && !opts.welcomeDone) return false
  return notes.some((n) => n.version === opts.version)
}

export function lastSeenNews(userId: string): string | null {
  try {
    return localStorage.getItem(key(userId))
  } catch {
    return null
  }
}

export function markNewsSeen(userId: string, version: string): void {
  try {
    localStorage.setItem(key(userId), version)
  } catch {
    // stockage indisponible : l'écran reviendra, tant pis
  }
}
