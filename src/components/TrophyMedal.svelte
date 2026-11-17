<script lang="ts">
  // Médaille d'un trophée (v2.7.0) : ruban + disque à la couleur de la rareté,
  // icône au centre. Pas obtenu : gris ; secret pas obtenu : cadenas.
  import Icon from './Icon.svelte'
  import { rarityOf, type Achievement } from '../lib/succes'

  let { achievement, tier = 0, size = 56, shine = false }: {
    achievement: Achievement
    /** Palier obtenu (0 = pas encore) */
    tier?: number
    size?: number
    /** Reflet qui passe (toast, trophée tout juste obtenu) */
    shine?: boolean
  } = $props()

  const locked = $derived(tier === 0)
  const color = $derived(locked ? 'var(--rarity-locked)' : `var(--rarity-${rarityOf(achievement, tier)})`)
  const hidden = $derived(locked && !!achievement.secret)
</script>

<span class="medal" class:locked class:shine style:--size="{size}px" style:--medal={color} aria-hidden="true">
  <span class="ribbon"><span class="r1"></span><span class="r2"></span></span>
  <span class="disc">
    <Icon name={hidden ? 'lock' : achievement.icon} size={Math.round(size * 0.42)} strokeWidth={2.2} />
    {#if !achievement.secret && tier > 0}
      <span class="tier">{'I'.repeat(tier)}</span>
    {/if}
  </span>
</span>

<style>
  .medal {
    position: relative;
    display: inline-block;
    flex: none;
    width: var(--size);
    height: calc(var(--size) * 1.18);
  }
  .ribbon { position: absolute; top: 0; left: 50%; width: calc(var(--size) * 0.6); height: calc(var(--size) * 0.5); transform: translateX(-50%); }
  .r1, .r2 {
    position: absolute;
    top: 0;
    width: 45%;
    height: 100%;
    background: var(--band);
    border: var(--line-w) solid var(--line);
  }
  .r1 { left: 0; transform: skewX(12deg); }
  .r2 { right: 0; transform: skewX(-12deg); }
  .disc {
    position: absolute;
    left: 0;
    bottom: 0;
    width: var(--size);
    height: var(--size);
    display: grid;
    place-items: center;
    overflow: hidden;
    border-radius: 50%;
    background: var(--medal);
    color: var(--ink, var(--text));
    border: var(--line-w) solid var(--line);
    box-shadow: var(--shadow-sm);
  }
  .locked .disc { color: var(--text-secondary); box-shadow: none; }
  .locked .r1, .locked .r2 { background: var(--rarity-locked); }
  .tier {
    position: absolute;
    bottom: 6%;
    font-size: calc(var(--size) * 0.17);
    font-weight: var(--fw-bold);
    letter-spacing: 0.08em;
    line-height: 1;
  }
  /* Reflet en biais qui traverse le disque */
  .shine .disc::after {
    content: '';
    position: absolute;
    inset: -20%;
    background: linear-gradient(110deg, transparent 35%, color-mix(in srgb, var(--surface) 85%, transparent) 50%, transparent 65%);
    transform: translateX(-120%);
    animation: medal-shine 1.4s ease-in-out 0.3s 2;
  }
  @keyframes medal-shine {
    to { transform: translateX(120%); }
  }
  @media (prefers-reduced-motion: reduce) {
    .shine .disc::after { animation: none; opacity: 0; }
  }
</style>
