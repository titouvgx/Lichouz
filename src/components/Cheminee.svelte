<script lang="ts">
  // Cheminée de Noël (v1.99.3), affichée sur l'Accueil quand le thème « Noël » est actif.
  // Dessin au trait carré (même esprit que les icônes), flammes qui crépitent :
  // seuls `transform` et `opacity` bougent ; « réduire les animations » → flammes fixes.
  // Pause quand l'appli n'est pas à l'écran (batterie).
  import { onMount } from 'svelte'

  let { size = 56 }: { size?: number } = $props()

  let paused = $state(false)
  onMount(() => {
    const onVisibility = () => { paused = document.visibilityState !== 'visible' }
    document.addEventListener('visibilitychange', onVisibility)
    return () => document.removeEventListener('visibilitychange', onVisibility)
  })
</script>

<div class="cheminee" class:paused aria-hidden="true">
  <svg viewBox="0 0 64 64" width={size} height={size}>
    <!-- guirlande et lueur (visibles surtout en grand) -->
    <path class="trait fin" d="M4 14c6 5 12 5 18 0 6 5 12 5 20 0 6 5 12 5 18 0" />
    <circle class="boule b1" cx="13" cy="17.5" r="1.6" /><circle class="boule b2" cx="32" cy="17.5" r="1.6" /><circle class="boule b3" cx="51" cy="17.5" r="1.6" />
    <ellipse class="lueur" cx="32" cy="52" rx="13" ry="8" />
    <!-- manteau et briques -->
    <path class="trait" d="M4 14h56v6H4zM8 20h48v40H8z" />
    <path class="trait fin" d="M8 30h10M46 30h10M8 40h10M46 40h10M8 50h10M46 50h10M13 20v10M51 20v10M13 40v10M51 40v10" />
    <!-- foyer -->
    <path class="foyer" d="M18 60V34a14 10 0 0 1 28 0v26z" />
    <!-- bûches -->
    <path class="trait" d="M21 57l22-5M21 52l22 5" />
    <!-- flammes -->
    <path class="flamme f1" d="M32 54c-7 0-8-7-4-12 0 3 2 4 3 4-1-5 2-10 6-12-2 5 3 8 3 13 0 4-3 7-8 7z" />
    <path class="flamme f2" d="M32 54c-4 0-5-4-2-8 0 2 1 3 2 3 0-3 1-5 3-6-1 3 2 5 2 8 0 2-2 3-5 3z" />
    <!-- chaussette -->
    <path class="chaussette" d="M44 20v8l4 3a3 3 0 0 1-4 4l-6-5v-10z" />
    <path class="trait fin" d="M38 20h6" />
  </svg>
</div>

<style>
  .cheminee {
    color: var(--line);
    line-height: 0;
  }

  svg { display: block; overflow: visible; }

  .trait {
    fill: none;
    stroke: currentColor;
    stroke-width: 2;
    stroke-linecap: square;
    stroke-linejoin: miter;
  }
  .trait.fin { stroke-width: 1; }

  .foyer { fill: var(--ink); stroke: currentColor; stroke-width: 2; }

  .chaussette { fill: var(--accent); stroke: currentColor; stroke-width: 2; stroke-linejoin: miter; }

  .flamme {
    transform-box: fill-box;
    transform-origin: 50% 100%;
    will-change: transform, opacity;
    animation: crepite 1.6s var(--ease-out) infinite alternate;
  }
  .f1 { fill: var(--accent); }
  .f2 { fill: var(--highlight); animation-duration: 1.1s; animation-delay: -0.4s; }

  .boule { fill: var(--highlight); stroke: currentColor; stroke-width: 0.8; }
  .b2 { fill: var(--accent); }

  /* Lueur du feu : pulse doucement (opacité seulement) */
  .lueur {
    fill: var(--highlight);
    opacity: 0.35;
    animation: lueur 2.4s ease-in-out infinite alternate;
  }
  @keyframes lueur { from { opacity: 0.2; } to { opacity: 0.45; } }

  .paused .flamme, .paused .lueur { animation-play-state: paused; }

  @keyframes crepite {
    0%   { transform: scale(1, 1);       opacity: 1; }
    35%  { transform: scale(0.94, 1.08); opacity: 0.9; }
    70%  { transform: scale(1.04, 0.93); opacity: 1; }
    100% { transform: scale(0.97, 1.05); opacity: 0.92; }
  }

  @media (prefers-reduced-motion: reduce) {
    .flamme, .lueur { animation: none; }
  }
</style>
