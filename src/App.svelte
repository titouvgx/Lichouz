<script lang="ts">
  import { router, navigate, PUBLIC_ROUTES } from './lib/router.svelte'
  import { auth, initAuth, signOut } from './lib/auth.svelte'
  import { profileState, loadProfile, clearProfile } from './lib/profile.svelte'
  import { supabaseConfigured } from './lib/supabase'

  import TabBar from './components/TabBar.svelte'
  import AppHeader from './components/AppHeader.svelte'
  import ToastContainer from './components/ToastContainer.svelte'
  import AppBackdrop from './components/AppBackdrop.svelte'
  import Login from './pages/Login.svelte'
  import Accueil from './pages/Accueil.svelte'
  import Frigo from './pages/Frigo.svelte'
  import Recettes from './pages/Recettes.svelte'
  import RecetteDetail from './pages/RecetteDetail.svelte'
  import RecetteForm from './pages/RecetteForm.svelte'
  import Semaine from './pages/Semaine.svelte'
  import Courses from './pages/Courses.svelte'
  import Historique from './pages/Historique.svelte'
  import MonCompte from './pages/MonCompte.svelte'
  import Famille from './pages/Famille.svelte'
  import MesRecettes from './pages/MesRecettes.svelte'
  import Evenements from './pages/Evenements.svelte'
  import Evenement from './pages/Evenement.svelte'
  import Avis from './pages/Avis.svelte'
  import Nouveautes from './pages/Nouveautes.svelte'
  import ConfirmDialog from './components/ConfirmDialog.svelte'
  import { RELEASE_NOTES, shouldShowNews, lastSeenNews, markNewsSeen } from './lib/nouveautes'
  import { APP_VERSION } from './lib/version'
  import Aide from './pages/Aide.svelte'
  import Bienvenue from './components/Bienvenue.svelte'
  import { welcome, welcomeSeen } from './lib/bienvenue.svelte'
  import Admin from './pages/Admin.svelte'
  import Rejoindre from './pages/Rejoindre.svelte'
  import MotDePasseOublie from './pages/MotDePasseOublie.svelte'
  import { isRecoveryPending, setRecoveryPending } from './lib/api/famille'
  import NouveauMotDePasse from './pages/NouveauMotDePasse.svelte'
  import ConfirmerEmail from './pages/ConfirmerEmail.svelte'

  // Pages plein écran, accessibles sans être connecté (invitation, mot de passe).
  // Elles restent affichées même quand une session s'ouvre pendant qu'on y est
  // (création du compte, lien de réinitialisation) : c'est la page qui navigue ensuite.
  const isPublicPage = $derived(PUBLIC_ROUTES.includes(router.current))

  // Initialiser l'auth au montage
  initAuth()

  // Charger le profil quand l'user change.
  // On attend que la session soit vérifiée : sinon, au démarrage, l'utilisateur
  // paraît déconnecté une fraction de seconde, le profil est marqué « chargé »
  // sans données, et les pages affichent « Profil introuvable » à tort.
  $effect(() => {
    if (auth.loading) return
    if (auth.user) {
      loadProfile(auth.user.id)
    } else {
      clearProfile()
    }
  })

  // Redirection : si pas connecté → login, si connecté et sur login → accueil
  $effect(() => {
    if (auth.loading) return

    // Session ouverte par un lien « mot de passe oublié » sans nouveau mot de passe
    // enregistré : on la ferme dès qu'on quitte la page (pas d'accès à l'appli).
    if (auth.user && isRecoveryPending() && router.current !== 'nouveau-mot-de-passe') {
      setRecoveryPending(false)
      void signOut('local').then(() => navigate('login'))
      return
    }
    if (isPublicPage) return
    if (!auth.user && router.current !== 'login') {
      navigate('login')
    } else if (auth.user && router.current === 'login') {
      navigate('accueil')
    }
  })

  // Bienvenue plein écran : à chaque ouverture, une fois connecté (profil chargé),
  // jusqu'à « Ne plus afficher ». Jamais sur les pages publiques ni sur l'aide.
  const showWelcome = $derived(
    !!auth.user && !!profileState.profile?.id && !isPublicPage && router.current !== 'aide'
      && !welcome.closedThisLaunch && !welcomeSeen(profileState.profile.id),
  )

  // Nouveautés (v1.6.0) : une fois par version, après la bienvenue, jamais en même temps.
  // Une personne qui n'a encore rien vu (première ouverture) ne les voit pas :
  // on note la version actuelle pour lui montrer seulement les suivantes.
  let newsClosed = $state(false)
  const newsUserId = $derived(auth.user && profileState.profile?.id && !isPublicPage ? profileState.profile.id : null)
  const showNews = $derived(
    !!newsUserId && !showWelcome && !newsClosed && router.current !== 'nouveautes'
      && shouldShowNews({ version: APP_VERSION, lastSeen: lastSeenNews(newsUserId), welcomeDone: welcomeSeen(newsUserId) }),
  )
  $effect(() => {
    if (newsUserId && lastSeenNews(newsUserId) === null && !welcomeSeen(newsUserId)) {
      markNewsSeen(newsUserId, APP_VERSION)
    }
  })
  const currentNotes = RELEASE_NOTES.find((n) => n.version === APP_VERSION)
  function closeNews() {
    if (newsUserId) markNewsSeen(newsUserId, APP_VERSION)
    newsClosed = true
  }

  function handleSignOut() {
    clearProfile(true) // déconnexion : on efface aussi les données gardées sur le téléphone
    signOut()
  }
