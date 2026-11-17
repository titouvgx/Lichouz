<script lang="ts">
  // Dessins des paquets de boosters (v2.5.0) : traits noirs épais, aplats
  // blancs, dans le style « Brutal beurre ». Un dessin par thème.
  import type { BoosterArtKey } from '../lib/boosterThemes'

  let { art, size = 76 }: { art: BoosterArtKey; size?: number } = $props()
</script>

<svg
  class="art"
  width={size}
  height={size}
  viewBox="0 0 96 96"
  fill="none"
  stroke="currentColor"
  stroke-width="4"
  stroke-linecap="square"
  stroke-linejoin="miter"
  aria-hidden="true"
>
  {#if art === 'jour'}
    <!-- Soleil : le cadeau du jour -->
    <circle cx="48" cy="48" r="18" class="fill" />
    <path d="M48 8v12M48 76v12M8 48h12M76 48h12M20 20l9 9M67 67l9 9M76 20l-9 9M29 67l-9 9" />
    <path d="M41 46h2M53 46h2M41 54q7 6 14 0" stroke-width="3" />
  {:else if art === 'express'}
    <!-- Chrono avec traits de vitesse -->
    <circle cx="54" cy="52" r="28" class="fill" />
    <path d="M48 16h12M54 16v8M54 52V36M54 52l10 8" />
    <path d="M6 40h12M2 52h14M6 64h12" />
  {:else if art === 'budget'}
    <!-- Tirelire et pièce -->
    <path d="M18 50q0-22 30-22t30 22q0 12-10 18v12H56v-8H40v8H28V68q-10-6-10-18z" class="fill" />
    <path d="M78 46h8v10h-6M30 44h2M40 32h16" />
    <circle cx="48" cy="12" r="8" class="fill" />
    <path d="M48 8v8" stroke-width="3" />
  {:else if art === 'monde'}
    <!-- Globe -->
    <circle cx="48" cy="48" r="36" class="fill" />
    <ellipse cx="48" cy="48" rx="15" ry="36" />
    <path d="M12 48h72M18 30h60M18 66h60" />
  {:else if art === 'vert'}
    <!-- Feuille -->
    <path d="M18 78Q14 22 80 16q2 62-62 62z" class="fill" />
    <path d="M18 78L64 32M38 58V44M50 46h14" />
  {:else if art === 'reconfort'}
    <!-- Bol fumant -->
    <path d="M12 48h72q0 30-36 30T12 48z" class="fill" />
    <path d="M30 86h36" />
    <path d="M34 38q-6-8 0-16t0-16M48 38q-6-8 0-16t0-16M62 38q-6-8 0-16t0-16" stroke-width="3" />
  {:else if art === 'enfants'}
    <!-- Sucette tourbillon -->
    <circle cx="44" cy="40" r="28" class="fill" />
    <path d="M44 40m-6 0a6 6 0 1 1 12 0a12 12 0 1 1-24 0a18 18 0 1 1 36 0" stroke-width="3" />
    <path d="M64 60l22 26" />
  {:else if art === 'fetes'}
    <!-- Sapin et étoile -->
    <path d="M48 20L20 58h14L18 80h60L62 58h14z" class="fill" />
    <path d="M44 80v10h8V80" />
    <path d="M48 2l3 7 7 1-5 5 1 7-6-3-6 3 1-7-5-5 7-1z" class="fill" stroke-width="2.5" />
    <path d="M36 60h4M56 66h4M46 46h4" />
  {/if}
</svg>

<style>
  .art { display: block; color: var(--line); }
  .fill { fill: var(--surface); }
</style>
