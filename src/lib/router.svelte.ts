import { tick } from 'svelte'

// Routeur « par # » : l'adresse ressemble à https://…/#/courses.
// Le serveur (GitHub Pages) ne voit jamais ce qui suit le #, il renvoie donc
// toujours index.html : aucune erreur 404 possible, même en rechargeant la page.

export type Route =
  | 'login'
  | 'accueil'          // page d'accueil : 5 recettes du jour
  | 'frigo'            // « Qu'est-ce qu'on mange ? » : recettes selon le frigo
  | 'recettes'
  | 'recette'          // détail : #/recette/<id>
  | 'nouvelle-recette' // création : #/nouvelle-recette
  | 'editer-recette'   // édition : #/editer-recette/<id>
  | 'semaine'
  | 'courses'
  | 'historique'
  | 'compte'           // page profil / mon compte
  | 'aide'             // aide : à quoi sert l'appli, onglet par onglet, FAQ
  | 'famille'          // ma famille : membres, invitations ; fondateur : ses familles
  | 'mes-recettes'     // mes recettes : partagées, famille seulement, archivées
  | 'avis'             // idées et retours envoyés à Titouan (v1.6.0)
  | 'nouveautes'       // ce qui a changé, version par version (v1.6.0)
  | 'admin'            // super-admin : liens fondateur, vue d'ensemble
  | 'evenements'       // fêtes et événements (v1.999.0) ; #/evenements/nouveau ouvre le formulaire
  | 'evenement'        // un événement : #/evenement/<id>
  | 'rejoindre'        // public : #/rejoindre/<jeton> (création de compte par lien)
  | 'mot-de-passe-oublie'  // public : demande d'e-mail de réinitialisation
  | 'nouveau-mot-de-passe' // public : arrivée depuis l'e-mail (?token_hash=…&type=recovery)
  | 'confirmer-email'      // public : lien « Confirme ton adresse » (?token_hash=…&type=signup)
  | 'cgu'                  // public : conditions d'utilisation (v2.0.0)
  | 'confidentialite'      // public : politique de confidentialité (v2.0.0)
  | 'stockage'             // public : stockage sur le téléphone, pas de traceur (v2.0.0)
  | 'vie-privee'           // pseudo, mes données, accords parentaux, documents (v2.0.0)
  | 'introuvable'

/** Les 5 onglets de la tab bar. */
export const TAB_ROUTES = ['accueil', 'recettes', 'semaine', 'courses', 'historique'] as const
export type TabRoute = (typeof TAB_ROUTES)[number]

const STATIC_ROUTES: string[] = [
  'login', 'accueil', 'frigo', 'recettes', 'nouvelle-recette', 'semaine', 'courses', 'historique', 'compte',
  'famille', 'mes-recettes', 'avis', 'nouveautes', 'admin', 'aide', 'evenements', 'mot-de-passe-oublie', 'nouveau-mot-de-passe', 'confirmer-email',
  'cgu', 'confidentialite', 'stockage', 'vie-privee',
]

/** Pages accessibles sans être connecté (en plus de « login »). */
export const PUBLIC_ROUTES: Route[] = ['rejoindre', 'mot-de-passe-oublie', 'nouveau-mot-de-passe', 'confirmer-email', 'cgu', 'confidentialite', 'stockage']
const DEFAULT_ROUTE: Route = 'accueil'

interface RouterState {
  current: Route
  /** ID de la recette quand current === 'recette'. */
  recipeId: string | null
  /** Jeton d'invitation quand current === 'rejoindre'. */
  token: string | null
}

