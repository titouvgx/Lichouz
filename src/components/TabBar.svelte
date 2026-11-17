<script lang="ts">
  import { router, href, TAB_ROUTES, type TabRoute } from '../lib/router.svelte'

  const tabs: { route: TabRoute; label: string; icon: string }[] = [
    { route: 'accueil',     label: 'Accueil',     icon: 'home' },
    { route: 'recettes',    label: 'Recettes',    icon: 'book' },
    { route: 'semaine',     label: 'Semaine',     icon: 'calendar' },
    { route: 'courses',     label: 'Courses',     icon: 'cart' },
    { route: 'historique',  label: 'Historique',   icon: 'clock' },
  ]

  /** Index de l'onglet actif (-1 sur Mon compte, la connexion…) : place la pastille */
  const activeIndex = $derived(tabs.findIndex((t) => isActive(t.route)))

  function isActive(route: TabRoute): boolean {
    if (route === 'accueil') {
      return router.current === 'accueil' || router.current === 'frigo' // sous-page de l'accueil
    }
    if (route === 'recettes') {
      return ['recettes', 'recette', 'nouvelle-recette', 'editer-recette'].includes(router.current)
    }
    return router.current === route
  }
</script>

<nav class="tab-bar deco-neige" aria-label="Navigation principale" style:--count={tabs.length}>
  <!-- Bloc orange qui glisse sous l'onglet actif (une seule pièce, déplacée par transform) -->
  <span
    class="indicator"
    class:hidden={activeIndex < 0}
    style:--i={Math.max(activeIndex, 0)}
    aria-hidden="true"
  ></span>
  {#each tabs as tab (tab.route)}
    <a
      href={href(tab.route)}
      class="tab"
      class:active={isActive(tab.route)}
      aria-current={isActive(tab.route) ? 'page' : undefined}
    >
      <svg class="tab-icon" width="21" height="21" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true">
        {#if tab.icon === 'home'}
          <path d="M3 10.5 12 3l9 7.5"/>
          <path d="M5 9v12h5v-6h4v6h5V9"/>
        {:else if tab.icon === 'book'}
          <path d="M4 3h16v18H4z"/>
          <path d="M8 3v18M11 8h6M11 12h6"/>
        {:else if tab.icon === 'calendar'}
          <rect x="3" y="4" width="18" height="18"/>
          <path d="M16 2v4M8 2v4M3 10h18"/>
        {:else if tab.icon === 'cart'}
          <path d="M1 2h4l3 13h12l3-9H6"/>
          <path d="M9 20h1M18 20h1"/>
        {:else if tab.icon === 'clock'}
          <circle cx="12" cy="12" r="10"/>
          <path d="M12 6v6l4 2"/>
        {/if}
      </svg>
      <span class="tab-label">{tab.label}</span>
    </a>
  {/each}
</nav>

<style>
  /* Barre d'onglets « Brutal beurre » : bande blanche, trait noir au-dessus.
     L'onglet actif est un bloc orange qui GLISSE d'un onglet à l'autre
     (une seule pièce, déplacée par transform, avec un petit claquement). */
  .tab-bar {
    view-transition-name: tab-bar; /* reste immobile pendant les transitions de page */
    position: fixed;
    inset: auto 0 0 0;
    display: flex;
    height: calc(64px + env(safe-area-inset-bottom, 0px));
    padding: 0 6px env(safe-area-inset-bottom, 0px);
    background: var(--surface);
    border-top: var(--line-w) solid var(--line);
    z-index: 100;
  }

  /* Bloc orange : une « case » de la largeur d'un onglet, déplacée de i cases */
  .indicator {
    position: absolute;
    top: 7px;
    left: 6px;
    width: calc((100% - 12px) / var(--count));
    height: 50px;
    padding: 0 4px 0 0; /* l'ombre (3 px à droite) reste dans la case */
    transform: translateX(calc(var(--i) * 100%));
    transition: transform var(--dur-sheet) var(--ease-snap), opacity var(--dur-base);
    pointer-events: none;
  }

  .indicator::before {
    content: '';
    display: block;
    height: 100%;
    background: var(--accent);
    border: var(--line-w) solid var(--line);
    box-shadow: var(--shadow-sm);
  }

  .indicator.hidden { opacity: 0; }

  .tab {
    position: relative; /* au-dessus du bloc */
    flex: 1;
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    gap: 2px;
    min-width: 0;
    color: var(--text);
    text-decoration: none;
    touch-action: manipulation;
    -webkit-tap-highlight-color: transparent;
    transition: transform var(--dur-fast) var(--ease-out);
  }

  .tab.active { color: var(--on-accent); }

  /* Appui : l'onglet s'enfonce un peu */
  .tab:active { transform: translateY(2px); }

  .tab-icon {
    stroke-width: 2;
    stroke-linecap: square;
    stroke-linejoin: miter;
  }

  /* L'icône de l'onglet qui devient actif « tombe » à sa place */
  .tab.active .tab-icon {
    animation: tab-drop var(--dur-sheet) var(--ease-snap);
  }

  @keyframes tab-drop {
    from { transform: translateY(-6px); }
  }

  .tab-label {
    font-size: 12px;
    letter-spacing: -0.01em;
    font-weight: var(--fw-medium);
    white-space: nowrap;
  }

  .tab.active .tab-label { font-weight: var(--fw-bold); }
</style>
