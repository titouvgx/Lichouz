<script lang="ts">
  // Mes trophées (#/succes, v2.7.0) : niveau, points, trophées évolutifs avec
  // leur progression, trophées secrets (cachés tant qu'ils ne sont pas obtenus).
  // Tout est calculé par la base ; visible par soi seul.
  import Icon from '../components/Icon.svelte'
  import ErrorState from '../components/ErrorState.svelte'
  import TrophyMedal from '../components/TrophyMedal.svelte'
  import { href } from '../lib/router.svelte'
  import { fetchMyAchievements, type MyAchievements } from '../lib/api/succes'
  import { checkAchievements } from '../lib/achievements.svelte'
  import {
    ACHIEVEMENTS, TIER_LABEL, RARITY_LABEL, MAX_POINTS,
    bestTiers, levelOf, rarityOf, totalPoints, type Achievement,
  } from '../lib/succes'

  let data = $state<MyAchievements | null>(null)
  let loading = $state(true)
  let loadError = $state<string | null>(null)
  let filter = $state<'tous' | 'obtenus' | 'a_obtenir'>('tous')

  $effect(() => {
    void (async () => {
      try {
        await checkAchievements(true) // enregistre d'abord ce qui vient d'être atteint
        data = await fetchMyAchievements()
      } catch (e: any) {
        loadError = e?.message ?? 'Chargement impossible'
      } finally {
        loading = false
      }
    })()
  })

  const best = $derived(bestTiers(data?.unlocked ?? []))
  const points = $derived(totalPoints(data?.unlocked ?? []))
  const lvl = $derived(levelOf(points))
  const obtained = $derived(ACHIEVEMENTS.filter((a) => (best.get(a.key) ?? 0) > 0).length)
  const dates = $derived(new Map((data?.unlocked ?? []).map((u) => [`${u.achievement}:${u.tier}`, u.unlocked_at])))

  function visible(a: Achievement): boolean {
    const t = best.get(a.key) ?? 0
    if (filter === 'obtenus') return t > 0
    if (filter === 'a_obtenir') return t < a.tiers.length
    return true
  }
  const evolutifs = $derived(ACHIEVEMENTS.filter((a) => !a.secret && visible(a)))
  const secrets = $derived(ACHIEVEMENTS.filter((a) => a.secret && visible(a)))

  function value(a: Achievement): number {
    return Math.max(0, Number(data?.progress?.[a.key] ?? 0))
  }
  function fmt(n: number, unit?: string): string {
    if (unit === 'min') return n >= 60 ? `${Math.floor(n / 60)} h ${String(n % 60).padStart(2, '0')}` : `${n} min`
    return `${n.toLocaleString('fr-FR')}${unit ? ` ${unit}` : ''}`
  }
  function day(iso: string | undefined): string {
    return iso ? new Date(iso).toLocaleDateString('fr-FR', { day: 'numeric', month: 'short', year: 'numeric' }) : ''
  }
</script>

