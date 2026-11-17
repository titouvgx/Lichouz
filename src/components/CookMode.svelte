<script lang="ts">
  // Mode « En cuisine » : une étape à la fois, en très gros, plein écran.
  // - Précédent / Suivant (boutons larges, flèches du clavier, balayage au doigt)
  // - Rappel des ingrédients (panneau qui se déplie, quantités à l'échelle des portions choisies)
  // - Écran gardé allumé (Screen Wake Lock) tant que le mode est ouvert, si le navigateur le permet
  // - Minuteurs (v1.99.0) : les durées écrites dans l'étape (« cuire 25 min ») deviennent
  //   des boutons ; à la fin : sonnerie, vibration (Android) et bandeau orange.
  //   Les minuteurs vivent tant que le mode En cuisine est ouvert.
  import { onMount, onDestroy, untrack } from 'svelte'
  import { auth } from '../lib/auth.svelte'
  import { recordCookSession } from '../lib/api/succes'
  import { checkAchievements } from '../lib/achievements.svelte'
  import Icon from './Icon.svelte'
  import { formatIngredient } from '../lib/quantities'
  import { clockLabel, findDurations, type FoundDuration } from '../lib/timers'
  import type { RecipeDetail } from '../lib/types'

  interface Props {
    recipe: RecipeDetail
    /** Portions choisies sur la fiche (les quantités du rappel suivent) */
    portions: number
    /** Étape affichée à l'ouverture (index à partir de 0) */
    start?: number
    onclose: () => void
  }
  let { recipe, portions, start = 0, onclose }: Props = $props()

  const steps = $derived(recipe.recipe_steps)
  const scale = $derived(portions / (recipe.default_portions || portions || 1))

  // La vue est recréée à chaque ouverture : on lit volontairement la valeur de départ.
  let index = $state(untrack(() => Math.min(Math.max(start, 0), Math.max(recipe.recipe_steps.length - 1, 0))))
  /** Sens du dernier changement d'étape (pour l'animation d'entrée) */
  let dir = $state<1 | -1>(1)
  let showIngredients = $state(false)
  let dialogEl: HTMLDivElement | undefined = $state()

  const isFirst = $derived(index === 0)
  const isLast = $derived(index >= steps.length - 1)

  function go(delta: 1 | -1) {
    const next = index + delta
    if (next < 0 || next >= steps.length) return
    dir = delta
    index = next
  }

  // ── Minuteurs ──
  interface RunningTimer { id: number; label: string; step: number; endsAt: number; done: boolean }
  let timers = $state<RunningTimer[]>([])
  let now = $state(Date.now())
  let timerSeq = 0
  // Poignées hors rendu (pas en $state)
  let ticker: ReturnType<typeof setInterval> | undefined
  let audio: AudioContext | null = null

  const stepDurations = $derived<FoundDuration[]>(steps.length > 0 ? findDurations(steps[index].instruction) : [])

  function startTimer(d: FoundDuration) {
    // Le son doit être « débloqué » par un geste : on prépare le lecteur ici
    try {
      audio ??= new (window.AudioContext || (window as any).webkitAudioContext)()
      void audio.resume()
    } catch { audio = null }
    timers = [...timers, { id: ++timerSeq, label: d.label, step: index + 1, endsAt: Date.now() + d.seconds * 1000, done: false }]
    now = Date.now()
    ticker ??= setInterval(tick, 250)
  }

  function stopTimer(id: number) {
    timers = timers.filter((t) => t.id !== id)
    if (timers.length === 0 && ticker) { clearInterval(ticker); ticker = undefined }
  }

  function tick() {
    now = Date.now()
    let rang = false
    timers = timers.map((t) => {
      if (!t.done && t.endsAt <= now) { rang = true; return { ...t, done: true } }
      return t
    })
    if (rang) ring()
  }

  /** Trois bips courts + vibration (Android ; Safari iPhone ignore la vibration). */
  function ring() {
    try { navigator.vibrate?.([300, 150, 300, 150, 600]) } catch { /* rien */ }
    if (!audio) return
    try {
      const t0 = audio.currentTime
      for (let i = 0; i < 3; i++) {
        const osc = audio.createOscillator()
        const gain = audio.createGain()
        osc.type = 'square'
        osc.frequency.value = 880
        gain.gain.setValueAtTime(0.0001, t0 + i * 0.35)
        gain.gain.exponentialRampToValueAtTime(0.25, t0 + i * 0.35 + 0.02)
        gain.gain.exponentialRampToValueAtTime(0.0001, t0 + i * 0.35 + 0.25)
        osc.connect(gain).connect(audio.destination)
        osc.start(t0 + i * 0.35)
        osc.stop(t0 + i * 0.35 + 0.26)
      }
    } catch { /* son indisponible : la vibration et le bandeau suffisent */ }
  }

  // ── Garder l'écran allumé ──
  // Volontairement PAS en $state : simple poignée, lue et écrite hors du rendu.
  let wakeLock: WakeLockSentinel | null = null
  let closed = false

  async function acquireWakeLock() {
    if (closed || wakeLock || document.visibilityState !== 'visible') return
    if (!('wakeLock' in navigator)) return // repli silencieux (navigateur trop ancien)
    try {
      const lock = await navigator.wakeLock.request('screen')
      if (closed) { lock.release().catch(() => {}); return }
      wakeLock = lock
      // Le navigateur relâche le verrou tout seul quand l'onglet passe en arrière-plan
      lock.addEventListener('release', () => { if (wakeLock === lock) wakeLock = null })
    } catch {
      // Refusé (économie d'énergie, iframe, contexte non sécurisé…) : on ne dit rien
    }
  }

  function onVisibility() {
    if (document.visibilityState === 'visible') acquireWakeLock()
  }

  // ── Balayage gauche / droite ──
  let swipe: { id: number; x: number; y: number } | null = null
  function onPointerDown(e: PointerEvent) {
    if (e.pointerType === 'mouse') return // à la souris, on a les boutons et le clavier
    swipe = { id: e.pointerId, x: e.clientX, y: e.clientY }
  }
  function onPointerUp(e: PointerEvent) {
    if (!swipe || swipe.id !== e.pointerId) return
    const dx = e.clientX - swipe.x
    const dy = e.clientY - swipe.y
    swipe = null
    // Geste franchement horizontal uniquement (sinon c'est un défilement vertical)
    if (Math.abs(dx) > 60 && Math.abs(dx) > Math.abs(dy) * 1.5) go(dx < 0 ? 1 : -1)
  }

  function onKeydown(e: KeyboardEvent) {
    if (e.key === 'Escape') {
      e.preventDefault()
      if (showIngredients) showIngredients = false
      else onclose()
    } else if (e.key === 'ArrowRight') {
      go(1)
    } else if (e.key === 'ArrowLeft') {
      go(-1)
    }
  }

  // Toque d'or (v2.7.0) : durée passée en mode cuisine, enregistrée à la fermeture
  const openedAt = new Date()

  let previousFocus: HTMLElement | null = null
  onMount(() => {
    previousFocus = document.activeElement as HTMLElement | null
    document.body.style.overflow = 'hidden' // la page derrière ne défile plus
    document.addEventListener('visibilitychange', onVisibility)
    acquireWakeLock()
    dialogEl?.focus()
  })
  onDestroy(() => {
    if (ticker) clearInterval(ticker)
    audio?.close().catch(() => {})
    closed = true
    document.body.style.overflow = ''
    document.removeEventListener('visibilitychange', onVisibility)
    wakeLock?.release().catch(() => {})
    wakeLock = null
    previousFocus?.focus?.()
    const uid = auth.user?.id
    if (uid) {
      recordCookSession(uid, recipe.id, openedAt)
        .then(() => checkAchievements(true))
        .catch(() => { /* hors connexion : tant pis pour cette séance */ })
    }
  })
