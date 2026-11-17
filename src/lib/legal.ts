// Documents légaux (v2.0.0, lot C). Version = date de publication des CGU et de la
// politique de confidentialité. ⚠️ Même valeur que public.current_terms_version()
// (migration 29) ; changer les textes de façon importante = nouvelle date + nouvelle
// migration qui change la fonction → tout le monde ré-accepte à la prochaine ouverture.
export const TERMS_VERSION = '2026-11-17'

/** Date lisible de la version (« 17 novembre 2026 »). */
export const TERMS_DATE_LABEL = new Date(`${TERMS_VERSION}T12:00:00`).toLocaleDateString('fr-FR', {
  day: 'numeric',
  month: 'long',
  year: 'numeric',
})

export type AgeGroup = 'majeur' | '15_17' | 'moins_15'

export const AGE_LABELS: Record<AgeGroup, string> = {
  majeur: '18 ans ou plus',
  '15_17': 'Entre 15 et 17 ans',
  moins_15: 'Moins de 15 ans',
}

/** Responsable du traitement et contact (affichés dans les documents). */
export const CONTROLLER = {
  name: 'Titouan',
  role: 'créateur de Lichouz, à titre personnel et non commercial',
  contact: 'le bouton « Idées et retours » de l’appli (Mon compte), ou directement auprès de Titouan',
}

/** Sous-traitants : qui héberge ou transporte les données (vérifié le 17/11/2026). */
export const PROCESSORS = [
  {
    name: 'Supabase',
    what: 'base de données, comptes et connexion, photos des recettes',
    where: 'Union européenne (Irlande, région « eu-west-1 »)',
  },
  {
    name: 'Brevo',
    what: 'envoi des e-mails (confirmation d’adresse, mot de passe oublié)',
    where: 'France / Union européenne',
  },
  {
    name: 'GitHub Pages',
    what: 'hébergement du site (les fichiers de l’appli, pas tes données)',
    where: 'États-Unis (GitHub, Microsoft) : reçoit ton adresse IP quand tu ouvres l’appli',
  },
  {
    name: 'Unsplash',
    what: 'certaines photos des recettes du catalogue',
    where: 'États-Unis : reçoit ton adresse IP quand une de ces photos s’affiche',
  },
] as const

/** Durées de conservation (mêmes durées que public.purge_expired_data()). */
export const RETENTION = [
  { what: 'Ton compte, ton profil, tes recettes', how: 'tant que ton compte existe ; effacés quand tu le supprimes (tes recettes restent dans le foyer, sans ton nom)' },
  { what: 'Preuve d’acceptation des conditions', how: 'tant que ton compte existe' },
  { what: 'Journal des erreurs de l’appli', how: '90 jours' },
  { what: 'Liens d’invitation utilisés, annulés ou expirés', how: '90 jours après' },
  { what: 'Événements', how: '1 an après leur date' },
  { what: 'Listes de courses terminées et plannings de repas', how: '2 ans' },
  { what: 'Idées et retours envoyés', how: '2 ans' },
] as const
