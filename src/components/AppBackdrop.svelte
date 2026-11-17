<script lang="ts">
  // Fond de TOUTE l'appli (v1.9.0, « Brutal beurre ») : couleur unie + pluie
  // lente d'aliments au trait, très pâles. Monté une seule fois dans App.svelte.
  //
  // Pour rester fluide sur téléphone :
  //   - une douzaine d'aliments seulement, chacun sur sa propre couche (GPU) ;
  //   - seul `transform` est animé (aucun recalcul de mise en page) ;
  //   - pause quand l'appli n'est pas à l'écran (batterie) ;
  //   - « réduire les animations » : aliments posés, immobiles.
  import { onMount } from 'svelte'
  import { makeRain, NOEL_MOTIFS } from '../lib/motifs'
  import { theme } from '../lib/theme.svelte'

  // Un tirage par ouverture de l'appli (et par changement de thème) :
  // aliments en Classique, flocons, sapins, cadeaux… en Noël.
  const items = $derived(theme.name === 'noel' ? makeRain(12, Math.random, NOEL_MOTIFS) : makeRain(12))

  let paused = $state(false)

  onMount(() => {
    const onVisibility = () => { paused = document.visibilityState !== 'visible' }
    document.addEventListener('visibilitychange', onVisibility)
    return () => document.removeEventListener('visibilitychange', onVisibility)
  })
</script>

<div class="backdrop" class:paused aria-hidden="true">
  {#each items as it, i (i)}
    <span
      class="food"
      class:accent={it.accent}
      style:left="{it.x}%"
      style:--y="{it.y}%"
      style:--size="{it.size}px"
      style:--r0="{it.rotStart}deg"
      style:--r1="{it.rotEnd}deg"
      style:animation-duration="{it.duration}s"
      style:animation-delay="{it.delay}s"
    >
      <svg viewBox="0 0 24 24">{@html it.motif}</svg>
    </span>
  {/each}
</div>

<style>
  .backdrop {
    position: fixed;
    inset: 0;
    z-index: -1;
    overflow: hidden;
    background: var(--page);
    pointer-events: none;
    contain: strict;
  }

  .food {
    position: absolute;
    top: 0;
    width: var(--size);
    height: var(--size);
    color: var(--motif-color);
    opacity: var(--motif-opacity);
    will-change: transform;
    animation-name: fall;
    animation-timing-function: linear;
    animation-iteration-count: infinite;
  }

  .food.accent {
    color: var(--accent);
    opacity: var(--motif-accent-opacity);
  }

  .food svg {
    display: block;
    width: 100%;
    height: 100%;
    fill: none;
    stroke: currentColor;
    stroke-width: 2;
    stroke-linecap: square;
    stroke-linejoin: miter;
  }

  .paused .food { animation-play-state: paused; }

  /* De juste au-dessus de l'écran à juste en dessous, en tournant un peu */
  @keyframes fall {
    from { transform: translate3d(0, -60px, 0) rotate(var(--r0)); }
    to   { transform: translate3d(0, calc(100svh + 60px), 0) rotate(var(--r1)); }
  }

  /* Mouvement réduit : les aliments sont posés, immobiles */
  @media (prefers-reduced-motion: reduce) {
    .food {
      top: var(--y);
      animation: none !important;
      transform: rotate(var(--r0));
      will-change: auto;
    }
  }
</style>
