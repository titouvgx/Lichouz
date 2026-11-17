<script lang="ts">
  // Boosters à thème (#/boosters, v2.5.0) : petits plus à côté du booster du
  // jour, rangés hors de la navigation principale (lien discret sur l'accueil).
  // Chaque thème s'ouvre une fois par jour ; ensuite ses 5 cartes restent
  // visibles jusqu'à minuit.
  import { onDestroy } from 'svelte'
  import Icon from '../components/Icon.svelte'
  import ErrorState from '../components/ErrorState.svelte'
  import BoosterPack from '../components/BoosterPack.svelte'
  import BoosterAura from '../components/BoosterAura.svelte'
  import BoosterArt from '../components/BoosterArt.svelte'
  import BoosterCard from '../components/BoosterCard.svelte'
  import { auth } from '../lib/auth.svelte'
  import { recordBoosterOpening } from '../lib/api/succes'
  import { checkAchievements } from '../lib/achievements.svelte'
  import { profileState } from '../lib/profile.svelte'
  import { href } from '../lib/router.svelte'
  import { fetchRecipeIndex, fetchRecipesByIds, todayKey, type RecipeIndexEntry } from '../lib/api/recipes'
  import { boosterOpenedToday, markBoosterOpened, drawBoosterIds, BOOSTER_SIZE } from '../lib/booster'
  import { availableThemes, type BoosterTheme } from '../lib/boosterThemes'
  import type { RecipeWithCategory } from '../lib/types'

  const reduceMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches
  const dateKey = todayKey()
  const userId = $derived(auth.user?.id ?? null)

  let index = $state<RecipeIndexEntry[]>([])
  let loading = $state(true)
  let loadError = $state<string | null>(null)

  const themes = $derived(availableThemes(index, new Date()))
  /** Thèmes déjà ouverts aujourd'hui (sur ce téléphone) */
  let opened = $state(new Set<string>())

  $effect(() => {
    fetchRecipeIndex()
      .then((r) => (index = r))
      .catch((e: any) => (loadError = e?.message ?? 'Chargement impossible'))
      .finally(() => (loading = false))
  })

  $effect(() => {
    const id = userId
    opened = new Set(themes.filter((t) => boosterOpenedToday(id, dateKey, t.theme.key)).map((t) => t.theme.key))
  })

  // ── Thème choisi ──
  let current = $state<{ theme: BoosterTheme; ids: string[] } | null>(null)
  let cards = $state<RecipeWithCategory[]>([])
  let drawing = $state(false)
  let drawError = $state<string | null>(null)
  /** 'ferme' : le paquet attend ; 'ouvert' : les cartes jaillissent ; 'direct' : cartes affichées */
  let stage = $state<'ferme' | 'ouvert' | 'direct'>('direct')
  let packGone = $state(false)
  let stageEl: HTMLElement | undefined = $state()
  let seq = 0

  async function choose(t: { theme: BoosterTheme; ids: string[] }) {
    const my = ++seq
    current = t
    cards = []
    drawError = null
    packGone = false
    stage = reduceMotion || opened.has(t.theme.key) ? 'direct' : 'ferme'
    drawing = true
    queueMicrotask(() => stageEl?.scrollIntoView({ behavior: reduceMotion ? 'auto' : 'smooth', block: 'start' }))
    try {
      const byId = new Map(index.map((r) => [r.id, r]))
      const ids = await drawBoosterIds(
        t.ids, profileState.profile?.family_id ?? null, dateKey, BOOSTER_SIZE, t.theme.key,
        t.theme.distinctOrigin ? (id) => byId.get(id)?.origin : undefined, userId,
      )
      const rows = await fetchRecipesByIds(ids)
      if (my === seq) cards = rows
    } catch (e: any) {
      if (my === seq) drawError = e?.message ?? 'Tirage impossible'
    } finally {
      if (my === seq) drawing = false
    }
  }

  function markOpened(key: string) {
    if (userId) {
      recordBoosterOpening(userId, key, dateKey, cards.map((r) => r.id))
        .then(() => checkAchievements(true))
        .catch(() => {})
    }
    markBoosterOpened(userId, dateKey, key)
    opened = new Set([...opened, key])
  }

  function openPack() {
    if (!current) return
    markOpened(current.theme.key)
    stage = 'ouvert'
  }

  function skipPack() {
    if (!current) return
    markOpened(current.theme.key)
    stage = 'direct'
  }

  // ── Aura (comme sur l'accueil) ──
  let aura = $state<{ x: number; y: number } | null>(null)
  let auraTimer: ReturnType<typeof setTimeout> | undefined
  function startAura(c: { x: number; y: number }) {
    aura = c
    clearTimeout(auraTimer)
    auraTimer = setTimeout(() => (aura = null), 1800)
  }
  onDestroy(() => clearTimeout(auraTimer))
</script>

