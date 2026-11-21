// Publication publique des recettes (migration 37).
// Une recette ne devient visible du public qu'après validation par l'administrateur.
// Les visibilités « foyer » et « toute la famille » n'ont AUCUNE validation.
// Les droits sont décidés par la base ; ces fonctions ne servent qu'à l'affichage.

/** Nombre maximum de demandes en attente par auteur (contrôlé aussi par la base) */
export const MAX_PENDING_REQUESTS = 3
/** Délai indicatif annoncé à l'auteur (pas un engagement juridique) */
export const REVIEW_DELAY_TEXT = 'en général sous 24 h'

export type PublicStatus = 'en_attente' | 'validee' | 'refusee'

/** Motifs de refus : liste fermée, la même que la contrainte de la base */
export const REFUSAL_REASONS = [
  { code: 'contenu_inapproprie', label: 'Contenu inapproprié' },
  { code: 'recette_incomplete', label: 'Recette incomplète' },
  { code: 'copie_suspecte', label: 'Texte ou photo copiés' },
  { code: 'photo_inadaptee', label: 'Photo inadaptée' },
  { code: 'doublon', label: 'Recette en double' },
  { code: 'autre', label: 'Autre raison' },
] as const
export type RefusalReason = (typeof REFUSAL_REASONS)[number]['code']

export function refusalLabel(code: string | null | undefined): string {
  return REFUSAL_REASONS.find((r) => r.code === code)?.label ?? 'Autre raison'
}

export interface PublicationInfo {
  /** Texte du badge (null = aucun badge) */
  badge: string | null
  /** Action principale proposée à l'auteur */
  action: 'demander' | 'retirer' | 'depublier' | 'redemander' | null
  actionLabel: string | null
  /** Phrase d'explication sous la ligne (motif de refus, délai…) */
  note: string | null
}

/** Ce que l'auteur voit pour une recette (calcul pur, testé). */
export function publicationInfo(r: {
  public_status?: PublicStatus | null
  public_refusal_reason?: string | null
  archived_at?: string | null
  visibility?: string
}): PublicationInfo {
  if (r.archived_at || r.visibility === 'catalogue') return { badge: null, action: null, actionLabel: null, note: null }
  switch (r.public_status) {
    case 'en_attente':
      return { badge: 'En attente de validation', action: 'retirer', actionLabel: 'Retirer la demande', note: `Réponse ${REVIEW_DELAY_TEXT}.` }
    case 'validee':
      return { badge: 'Publique', action: 'depublier', actionLabel: 'Dépublier', note: 'Si tu la modifies, elle repart en validation.' }
    case 'refusee':
      return { badge: 'Refusée', action: 'redemander', actionLabel: 'Redemander', note: `Motif : ${refusalLabel(r.public_refusal_reason)}. Corrige-la puis redemande.` }
    default:
      return { badge: null, action: 'demander', actionLabel: 'Publier en public', note: null }
  }
}
