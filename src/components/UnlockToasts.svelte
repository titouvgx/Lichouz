<script lang="ts">
  // Toast « Trophée débloqué » (v2.7.0) : glisse depuis le haut, médaille qui
  // brille, reste 5 s ; toucher → page Mes trophées. Un seul affiché à la fois
  // (les suivants attendent leur tour). Annoncé aux lecteurs d'écran.
  import TrophyMedal from './TrophyMedal.svelte'
  import { unlockQueue, dismissUnlock } from '../lib/achievements.svelte'
  import { RARITY_LABEL, rarityOf, pointsOf, unlockTitle } from '../lib/succes'
  import { href } from '../lib/router.svelte'

  const current = $derived(unlockQueue.items[0] ?? null)
  const SHOW_MS = 5000

  $effect(() => {
    const t = current
    if (!t) return
    navigator.vibrate?.([20, 40, 20])
    const timer = setTimeout(() => dismissUnlock(t.id), SHOW_MS)
    return () => clearTimeout(timer)
  })
</script>

<div class="zone" aria-live="polite">
  {#if current}
    {#key current.id}
      {@const r = rarityOf(current.achievement, current.tier)}
      <a
        class="unlock"
        href={href('succes')}
        style:--medal="var(--rarity-{r})"
        onclick={() => dismissUnlock(current.id)}
      >
        <TrophyMedal achievement={current.achievement} tier={current.tier} size={46} shine />
        <span class="txt">
          <span class="kicker">Trophée débloqué · {RARITY_LABEL[r]}</span>
          <strong class="name">{unlockTitle(current.achievement, current.tier)}</strong>
          <span class="desc">{current.achievement.desc} · +{pointsOf(current.achievement, current.tier)} pts</span>
        </span>
      </a>
    {/key}
  {/if}
</div>

<style>
  .zone {
    position: fixed;
    top: calc(10px + env(safe-area-inset-top, 0px));
    left: 0;
    right: 0;
    z-index: 190; /* au-dessus de la barre d'onglets, sous les fenêtres (200) */
    display: flex;
    justify-content: center;
    padding: 0 var(--gutter);
    pointer-events: none;
  }
  .unlock {
    pointer-events: auto;
    display: flex;
    align-items: center;
    gap: var(--sp-3);
    width: 100%;
    max-width: 420px;
    padding: var(--sp-2) var(--sp-3);
    background: var(--surface);
    color: var(--text);
    text-decoration: none;
    border: var(--line-w) solid var(--line);
    border-left: 10px solid var(--medal);
    box-shadow: var(--shadow-lg);
    animation: drop 0.5s var(--ease-snap) both;
    touch-action: manipulation;
  }
  .txt { display: flex; flex-direction: column; min-width: 0; gap: 1px; }
  .kicker { font-size: 11px; font-weight: var(--fw-bold); text-transform: uppercase; letter-spacing: var(--tracking-caps); color: var(--text-secondary); }
  .name { font-size: 16px; line-height: 1.15; }
  .desc { font-size: 12px; color: var(--text-secondary); overflow-wrap: anywhere; }
  @keyframes drop {
    from { opacity: 0; transform: translate3d(0, -120%, 0) rotate(-2deg); }
  }
</style>