<div class="page">
  <a href={href('accueil')} class="back-link"><Icon name="arrow-left" size={18} /> Accueil</a>

  <header class="head">
    <h1>Boosters</h1>
    <p class="head-sub">Un petit plus : chaque thème s’ouvre une fois par jour.</p>
  </header>

  {#if current}
    <section class="stage card" bind:this={stageEl} aria-label="Booster {current.theme.name}">
      <h2 class="band">{current.theme.name} <span class="band-sub">{current.theme.sub}</span></h2>
      {#if drawError}
        <div class="pad"><ErrorState error={drawError} message={drawError} /></div>
      {:else}
        <div class="arena">
        {#if stage === 'ferme' || (stage === 'ouvert' && !packGone)}
          <div class="pack-zone">
            <BoosterPack
              ready={!drawing && cards.length > 0}
              name={current.theme.name}
              sub={current.theme.sub}
              art={current.theme.art}
              tone={current.theme.tone}
              count={cards.length || BOOSTER_SIZE}
              onopen={openPack}
              ontear={startAura}
              ondone={() => (packGone = true)}
              onskip={skipPack}
            />
          </div>
        {/if}
        {#if stage !== 'ferme'}
          {#if drawing}
            <p class="muted pad" aria-busy="true">Tirage…</p>
          {:else}
            <div class="grid" class:over={stage === 'ouvert' && !packGone}>
              {#each cards as r, i (r.id)}
                <BoosterCard recipe={r} index={i} burst={stage === 'ouvert'} />
              {/each}
            </div>
          {/if}
        {/if}
        </div>
      {/if}
    </section>
  {/if}

  {#if loading}
    <p class="muted" aria-busy="true">Chargement…</p>
  {:else if loadError}
    <ErrorState error={loadError} message={loadError} />
  {:else if themes.length === 0}
    <p class="muted">Pas encore assez de recettes étiquetées pour les boosters à thème.</p>
  {:else}
    <ul class="shelf" aria-label="Boosters à thème">
      {#each themes as t, i (t.theme.key)}
        <li style:--i={i}>
          <button
            class="mini"
            class:active={current?.theme.key === t.theme.key}
            style:--tone={t.theme.tone}
            onclick={() => choose(t)}
          >
            <span class="mini-art"><BoosterArt art={t.theme.art} size={44} /></span>
            <span class="mini-name">{t.theme.name}</span>
            <span class="mini-state">
              {#if opened.has(t.theme.key)}<Icon name="check" size={13} /> Ouvert{:else}À ouvrir{/if}
            </span>
          </button>
        </li>
      {/each}
    </ul>
    <p class="muted small">Le tirage est le même pour tout ton foyer et change à minuit. Il évite ce que vous avez cuisiné ces 2 dernières semaines.</p>
  {/if}
</div>

{#if aura}
  <BoosterAura x={aura.x} y={aura.y} />
{/if}

<style>
  .page {
    padding: var(--gutter);
    padding-top: 0;
    max-width: 640px;
    margin: 0 auto;
    padding-bottom: calc(84px + env(safe-area-inset-bottom, 0px));
    display: flex;
    flex-direction: column;
    gap: var(--sp-4);
  }
  .back-link {
    display: inline-flex;
    align-items: center;
    align-self: flex-start;
    gap: 6px;
    min-height: 44px;
    margin-top: calc(8px + env(safe-area-inset-top, 0px));
    color: var(--text);
    font-weight: var(--fw-bold);
    text-decoration: underline;
    text-decoration-thickness: 2px;
    text-underline-offset: 3px;
    touch-action: manipulation;
  }
  .head h1 { padding-right: 56px; }
  .head-sub { margin-top: var(--sp-1); font-size: 15px; font-weight: var(--fw-medium); color: var(--text-secondary); }
  .muted { color: var(--text-secondary); }
  .small { font-size: 13px; }
  .pad { padding: var(--sp-3); }

  /* ── Étagère des thèmes : petits paquets en grille ── */
  .shelf {
    list-style: none;
    margin: 0;
    padding: 0;
    display: grid;
    grid-template-columns: repeat(3, minmax(0, 1fr));
    gap: var(--sp-3);
  }
  .shelf li { animation: fade-up var(--dur-sheet) var(--ease-out) calc(var(--i) * 50ms) backwards; }
  .mini {
    width: 100%;
    min-height: 132px;
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    gap: 4px;
    padding: var(--sp-2) 4px;
    background: var(--tone);
    color: var(--ink, var(--text));
    border: var(--line-w) solid var(--line);
    box-shadow: var(--shadow-sm);
    font: inherit;
    cursor: pointer;
    touch-action: manipulation;
    transition: transform var(--dur-fast) var(--ease-out);
  }
  .mini:active { transform: translate(var(--press), var(--press)); box-shadow: none; }
  .mini.active { box-shadow: var(--shadow-lg); transform: translate(-2px, -2px); }
  .mini-name { font-weight: var(--fw-bold); font-size: 13px; line-height: 1.1; text-transform: uppercase; text-align: center; }
  .mini-state {
    display: inline-flex;
    align-items: center;
    gap: 3px;
    padding: 1px 5px;
    background: var(--surface);
    border: var(--line-thin, 1px) solid var(--line);
    color: var(--text);
    font-size: 11px;
    font-weight: var(--fw-bold);
  }

  /* ── Scène du thème choisi ── */
  .stage { padding: 0 0 var(--sp-3); scroll-margin-top: 12px; }
  .stage h2.band { font-size: 13px; letter-spacing: var(--tracking-caps); justify-content: flex-start; }
  .band-sub { font-weight: var(--fw-medium); text-transform: none; letter-spacing: 0; opacity: 0.8; }
  .arena { position: relative; }
  .pack-zone { position: relative; height: 380px; }
  /* 3 par ligne, la 2e ligne centrée (5 cartes = 3 + 2) */
  .grid {
    position: relative;
    z-index: 1;
    display: flex;
    flex-wrap: wrap;
    justify-content: center;
    align-items: stretch;
    gap: var(--sp-4) var(--sp-3);
    padding: var(--sp-4) var(--sp-3) 0;
  }
  .grid > :global(*) { width: calc((100% - 2 * var(--sp-3)) / 3); }
  /* Pendant que le paquet descend, les cartes sortent PAR-DESSUS lui */
  .grid.over { position: absolute; inset: 0 0 auto 0; }
</style>
