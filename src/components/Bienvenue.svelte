<script lang="ts">
  // Bienvenue plein écran, à chaque ouverture de l'appli :
  //   « Découvrir l'appli » → aide (fermé pour cette fois)
  //   « Fermer »            → fermé pour cette fois, revient à la prochaine ouverture
  //   « Ne plus afficher »  → définitif sur ce téléphone
  import Icon from './Icon.svelte'
  import { navigate } from '../lib/router.svelte'
  import { profileState } from '../lib/profile.svelte'
  import { welcome, markWelcomeSeen } from '../lib/bienvenue.svelte'

  let primary = $state<HTMLButtonElement | null>(null)
  $effect(() => {
    primary?.focus()
  })

  // Pas de défilement de la page derrière tant que l'écran est ouvert
  $effect(() => {
    const before = document.body.style.overflow
    document.body.style.overflow = 'hidden'
    return () => {
      document.body.style.overflow = before
    }
  })

  function closeForNow() {
    welcome.closedThisLaunch = true
  }

  function discover() {
    closeForNow()
    navigate('aide')
  }

  function neverAgain() {
    const id = profileState.profile?.id
    if (id) markWelcomeSeen(id)
    else closeForNow()
  }

  function onkeydown(e: KeyboardEvent) {
    if (e.key === 'Escape') closeForNow()
  }
</script>

<svelte:window {onkeydown} />

<div class="screen" role="dialog" aria-modal="true" aria-labelledby="welcome-title">
  <div class="content">
    <div class="logo" aria-hidden="true"><Icon name="cart" size={40} /></div>
    <h1 id="welcome-title">Bienvenue sur Lichouz</h1>
    <p class="lead">Les repas et les courses de la maison, au même endroit et à jour pour tout le monde.</p>

    <ol class="steps card">
      <li style="--i: 0"><span class="step-icon"><Icon name="book" size={20} /></span><span><strong>Choisis des recettes</strong> : les tiennes ou celles du catalogue.</span></li>
      <li style="--i: 1"><span class="step-icon"><Icon name="calendar" size={20} /></span><span><strong>Planifie la semaine</strong> : qui mange quoi, et qui cuisine.</span></li>
      <li style="--i: 2"><span class="step-icon"><Icon name="cart" size={20} /></span><span><strong>La liste de courses se fait toute seule</strong>, et chacun la voit cochée en direct.</span></li>
    </ol>

    <div class="actions">
      <button class="btn btn-primary" bind:this={primary} onclick={discover}>
        Découvrir l’appli <Icon name="arrow-right" size={18} />
      </button>
      <button class="btn btn-outline" onclick={closeForNow}>Fermer</button>
      <button class="never" onclick={neverAgain}>Ne plus afficher ce message</button>
    </div>
    <p class="hint">L’aide reste dans <strong>Mon compte</strong>.</p>
  </div>
</div>

<style>
  /* Plein écran, au-dessus de l'en-tête et de la barre d'onglets */
  .screen {
    position: fixed;
    inset: 0;
    z-index: 200;
    overflow-y: auto;
    overscroll-behavior: contain;
    background: var(--page);
    display: flex;
    justify-content: center;
    padding: calc(var(--sp-5) + env(safe-area-inset-top, 0px)) var(--gutter) calc(var(--sp-5) + env(safe-area-inset-bottom, 0px));
    animation: ui-fade var(--dur-base) var(--ease-out);
  }
  .content {
    width: 100%;
    max-width: 440px;
    margin: auto 0; /* centré verticalement s'il y a la place, sinon défile */
    display: grid;
    gap: var(--sp-4);
    animation: fade-up var(--dur-sheet) var(--ease-out) backwards;
  }
  .logo {
    width: 76px;
    height: 76px;
    display: grid;
    place-items: center;
    justify-self: center;
    background: var(--accent);
    color: var(--on-accent);
    border: var(--line-w) solid var(--line);
    box-shadow: var(--shadow-md);
    animation: snap-in var(--dur-sheet) var(--ease-snap) 80ms backwards;
  }
  h1 {
    font-size: var(--fs-2xl);
    line-height: 1.05;
    text-align: center;
  }
  .lead {
    text-align: center;
    color: var(--text-secondary);
    font-size: var(--fs-base);
    line-height: 1.45;
  }
  .steps {
    list-style: none;
    margin: var(--sp-1) 0 0;
    padding: var(--sp-4);
    display: grid;
    gap: var(--sp-4);
  }
  .steps li {
    display: flex;
    gap: var(--sp-3);
    align-items: flex-start;
    font-size: var(--fs-base);
    line-height: 1.4;
    animation: fade-up var(--dur-sheet) var(--ease-out) calc(var(--i, 0) * 45ms + 120ms) backwards;
  }
  .step-icon {
    width: 40px;
    height: 40px;
    display: grid;
    place-items: center;
    flex: none;
    background: var(--accent);
    color: var(--on-accent);
    border: var(--line-w) solid var(--line);
  }
  .actions { display: grid; gap: var(--sp-3); margin-top: var(--sp-1); }
  .actions .btn { min-height: 52px; width: 100%; }
  .never {
    min-height: 44px;
    background: none;
    border: none;
    color: var(--text);
    font: inherit;
    font-size: var(--fs-sm);
    font-weight: var(--fw-bold);
    text-decoration: underline;
    text-decoration-thickness: 2px;
    text-underline-offset: 3px;
    cursor: pointer;
    touch-action: manipulation;
  }
  .never:active { transform: translate(1px, 1px); }
  .hint { text-align: center; font-size: var(--fs-sm); color: var(--text-secondary); }

  @media (hover: hover) and (pointer: fine) {
    .never:hover { background: var(--highlight); }
  }
</style>