</script>

<svelte:window onkeydown={onKeydown} />

<div
  class="cook"
  bind:this={dialogEl}
  role="dialog"
  aria-modal="true"
  aria-labelledby="cook-title"
  tabindex="-1"
>
  <header class="cook-top">
    <button class="btn btn-icon round" onclick={onclose} aria-label="Fermer le mode cuisine">
      <Icon name="x" size={22} />
    </button>
    <div class="cook-heading">
      <span class="cook-kicker"><Icon name="chef" size={14} /> En cuisine</span>
      <h2 id="cook-title" class="cook-title">{recipe.title}</h2>
    </div>
    {#if recipe.recipe_ingredients.length > 0}
      <button
        class="btn btn-sm pill"
        class:on={showIngredients}
        onclick={() => (showIngredients = !showIngredients)}
        aria-expanded={showIngredients}
        aria-controls="cook-ingredients"
      >
        <Icon name="list" size={18} /> Ingrédients
      </button>
    {/if}
  </header>

  {#if steps.length > 0}
    <!-- Barre de progression : un segment par étape -->
    <div class="progress" aria-hidden="true">
      {#each steps as s, i (s.id)}
        <span class="seg" class:done={i < index} class:current={i === index}></span>
      {/each}
    </div>

    {#if timers.length > 0}
      <ul class="timers" aria-label="Minuteurs en cours">
        {#each timers as t (t.id)}
          <li class="timer" class:done={t.done} role={t.done ? 'alert' : undefined}>
            <Icon name="clock" size={18} />
            <span class="timer-text">
              {#if t.done}<strong>C’est prêt !</strong>{:else}<strong class="timer-clock">{clockLabel((t.endsAt - now) / 1000)}</strong>{/if}
              <small>Étape {t.step} · {t.label}</small>
            </span>
            <button class="btn btn-sm timer-stop" onclick={() => stopTimer(t.id)} aria-label={t.done ? `Arrêter le minuteur de l’étape ${t.step}` : `Annuler le minuteur de l’étape ${t.step}`}>
              {t.done ? 'OK' : 'Annuler'}
            </button>
          </li>
        {/each}
      </ul>
    {/if}

    <!-- svelte-ignore a11y_no_static_element_interactions -->
    <div
      class="stage"
      onpointerdown={onPointerDown}
      onpointerup={onPointerUp}
      onpointercancel={() => (swipe = null)}
    >
      {#key index}
        <div class="step" class:back={dir === -1} aria-live="polite">
          <p class="step-count">Étape {index + 1} sur {steps.length}</p>
          <p class="step-text">{steps[index].instruction}</p>
        </div>
      {/key}
    </div>

    {#if stepDurations.length > 0}
      <div class="timer-starts">
        {#each stepDurations as d (d.seconds)}
          <button class="btn btn-outline timer-start" onclick={() => startTimer(d)}>
            <Icon name="clock" size={18} /> Minuteur {d.label}
          </button>
        {/each}
      </div>
    {/if}

    <nav class="cook-nav" aria-label="Étapes">
      <button class="btn btn-outline nav-btn prev" onclick={() => go(-1)} disabled={isFirst}>
        <Icon name="arrow-left" size={22} /> Précédent
      </button>
      {#if isLast}
        <button class="btn btn-primary nav-btn next finish" onclick={onclose}>
          <Icon name="check" size={22} /> Terminé
        </button>
      {:else}
        <button class="btn btn-primary nav-btn next" onclick={() => go(1)}>
          Suivant <Icon name="arrow-right" size={22} />
        </button>
      {/if}
    </nav>
  {:else}
    <div class="stage empty"><p>Cette recette n'a pas encore d'étapes.</p></div>
  {/if}

  {#if showIngredients}
    <!-- svelte-ignore a11y_click_events_have_key_events -->
    <!-- svelte-ignore a11y_no_static_element_interactions -->
    <div class="ui-overlay" onclick={() => (showIngredients = false)}>
    <!-- svelte-ignore a11y_click_events_have_key_events -->
    <!-- svelte-ignore a11y_no_noninteractive_element_interactions -->
    <section
      id="cook-ingredients"
      class="ui-sheet sheet"
      aria-label="Ingrédients pour {portions} portions"
      onclick={(e) => e.stopPropagation()}
    >
      <div class="sheet-head">
        <h3>Ingrédients <span class="sheet-sub">· {portions} portion{portions > 1 ? 's' : ''}</span></h3>
        <button class="btn btn-icon round small" onclick={() => (showIngredients = false)} aria-label="Masquer les ingrédients">
          <Icon name="chevron-down" size={20} />
        </button>
      </div>
      <ul class="sheet-list">
        {#each recipe.recipe_ingredients as ing, i (ing.id)}
          {@const qty = formatIngredient(ing.quantity, ing.unit, scale)}
          <li style="--i: {Math.min(i, 8)}">
            <span class="sheet-qty">{qty}</span>
            <span class="sheet-name">{ing.name}</span>
          </li>
        {/each}
      </ul>
    </section>
    </div>
  {/if}
</div>

<style>
  .cook {
    position: fixed;
    inset: 0;
    z-index: 200; /* au-dessus de la barre d'onglets (100) */
    display: flex;
    flex-direction: column;
    /* Opaque : on cuisine, le fond animé n'apporte rien et gêne la lecture */
    background: var(--bg);
    color: var(--text);
    padding:
      calc(12px + env(safe-area-inset-top, 0px))
      calc(16px + env(safe-area-inset-right, 0px))
      calc(16px + env(safe-area-inset-bottom, 0px))
      calc(16px + env(safe-area-inset-left, 0px));
    outline: none;
    animation: cook-in var(--dur-sheet) var(--ease-out);
    overscroll-behavior: contain;
  }

  @keyframes cook-in {
    from { opacity: 0; transform: translateY(16px); }
    to   { opacity: 1; transform: none; }
  }

  /* ── En-tête ── */
  .cook-top {
    display: flex;
    align-items: center;
    gap: var(--sp-3);
  }

  .round { width: 48px; height: 48px; min-height: 48px; }
  .round.small { width: 44px; height: 44px; min-height: 44px; }

  .cook-heading {
    flex: 1;
    min-width: 0;
  }

  .cook-kicker {
    display: inline-flex;
    align-items: center;
    gap: 5px;
    font-size: 12px;
    font-weight: var(--fw-bold);
    letter-spacing: var(--tracking-caps);
    text-transform: uppercase;
    color: var(--text-secondary);
  }

  .cook-title {
    font-family: var(--font-display);
    font-size: 17px;
    font-weight: var(--fw-bold);
    line-height: 1.2;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }

  .pill { flex-shrink: 0; }

  .pill.on {
    background: var(--accent);
    color: var(--on-accent);
  }

  /* ── Progression : un carré plat par étape ── */
  .progress {
    display: flex;
    gap: var(--sp-1);
    margin: var(--sp-4) 0 0;
  }

  .seg {
    flex: 1;
    height: 10px;
    border: var(--line-thin) solid var(--line);
    background: var(--surface-sunken);
  }

  .seg.done { background: var(--band); }
  .seg.current { background: var(--accent); }

  /* ── Étape ── */
  .stage {
    flex: 1;
    min-height: 0;
    overflow-y: auto; /* les très longues étapes défilent */
    display: flex;
    touch-action: pan-y; /* le balayage horizontal est pour nous */
    -webkit-overflow-scrolling: touch;
  }

  .stage.empty {
    align-items: center;
    justify-content: center;
    color: var(--text-secondary);
  }

  .step {
    margin: auto 0; /* centré verticalement, mais défile proprement si trop long */
    width: 100%;
    max-width: 760px;
    margin-inline: auto;
    padding: var(--sp-5) var(--sp-1);
    animation: step-in var(--dur-sheet) var(--ease-out);
  }

  .step.back { animation-name: step-in-back; }

  @keyframes step-in {
    from { opacity: 0; transform: translateX(24px); }
    to   { opacity: 1; transform: none; }
  }

  @keyframes step-in-back {
    from { opacity: 0; transform: translateX(-24px); }
    to   { opacity: 1; transform: none; }
  }

  /* « Étape 2 sur 3 » : petit bandeau */
  .step-count {
    display: inline-block;
    padding: 4px 10px;
    margin-bottom: var(--sp-4);
    background: var(--band);
    color: var(--text-on-band);
    font-size: 13px;
    font-weight: var(--fw-bold);
    letter-spacing: var(--tracking-caps);
    text-transform: uppercase;
  }

  .step-text {
    font-family: var(--font-display);
    font-size: clamp(26px, 7.2vw, 40px);
    font-weight: var(--fw-medium);
    line-height: 1.38;
    color: var(--text);
    overflow-wrap: break-word; /* pas de césure : un mot coupé se lit mal d'un coup d'œil */
  }

  /* ── Navigation ── */
  /* ── Minuteurs ── */
  .timers {
    list-style: none;
    margin: 0;
    padding: var(--sp-2) var(--gutter) 0;
    display: flex;
    flex-direction: column;
    gap: var(--sp-2);
  }
  .timer {
    display: flex;
    align-items: center;
    gap: var(--sp-3);
    min-height: 52px;
    padding: 4px 6px 4px var(--sp-3);
    border: var(--line-w) solid var(--line);
    background: var(--surface);
    box-shadow: var(--shadow-sm);
  }
  .timer.done {
    background: var(--accent);
    color: var(--on-accent);
    animation: timer-shake 0.5s var(--ease-snap) 3;
  }
  @keyframes timer-shake {
    25% { transform: translateX(-4px); }
    75% { transform: translateX(4px); }
  }
  .timer-text { flex: 1; min-width: 0; display: flex; flex-direction: column; line-height: 1.15; }
  .timer-clock { font-size: var(--fs-xl); font-variant-numeric: tabular-nums; }
  .timer-text small { font-size: 12px; }
  .timer-stop { flex: none; }

  .timer-starts {
    display: flex;
    flex-wrap: wrap;
    gap: var(--sp-2);
    padding: 0 var(--gutter) var(--sp-3);
  }
  .timer-start { min-height: 48px; }

  .cook-nav {
    display: flex;
    gap: var(--sp-3);
    max-width: 760px;
    width: 100%;
    margin: 0 auto;
    padding-bottom: var(--sp-1); /* place pour l'ombre */
  }

  .nav-btn {
    flex: 1;
    width: auto;
    min-height: 60px;
    font-size: 17px;
  }

  .prev { flex: 0 1 42%; text-transform: uppercase; letter-spacing: 0.02em; }
  .prev:disabled { opacity: 0.35; }

  /* ── Rappel des ingrédients : fenêtre commune (.ui-overlay / .ui-sheet) ── */
  .sheet {
    max-height: 70svh;
    display: flex;
    flex-direction: column;
    padding-top: var(--sp-3);
    padding-bottom: calc(var(--sp-4) + env(safe-area-inset-bottom, 0px));
  }

  .sheet-head {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: var(--sp-3);
    margin-bottom: var(--sp-2);
  }

  .sheet-head h3 {
    font-family: var(--font-display);
    font-size: 20px;
    text-transform: uppercase;
  }

  .sheet-sub {
    font-family: var(--font-body);
    font-size: 15px;
    font-weight: var(--fw-medium);
    text-transform: none;
    color: var(--text-secondary);
  }

  .sheet-list {
    list-style: none;
    margin: 0;
    padding: 0;
    overflow-y: auto;
    max-width: 760px;
    width: 100%;
    margin-inline: auto;
    border: var(--line-w) solid var(--line);
    background: var(--surface);
  }

  .sheet-list li {
    display: flex;
    gap: var(--sp-3);
    align-items: baseline;
    padding: var(--sp-3);
    border-top: var(--line-thin) solid var(--line);
    font-size: 18px;
    line-height: 1.35;
    animation: fade-up var(--dur-sheet) var(--ease-out) calc(var(--i, 0) * 45ms) backwards;
  }

  .sheet-list li:first-child { border-top: none; }

  .sheet-qty {
    flex-shrink: 0;
    min-width: 76px;
    font-weight: var(--fw-bold);
    font-variant-numeric: tabular-nums;
  }

  .sheet-name { color: var(--text); }
</style>
