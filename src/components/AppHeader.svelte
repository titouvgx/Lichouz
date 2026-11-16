<script lang="ts">
  import { profileState } from '../lib/profile.svelte'
  import { router, href } from '../lib/router.svelte'

  const initial = $derived(
    profileState.profile?.display_name
      ? profileState.profile.display_name.charAt(0).toUpperCase()
      : '?'
  )

  const isOnCompte = $derived(router.current === 'compte')
</script>

<header class="app-header">
  <a
    href={href('compte')}
    class="avatar-btn"
    class:active={isOnCompte}
    aria-label="Mon compte"
    title="Mon compte"
  >
    {initial}
  </a>
</header>

<style>
  .app-header {
    view-transition-name: app-header; /* reste immobile pendant les transitions de page */
    /* absolute (et non fixed) : l'avatar part avec le défilement au lieu de
       recouvrir les boutons qui passent dessous (ex. + des portions). */
    position: absolute;
    top: 0;
    right: 0;
    z-index: 50;
    padding: calc(10px + env(safe-area-inset-top, 0px)) max(12px, env(safe-area-inset-right, 0px)) 0 0;
    pointer-events: none;
  }

  /* Avatar carré, bordure noire, ombre franche ; s'enfonce quand on appuie */
  .avatar-btn {
    pointer-events: all;
    width: 44px;
    height: 44px;
    border: var(--line-w) solid var(--line);
    background: var(--surface);
    color: var(--text);
    box-shadow: var(--shadow-sm);
    font-size: var(--fs-lg);
    font-weight: var(--fw-bold);
    display: flex;
    align-items: center;
    justify-content: center;
    text-decoration: none;
    touch-action: manipulation;
    transition: transform var(--dur-fast) var(--ease-out);
  }

  .avatar-btn.active {
    background: var(--accent);
    color: var(--on-accent);
  }

  @media (hover: hover) and (pointer: fine) {
    .avatar-btn:hover { background: var(--surface-hover); }
    .avatar-btn.active:hover { background: var(--accent); }
  }

  .avatar-btn:active {
    transform: translate(var(--press), var(--press));
    box-shadow: none;
  }
</style>
