// Pseudo (v2.0.0, migration 29) : mêmes règles que la base (public.pseudo_is_valid).
// La base reste juge ; ces règles servent à prévenir AVANT d'envoyer.
// ⚠️ La liste RESERVED_PSEUDOS doit rester identique à celle de la migration
// 20261118100000_conformite.sql (un test unitaire compare les deux).

export const PSEUDO_MIN = 3
export const PSEUDO_MAX = 20

export const RESERVED_PSEUDOS = [
  'admin', 'administrateur', 'administration', 'moderateur', 'moderation', 'modo',
  'support', 'aide', 'help', 'contact', 'equipe', 'staff', 'officiel', 'service',
  'root', 'system', 'systeme', 'superadmin', 'super_admin', 'fondateur',
  'null', 'undefined', 'anonyme', 'inconnu', 'supprime', 'auteur_supprime', 'compte_supprime',
] as const

/** Message d'erreur en français, ou null si le pseudo est valable. */
export function pseudoProblem(raw: string): string | null {
  const p = raw.trim()
  if (p.length < PSEUDO_MIN) return `Au moins ${PSEUDO_MIN} caractères`
  if (p.length > PSEUDO_MAX) return `${PSEUDO_MAX} caractères au plus`
  if (!/^[A-Za-z0-9_.]+$/.test(p)) return 'Lettres sans accent, chiffres, « _ » et « . » seulement'
  if (/^[._]/.test(p) || /[._]$/.test(p)) return 'Pas de « . » ni de « _ » au début ou à la fin'
  if (p.includes('..')) return 'Pas deux points à la suite'
  const low = p.toLowerCase()
  if ((RESERVED_PSEUDOS as readonly string[]).includes(low) || /^(lichouz|admin)/.test(low)) return 'Ce pseudo est réservé'
  return null
}

/** Propose un pseudo de départ à partir du prénom (sans accents ni espaces). */
export function suggestPseudo(displayName: string): string {
  const base = displayName
    .normalize('NFD')
    .replace(/[̀-ͯ]/g, '')
    .replace(/[^A-Za-z0-9]+/g, '_')
    .replace(/^_+|_+$/g, '')
    .slice(0, PSEUDO_MAX)
  return pseudoProblem(base) ? '' : base
}
