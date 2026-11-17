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
    version: '2.4.0',
    date: '2026-11-17',
    items: [
      'Booster du jour : sur l’accueil, ouvre le paquet et les 5 recettes du jour en sortent (une ouverture par jour, ou « Passer »).',
      'Le tirage évite ce que ton foyer a cuisiné ces 2 dernières semaines ou déjà prévu, et favorise les recettes les mieux notées.',
    ],
  },
  {
    version: '2.3.0',
    date: '2026-11-17',
    items: [
      'Nouvel onglet Tendances : le Top 25 ou Top 50 des recettes les mieux notées.',
      'Aussi dans Tendances : les recettes les plus cuisinées chez vous ce mois-ci, et les nouvelles recettes.',
      'L’historique des courses est maintenant dans Courses → « Listes passées ».',
    ],
  },
  {
    version: '2.2.0',
    date: '2026-11-17',
    items: [
      'Les étoiles arrivent : note chaque recette de 1 à 5, directement sur sa fiche.',
      'Tout le monde voit la moyenne et le nombre de votes ; ton vote à toi reste privé.',
      'La moyenne s’affiche aussi sur les cartes de la page Recettes.',
    ],
  },
  {
    version: '2.1.0',
    date: '2026-11-17',
    items: [
      'Nouveaux mots : ton « foyer », ce sont les personnes qui vivent avec toi ; ta « famille », ce sont tous vos foyers réunis (ex. famille Martin).',
      'Inviter quelqu’un à côté de toi : après avoir créé le lien, « Afficher en QR code » et il le scanne avec son téléphone.',
      'Un lien d’invitation présente d’abord Lichouz, avant de créer le compte.',
      'Nouvelle icône : le chat de Lichouz, sur l’écran d’accueil du téléphone et dans l’appli.',
      'Quand quelque chose ne marche pas, un chat dessiné te dit quoi faire.',
    ],
  },
  {
    version: '2.0.0',
    date: '2026-11-17',
    items: [
      'Lichouz a maintenant ses règles écrites : conditions d’utilisation et confidentialité, à accepter une fois.',
      'Chacun choisit son pseudo, unique dans toute l’appli (il servira au quiz et aux classements).',
      'Mon compte → Vie privée : change ton pseudo, télécharge toutes tes données, relis les règles.',
      'Moins de 15 ans : un parent du foyer donne son accord depuis son téléphone (Vie privée).',
      'Le ménage des vieilles données se fait tout seul (durées écrites dans Confidentialité).',
    ],
  },
  {
    version: '1.999.0',
    date: '2026-11-17',
    items: [
      'Événements : organise Noël, un anniversaire ou une fête (Accueil ou Mon compte → Événements).',
      'Chacun répond « Je viens », « Peut-être » ou « Je ne viens pas », et s’inscrit dans « Qui fait quoi » (apéritif, plat, desserts…).',
      'Chez qui, thème, lien de playlist, infos pratiques ; visible par ton foyer ou par toute la famille.',
      'Thème de Noël : grande cheminée sur l’accueil.',
    ],
  },
  {
    version: '1.99.3',
    date: '2026-11-17',
    items: [
      'Thème de Noël 🎄 : crème, sapin, rouge et or, flocons qui tombent et cheminée sur l’accueil. Il s’active tout seul du 1er décembre au 6 janvier.',
      'Mon compte → Affichage : choisis Automatique, Classique ou Noël quand tu veux.',
      'Liste de courses plus légère : les recettes d’origine sont en simple texte gris.',
      'Mot de passe oublié : après en avoir choisi un nouveau, reconnecte-toi avec (tu es déconnecté de tous tes appareils).',
    ],
  },
  {
    version: '1.99.0',
    date: '2026-11-16',
    items: [
      'Semaine : entrée, plat et dessert sur un même repas (« + Entrée », « + Dessert »).',
      'Restes : prévois de manger plus tard ce que tu cuisines aujourd’hui, les courses comptent les deux.',
      'Recopie la semaine d’avant, ou enregistre et applique des semaines types.',
      'En cuisine : bouton Minuteur quand une étape parle d’une durée.',
      'Recettes : filtre par temps de préparation, étiquettes sur les cartes, et une étiquette touchée sur une fiche montre toutes les recettes qui l’ont.',
      'Admins : désactiver un compte (et le réactiver) au lieu de le supprimer.',
    ],
  },
  {
    version: '1.9.0',
    date: '2026-11-16',
    items: [
      'Nouveau look pour toute l’appli : fond beurre, encre noire, boutons carrés qui s’enfoncent quand on appuie.',
      'Des aliments tombent doucement dans le fond. Ils s’arrêtent si ton téléphone est réglé sur « réduire les animations ».',
      'Mode sombre : l’appli suit le réglage de ton téléphone.',
      'Animations plus vives : onglets, fenêtres qui montent du bas, cases qui se cochent, cartes qui tombent à leur place.',
    ],
  },
  {
    version: '1.8.0',
    date: '2026-11-16',
    items: [
      'Recettes : bouton « Filtres » pour trier par régime (végétarien, vegan, sans gluten…), budget, thème ou origine.',
      'Chaque recette peut recevoir ses étiquettes dans le formulaire ; les 50 recettes du catalogue sont déjà étiquetées.',
      'Nouveaux types : apéritif, sauce, petit-déj & goûter, boisson & cocktail.',
      'La recherche trouve aussi les étiquettes : tape « vegan » ou « Bretagne ».',
    ],
  },
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