</script>

<!-- Fond commun à toutes les pages (y compris connexion et chargement) : pluie lente d'aliments -->
<AppBackdrop />
<ToastContainer />

{#if isPublicPage}
  {#if router.current === 'rejoindre'}
    <Rejoindre />
  {:else if router.current === 'mot-de-passe-oublie'}
    <MotDePasseOublie />
  {:else if router.current === 'confirmer-email'}
    <ConfirmerEmail />
  {:else}
    <NouveauMotDePasse />
  {/if}
{:else if auth.loading}
  <div class="loading">
    <div class="spinner"></div>
  </div>
{:else if !auth.user}
  <!-- Non connecté : page de login -->
  <Login />
{:else if profileState.disabled}
  <!-- Compte désactivé par un admin (v1.99.0) : rien d'autre n'est accessible -->
  <main class="disabled-screen">
    <div class="card disabled-card" role="alert">
      <span class="disabled-icon" aria-hidden="true"><svg width="28" height="28" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="square" stroke-linejoin="miter"><rect x="5" y="11" width="14" height="10" /><path d="M8 11V8a4 4 0 0 1 8 0v3" /></svg></span>
      <h1>Compte désactivé</h1>
      <p>Un admin de ta famille a mis ton compte en pause. Tes recettes et ton historique sont gardés.</p>
      <p>Pour retrouver l’accès, demande-lui de le réactiver.</p>
      <button class="btn btn-outline" onclick={handleSignOut}>Se déconnecter</button>
    </div>
  </main>
{:else}
  <!-- Connecté : app shell -->
  <AppHeader />
  <div class="app-shell">
    {#if router.current === 'accueil'}
      <Accueil />
    {:else if router.current === 'frigo'}
      <Frigo />
    {:else if router.current === 'recettes'}
      <Recettes />
    {:else if router.current === 'recette'}
      <RecetteDetail />
    {:else if router.current === 'nouvelle-recette'}
      <RecetteForm />
    {:else if router.current === 'editer-recette'}
      <RecetteForm editId={router.recipeId} />
    {:else if router.current === 'semaine'}
      <Semaine />
    {:else if router.current === 'courses'}
      <Courses />
    {:else if router.current === 'historique'}
      <Historique />
    {:else if router.current === 'compte'}
      <MonCompte />
    {:else if router.current === 'famille'}
      <Famille />
    {:else if router.current === 'evenements'}
      <Evenements />
    {:else if router.current === 'evenement'}
      {#key router.recipeId}<Evenement />{/key}
    {:else if router.current === 'mes-recettes'}
      <MesRecettes />
    {:else if router.current === 'avis'}
      <Avis />
    {:else if router.current === 'nouveautes'}
      <Nouveautes />
    {:else if router.current === 'aide'}
      <Aide />
    {:else if router.current === 'admin'}
      <Admin />
    {:else}
      <div class="page-404">
        <h1>Page introuvable</h1>
        <p>Cette adresse n'existe pas.</p>
        <a href="#/accueil" class="btn btn-outline">Retour à l'accueil</a>
      </div>
    {/if}
  </div>

  <TabBar />
  {#if showWelcome}
    <Bienvenue />
  {/if}
  {#if showNews && currentNotes}
    <ConfirmDialog
      title="Nouveau dans Lichouz {APP_VERSION}"
      confirmLabel="C’est noté"
      cancelLabel="Fermer"
      onconfirm={closeNews}
      oncancel={closeNews}
    >
      <ul class="news-list">
        {#each currentNotes.items as item, i (i)}
          <li>{item}</li>
        {/each}
      </ul>
    </ConfirmDialog>
  {/if}
{/if}

<style>
  .news-list { margin: 0; padding-left: 20px; display: flex; flex-direction: column; gap: 8px; text-align: left; line-height: 1.45; }

  .loading {
    min-height: 100dvh;
    display: flex;
    align-items: center;
    justify-content: center;
  }

  /* Chargement : un carré orange qui bascule d'un quart de tour, sec, en boucle */
  .spinner {
    width: 28px;
    height: 28px;
    border: var(--line-w) solid var(--line);
    background: var(--accent);
    box-shadow: var(--shadow-sm);
    animation: spin 0.7s var(--ease-snap) infinite;
  }

  @keyframes spin {
    to { transform: rotate(90deg); }
  }

  .app-shell {
    min-height: 100dvh;
    /* Place pour la tab bar + safe area bottom */
    padding-bottom: calc(84px + env(safe-area-inset-bottom, 0px));
  }

  .disabled-screen {
    min-height: 100dvh;
    display: grid;
    place-items: center;
    padding: var(--gutter);
  }
  .disabled-card {
    width: min(420px, 100%);
    display: flex;
    flex-direction: column;
    gap: var(--sp-3);
    padding: var(--sp-5) var(--sp-4);
  }
  .disabled-card h1 { font-size: var(--fs-2xl); }
  .disabled-card p { color: var(--text-secondary); }
  .disabled-icon {
    display: grid;
    place-items: center;
    width: 56px;
    height: 56px;
    border: var(--line-w) solid var(--line);
    background: var(--error);
    color: var(--on-error);
    box-shadow: var(--shadow-sm);
  }

  .page-404 {
    padding: var(--gutter);
    padding-top: calc(60px + env(safe-area-inset-top, 0px));
    text-align: center;
  }

  .page-404 p {
    color: var(--text-secondary);
    margin: 8px 0 24px;
  }
</style>