function readHash(): RouterState {
  const raw = window.location.hash.replace(/^#\/?/, '')
  const parts = raw.split('/')

  // Arrivée depuis l'e-mail « mot de passe oublié » : ?token_hash=…&type=recovery
  const linkType = new URLSearchParams(window.location.search).get('type')
  if (linkType === 'recovery') {
    return { current: 'nouveau-mot-de-passe', recipeId: null, token: null }
  }
  // Arrivée depuis l'e-mail « Confirme ton adresse » : ?token_hash=…&type=signup
  if (linkType === 'signup' || linkType === 'email') {
    return { current: 'confirmer-email', recipeId: null, token: null }
  }

  if (raw === '') return { current: DEFAULT_ROUTE, recipeId: null, token: null }

  // Routes dynamiques
  if (parts[0] === 'recette' && parts[1]) {
    return { current: 'recette', recipeId: parts[1], token: null }
  }
  if (parts[0] === 'editer-recette' && parts[1]) {
    return { current: 'editer-recette', recipeId: parts[1], token: null }
  }
  if (parts[0] === 'evenement' && parts[1]) {
    return { current: 'evenement', recipeId: parts[1], token: null }
  }
  if (parts[0] === 'rejoindre') {
    return { current: 'rejoindre', recipeId: null, token: parts[1] ?? null }
  }

  // Routes statiques
  if (STATIC_ROUTES.includes(parts[0])) {
    return { current: parts[0] as Route, recipeId: null, token: null }
  }

  return { current: 'introuvable', recipeId: null, token: null }
}

// $state = valeur réactive de Svelte 5
export const router: RouterState = $state(readHash())

// ── Transitions entre pages (API View Transitions) ──
// On avance (onglet plus à droite, ouverture d'une fiche) → la page glisse vers la gauche.
// On recule → elle glisse vers la droite. Seul .app-shell (le contenu) bouge :
// le fond photo, la barre d'onglets et l'avatar restent immobiles (voir app.css).
// Navigateurs sans cette API (ou « réduire les animations ») : changement direct,
// l'animation CSS « page-in » prend le relais.

/** Position de chaque écran : onglets de gauche à droite, sous-pages juste après leur onglet. */
const ORDER: Record<Route, number> = {
  login: -10,
  accueil: 0, frigo: 1, evenements: 2, evenement: 3,
  recettes: 10, recette: 11, 'nouvelle-recette': 11, 'editer-recette': 12,
  semaine: 20,
  courses: 30,
  historique: 40,
  compte: 50, famille: 51, 'mes-recettes': 51, avis: 51, nouveautes: 51, admin: 52, aide: 53, 'vie-privee': 51,
  cgu: 54, confidentialite: 54, stockage: 54,
  rejoindre: -10, 'mot-de-passe-oublie': -9, 'nouveau-mot-de-passe': -9, 'confirmer-email': -9,
  introuvable: 60,
}

const supportsViewTransitions =
  typeof document !== 'undefined' && 'startViewTransition' in document

if (supportsViewTransitions) document.documentElement.classList.add('vt')

function applyRoute(next: RouterState) {
  router.current = next.current
  router.recipeId = next.recipeId
  router.token = next.token
  window.scrollTo(0, 0) // chaque nouvel écran commence en haut
}

window.addEventListener('hashchange', () => {
  const next = readHash()
  if (next.current === router.current && next.recipeId === router.recipeId && next.token === router.token) return

  const reduce = window.matchMedia('(prefers-reduced-motion: reduce)').matches
  if (!supportsViewTransitions || reduce) {
    applyRoute(next)
    return
  }

  const root = document.documentElement
  root.dataset.nav =
    next.current === 'login' || router.current === 'login' || PUBLIC_ROUTES.includes(next.current)
      ? 'fade'
      : ORDER[next.current] >= ORDER[router.current] ? 'forward' : 'back'

  const transition = (document as any).startViewTransition(async () => {
    applyRoute(next)
    await tick() // attendre que Svelte ait mis la nouvelle page dans le DOM
  })
  transition.finished.finally(() => {
    delete root.dataset.nav
  })
})

export function href(route: Route | string, id?: string): string {
  if (route === 'recette' && id) return `#/recette/${id}`
  if (route === 'editer-recette' && id) return `#/editer-recette/${id}`
  if (route === 'evenement' && id) return `#/evenement/${id}`
  return `#/${route}`
}

/** Navigation programmatique. */
export function navigate(route: Route | string, id?: string): void {
  window.location.hash = href(route, id).slice(1) // enlève le #
}
