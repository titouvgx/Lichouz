<script lang="ts">
  // Aura d'ouverture du booster (v2.4.1) : un halo doux part du paquet et
  // envahit tout l'écran, avec quelques étincelles qui scintillent, ~1,4 s.
  // Purement décoratif : rien de cliquable, jamais au-dessus des fenêtres
  // (z-index 150 < .ui-overlay 200). Seuls transform et opacity bougent.
  // L'accueil ne l'affiche jamais en « mouvement réduit ».
  import { seededRandom } from '../lib/random'

  /** Centre du halo, en px dans la fenêtre (le paquet) */
  let { x, y }: { x: number; y: number } = $props()

  // Étincelles : mêmes positions à chaque fois (tirage fixe), réparties sur l'écran
  const rand = seededRandom('lichouz:aura')
  const sparks = Array.from({ length: 16 }, (_, i) => ({
    left: 4 + rand() * 92,
    top: 6 + rand() * 82,
    size: 10 + Math.round(rand() * 14),
    delay: Math.round(80 + i * 45 + rand() * 120),
  }))
</script>

<div class="aura" aria-hidden="true">
  <span class="halo" style:left="{x}px" style:top="{y}px"></span>
  <span class="veil"></span>
  {#each sparks as s, i (i)}
    <svg
      class="spark"
      style:left="{s.left}%"
      style:top="{s.top}%"
      style:--d="{s.delay}ms"
      width={s.size}
      height={s.size}
      viewBox="0 0 24 24"
    >
      <path d="M12 0c1 7 5 11 12 12-7 1-11 5-12 12-1-7-5-11-12-12 7-1 11-5 12-12z" />
    </svg>
  {/each}
</div>

<style>
  .aura {
    position: fixed;
    inset: 0;
    z-index: 150; /* au-dessus de la barre d'onglets (100), sous les fenêtres (200) */
    pointer-events: none;
    overflow: hidden;
  }

  /* Halo : grand disque flou qui grandit depuis le paquet puis s'efface */
  .halo {
    position: absolute;
    width: 140vmax;
    height: 140vmax;
    margin: -70vmax 0 0 -70vmax;
    border-radius: 50%;
    background: radial-gradient(
      circle,
      color-mix(in srgb, var(--surface) 75%, transparent) 0%,
      color-mix(in srgb, var(--accent) 30%, transparent) 30%,
      transparent 62%
    );
    opacity: 0;
    transform: scale(0.1);
    animation: halo 1.3s var(--ease-out) forwards;
  }

  /* Voile très léger sur tout l'écran : un « flash » doux */
  .veil {
    position: absolute;
    inset: 0;
    background: var(--surface);
    opacity: 0;
    animation: veil 0.9s ease-out forwards;
  }

  .spark {
    position: absolute;
    fill: var(--surface);
    stroke: var(--accent);
    stroke-width: 1;
    opacity: 0;
    transform: scale(0) rotate(0deg);
    animation: twinkle 0.9s ease-in-out var(--d) forwards;
  }

  @keyframes halo {
    0%   { opacity: 0; transform: scale(0.1); }
    25%  { opacity: 0.9; }
    100% { opacity: 0; transform: scale(1); }
  }
  @keyframes veil {
    0%   { opacity: 0; }
    20%  { opacity: 0.18; }
    100% { opacity: 0; }
  }
  @keyframes twinkle {
    0%   { opacity: 0; transform: scale(0) rotate(0deg); }
    45%  { opacity: 1; transform: scale(1) rotate(45deg); }
    100% { opacity: 0; transform: scale(0.3) rotate(90deg); }
  }

  @media (prefers-reduced-motion: reduce) {
    .aura { display: none; }
  }
</style>