<div class="page">
  <a href={href('compte')} class="back-link"><Icon name="arrow-left" size={18} /> Mon compte</a>

  <header class="head">
    <h1>Mes trophées</h1>
    <p class="head-sub">Gagnés en cuisinant, en planifiant, en faisant les courses… Visibles par toi seul.</p>
  </header>

  {#if loading}
    <p class="muted" aria-busy="true">Chargement…</p>
  {:else if loadError}
    <ErrorState error={loadError} message={loadError} />
  {:else}
    <!-- Niveau -->
    <section class="level card" aria-label="Niveau">
      <div class="lv-badge"><span class="lv-small">Niv.</span><span class="lv-num">{lvl.level}</span></div>
      <div class="lv-main">
        <p class="lv-points"><strong>{points}</strong> points <span class="muted">· {obtained}/{ACHIEVEMENTS.length} trophées</span></p>
        <div class="bar" role="progressbar" aria-valuemin={lvl.current} aria-valuemax={lvl.next} aria-valuenow={points}
          aria-label="Vers le niveau {lvl.level + 1}">
          <span class="fill" style:transform="scaleX({Math.min(1, (points - lvl.current) / (lvl.next - lvl.current))})"></span>
        </div>
        <p class="lv-next muted">{lvl.next - points} points avant le niveau {lvl.level + 1} · {MAX_POINTS} au total</p>
      </div>
    </section>

    <div class="filters" role="group" aria-label="Afficher">
      <button class="chip" aria-pressed={filter === 'tous'} onclick={() => (filter = 'tous')}>Tous</button>
      <button class="chip" aria-pressed={filter === 'obtenus'} onclick={() => (filter = 'obtenus')}>Obtenus</button>
      <button class="chip" aria-pressed={filter === 'a_obtenir'} onclick={() => (filter = 'a_obtenir')}>À obtenir</button>
    </div>

    <!-- Évolutifs -->
    {#if evolutifs.length}
      <section class="group card" aria-labelledby="h-evo">
        <h2 id="h-evo" class="band">Évolutifs <span class="band-sub">Bronze · Argent · Or</span></h2>
        <ul>
          {#each evolutifs as a, i (a.key)}
            {@const t = best.get(a.key) ?? 0}
            {@const v = value(a)}
            {@const goal = a.tiers[Math.min(t, a.tiers.length - 1)]}
            {@const prev = t > 0 ? a.tiers[t - 1] : 0}
            {@const done = t >= a.tiers.length}
            <li class="evo" style:--i={Math.min(i, 8)}>
              <TrophyMedal achievement={a} tier={t} size={52} />
              <div class="evo-main">
                <p class="evo-name">{a.name} {#if t > 0}<span class="tier-tag" style:--medal="var(--rarity-{rarityOf(a, t)})">{TIER_LABEL[t - 1]}</span>{/if}</p>
                <p class="evo-desc">{a.desc}</p>
                <div class="bar small" aria-hidden="true">
                  <span class="fill" style:transform="scaleX({done ? 1 : Math.min(1, (v - prev) / Math.max(1, goal - prev))})"></span>
                </div>
                <p class="evo-count muted">
                  {#if done}Or obtenu{#if dates.get(`${a.key}:3`)} le {day(dates.get(`${a.key}:3`))}{/if} · {fmt(v, a.unit)}
                  {:else}{fmt(Math.min(v, goal), a.unit)} / {fmt(goal, a.unit)} → {TIER_LABEL[t]}{/if}
                </p>
              </div>
            </li>
          {/each}
        </ul>
      </section>
    {/if}

    <!-- Secrets -->
    {#if secrets.length}
      <section class="group card" aria-labelledby="h-sec">
        <h2 id="h-sec" class="band">Secrets <span class="band-sub">{secrets.filter((a) => best.has(a.key)).length} découverts</span></h2>
        <ul class="secret-grid">
          {#each secrets as a (a.key)}
            {@const got = best.has(a.key)}
            <li class="secret" class:got>
              <TrophyMedal achievement={a} tier={got ? 1 : 0} size={50} />
              <p class="s-name">{got ? a.name : '???'}</p>
              <p class="s-rarity" style:--medal="var(--rarity-{rarityOf(a, 1)})">{RARITY_LABEL[rarityOf(a, 1)]}</p>
              {#if got}
                <p class="s-desc">{a.desc}</p>
                <p class="s-date muted">{day(dates.get(`${a.key}:1`))}</p>
              {:else}
                <p class="s-desc muted">À découvrir…</p>
              {/if}
            </li>
          {/each}
        </ul>
      </section>
    {/if}

    <p class="muted small">Les trophées se calculent avec ce que tu fais dans Lichouz : un repas compte comme cuisiné quand son jour est passé et que « Qui cuisine ? » c’est toi.</p>
  {/if}
</div>

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
    display: inline-flex; align-items: center; align-self: flex-start; gap: 6px;
    min-height: 44px; margin-top: calc(8px + env(safe-area-inset-top, 0px));
    color: var(--text); font-weight: var(--fw-bold);
    text-decoration: underline; text-decoration-thickness: 2px; text-underline-offset: 3px;
    touch-action: manipulation;
  }
  .head h1 { padding-right: 56px; }
  .head-sub { margin-top: var(--sp-1); font-size: 15px; font-weight: var(--fw-medium); color: var(--text-secondary); }
  .muted { color: var(--text-secondary); }
  .small { font-size: 13px; }

  /* Niveau */
  .level { display: flex; align-items: center; gap: var(--sp-3); padding: var(--sp-3); }
  .lv-badge {
    flex: none; display: flex; flex-direction: column; align-items: center; justify-content: center;
    width: 72px; height: 72px;
    background: var(--accent); color: var(--on-accent);
    border: var(--line-w) solid var(--line); box-shadow: var(--shadow-md);
    transform: rotate(-4deg);
  }
  .lv-small { font-size: 11px; font-weight: var(--fw-bold); text-transform: uppercase; }
  .lv-num { font-size: 32px; font-weight: var(--fw-bold); line-height: 1; }
  .lv-main { flex: 1; min-width: 0; display: flex; flex-direction: column; gap: 6px; }
  .lv-points { font-size: 15px; }
  .lv-next { font-size: 12px; }
  .bar {
    position: relative; height: 14px; overflow: hidden;
    background: var(--surface); border: var(--line-w) solid var(--line);
  }
  .bar.small { height: 8px; }
  .fill {
    position: absolute; inset: 0;
    background: var(--accent);
    transform-origin: left center;
    transition: transform 0.8s var(--ease-out);
  }

  .filters { display: flex; gap: var(--sp-2); flex-wrap: wrap; }

  .group { padding: 0 0 var(--sp-1); }
  .group h2.band { font-size: 13px; letter-spacing: var(--tracking-caps); justify-content: flex-start; }
  .band-sub { font-weight: var(--fw-medium); text-transform: none; letter-spacing: 0; opacity: 0.8; }
  .group ul { list-style: none; margin: 0; padding: 0; }

  .evo {
    display: flex; align-items: center; gap: var(--sp-3);
    padding: var(--sp-3);
    border-top: var(--line-thin, 1px) solid var(--line);
    animation: fade-up var(--dur-sheet) var(--ease-out) calc(var(--i, 0) * 40ms) backwards;
  }
  .evo:first-child { border-top: none; }
  .evo-main { flex: 1; min-width: 0; display: flex; flex-direction: column; gap: 3px; }
  .evo-name { font-weight: var(--fw-bold); display: flex; align-items: center; gap: 6px; flex-wrap: wrap; }
  .tier-tag {
    padding: 0 5px; font-size: 11px; text-transform: uppercase; letter-spacing: var(--tracking-caps);
    background: var(--medal); color: var(--ink, var(--text)); border: var(--line-thin, 1px) solid var(--line);
  }
  .evo-desc { font-size: 13px; }
  .evo-count { font-size: 12px; }

  .secret-grid {
    display: grid !important;
    grid-template-columns: repeat(3, minmax(0, 1fr));
    gap: var(--sp-3) var(--sp-2);
    padding: var(--sp-3) !important;
  }
  .secret { display: flex; flex-direction: column; align-items: center; text-align: center; gap: 3px; min-width: 0; }
  .s-name { font-weight: var(--fw-bold); font-size: 13px; line-height: 1.15; margin-top: 4px; }
  .s-rarity {
    padding: 0 5px; font-size: 10px; font-weight: var(--fw-bold); text-transform: uppercase; letter-spacing: var(--tracking-caps);
    background: var(--medal); color: var(--ink, var(--text)); border: var(--line-thin, 1px) solid var(--line);
  }
  .s-desc { font-size: 11px; line-height: 1.25; overflow-wrap: anywhere; }
  .s-date { font-size: 10px; }
  .secret:not(.got) .s-name { letter-spacing: 0.2em; }
</style>
