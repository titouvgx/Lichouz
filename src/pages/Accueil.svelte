<script lang="ts">
  import Icon from '../components/Icon.svelte'
  // Page d'accueil : 5 recettes tirées au hasard chaque jour, qui flottent à l'écran.
  // - Le tirage dépend de la date → même sélection pour toute la famille, change à minuit.
  // - Le placement est calculé (lib/floatLayout.ts) pour tenir dans l'écran sans chevauchement.
  import { onDestroy } from 'svelte'
  import { profileState } from '../lib/profile.svelte'
  import { href } from '../lib/router.svelte'
  import { fetchDailyRecipes, todayKey, DAILY_RECIPES_COUNT } from '../lib/api/recipes'
  import { computeFloatLayout, MIN_ZONE_HEIGHT } from '../lib/floatLayout'
  import FloatingRecipeCard from '../components/FloatingRecipeCard.svelte'
  import Cheminee from '../components/Cheminee.svelte'
  import { theme } from '../lib/theme.svelte'
  import { fetchEvents, type FamilyEvent } from '../lib/api/events'
  import { countdownLabel, daysUntil, templateOf } from '../lib/evenements'
  import PlanRecipeDialog from '../components/PlanRecipeDialog.svelte'
  import { fetchRecipe } from '../lib/api/recipes'
  import { fetchTodayMeals, type TodayMeal } from '../lib/api/household'
  import { toast } from '../lib/toast.svelte'
  import type { RecipeDetail } from '../lib/types'
  import type { RecipeWithCategory } from '../lib/types'

  // ────────── Données ──────────

  let recipes: RecipeWithCategory[] = $state([])
  let loading = $state(true)
  let error = $state<string | null>(null)

  /** Date du jour (AAAA-MM-JJ). Quand elle change, l'effet ci-dessous refait le tirage. */
  let dateKey = $state(todayKey())
  let now = $state(new Date())

  $effect(() => {
    if (profileState.loading) return
    const key = dateKey
    let cancelled = false // évite qu'une vieille requête écrase une plus récente

    loading = true
    error = null
    fetchDailyRecipes(key)
      .then((r) => { if (!cancelled) recipes = r })
      .catch((e) => { if (!cancelled) error = e?.message ?? 'Erreur de chargement' })
      .finally(() => { if (!cancelled) loading = false })

    return () => { cancelled = true }
  })

  // Repas prévus aujourd'hui (« Ce soir : … »). En cas d'échec : on n'affiche rien.
  let todayMeals = $state<TodayMeal[]>([])

  $effect(() => {
    if (profileState.loading) return
    const familyId = profileState.profile?.family_id
    void dateKey // recharger à minuit
    if (!familyId) { todayMeals = []; return }
    let cancelled = false
    fetchTodayMeals(familyId)
      .then((m) => { if (!cancelled) todayMeals = m })
      .catch(() => { if (!cancelled) todayMeals = [] })
    return () => { cancelled = true }
  })

  // Prochain événement (Noël, anniversaire…) dans les 60 jours : bandeau sous le bonjour.
  // En cas d'échec (ancienne base sans événements) : on n'affiche rien.
  let nextEvent = $state<FamilyEvent | null>(null)
  $effect(() => {
    if (profileState.loading || !profileState.profile?.family_id) return
    void dateKey
    let cancelled = false
    fetchEvents()
      .then((list) => {
        if (cancelled) return
        nextEvent = list.find((e) => { const n = daysUntil(e.starts_on); return n >= 0 && n <= 60 }) ?? null
      })
      .catch(() => { if (!cancelled) nextEvent = null })
    return () => { cancelled = true }
  })

  // Horloge : compte à rebours + détection de minuit (aussi au retour sur l'app)
  function tick() {
    now = new Date()
    const k = todayKey(now)
    if (k !== dateKey) dateKey = k
  }
  const clock = setInterval(tick, 30_000)
  const onVisible = () => { if (document.visibilityState === 'visible') tick() }
  document.addEventListener('visibilitychange', onVisible)
  onDestroy(() => {
    clearInterval(clock)
    document.removeEventListener('visibilitychange', onVisible)
  })

  // ────────── Textes ──────────

  const firstName = $derived(profileState.profile?.display_name?.trim().split(/\s+/)[0] ?? '')
  const greeting = $derived(now.getHours() >= 18 ? 'Bonsoir' : 'Bonjour')
  const dateLabel = $derived(
    now.toLocaleDateString('fr-FR', { weekday: 'long', day: 'numeric', month: 'long' }),
  )
  const countdown = $derived.by(() => {
    const midnight = new Date(now)
    midnight.setHours(24, 0, 0, 0)
    const mins = Math.max(1, Math.ceil((midnight.getTime() - now.getTime()) / 60000))
    const h = Math.floor(mins / 60)
    const m = mins % 60
    return h > 0 ? `${h} h ${String(m).padStart(2, '0')}` : `${m} min`
  })

  /** Le repas à venir : le midi jusqu'à 14 h (sinon le soir), puis le soir. */
  const nextMeal = $derived.by(() => {
    const midi = todayMeals.find((m) => m.mealType === 'midi')
    const soir = todayMeals.find((m) => m.mealType === 'soir')
    return now.getHours() < 14 ? (midi ?? soir ?? null) : (soir ?? null)
  })

  // ────────── Placement ──────────

  let zoneW = $state(0)
  let zoneH = $state(0)

  const cardCount = $derived(loading ? DAILY_RECIPES_COUNT : recipes.length)
  const layout = $derived(computeFloatLayout(zoneW, zoneH, cardCount, `layout:${dateKey}`))

  // ────────── Planifier directement depuis une carte ──────────
  // La fenêtre a besoin des ingrédients : on charge la recette complète au clic.
  let planRecipe = $state<RecipeDetail | null>(null)
  let opening = false

  async function openPlan(recipeId: string) {
    if (opening) return
    opening = true
    try {
      planRecipe = await fetchRecipe(recipeId)
    } catch (e: any) {
      toast.error(e?.message ?? 'Recette introuvable')
    } finally {
      opening = false
    }
  }

  // ────────── Parallaxe (souris uniquement) ──────────
  // Au doigt, pointermove se déclenche pendant le défilement : les cartes
  // sauteraient. On la réserve donc à la souris / au trackpad.

  let px = $state(0)
  let py = $state(0)
  const reduceMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches
  let frame = 0

  function onPointerMove(e: PointerEvent) {
    if (reduceMotion || e.pointerType !== 'mouse') return
    const el = e.currentTarget as HTMLElement
    cancelAnimationFrame(frame)
    frame = requestAnimationFrame(() => {
      const r = el.getBoundingClientRect()
      px = ((e.clientX - r.left) / r.width - 0.5) * 2 // −1 → 1
      py = ((e.clientY - r.top) / r.height - 0.5) * 2
    })
  }

  function resetParallax() {
    cancelAnimationFrame(frame)
    px = 0
    py = 0
  }

  onDestroy(() => cancelAnimationFrame(frame))

</script>

{#if planRecipe}
  <PlanRecipeDialog recipe={planRecipe} mode="plan" onclose={() => (planRecipe = null)} />
{/if}

<div class="page accueil">

  <header class="hero" class:hero-noel={theme.name === 'noel'}>
    {#if theme.name === 'noel'}
      <!-- Thème Noël : grande cheminée en haut à droite, derrière le texte et les cartes -->
      <div class="hearth" aria-hidden="true"><Cheminee size={132} /></div>
    {/if}
    <span class="date-chip">{dateLabel}</span>
    <h1>
      {greeting}{firstName ? ` ${firstName}` : ''}
    </h1>
    <p class="subtitle">
      Tes <strong>{DAILY_RECIPES_COUNT} idées</strong> du jour
    </p>
    {#if nextMeal}
      <a href={href('recette', nextMeal.recipeId)} class="today-meal">
        <Icon name={nextMeal.mealType === 'midi' ? 'sun' : 'moon'} size={15} />
        <span class="today-text">
          <span class="today-when">{nextMeal.mealType === 'midi' ? 'Ce midi' : 'Ce soir'}&nbsp;:</span>
          <strong>{nextMeal.title}</strong>{#if nextMeal.cookName}{' · '}<span class="today-cook">{nextMeal.cookName} cuisine</span>{/if}
        </span>
        <Icon name="chevron-right" size={15} />
      </a>
    {/if}
    {#if nextEvent}
      <a href={href('evenement', nextEvent.id)} class="event-banner">
        <Icon name={templateOf(nextEvent.kind).icon} size={18} />
        <span class="event-text"><strong>{nextEvent.title}</strong> · {countdownLabel(nextEvent.starts_on).toLowerCase()}</span>
        <Icon name="chevron-right" size={15} />
      </a>
    {:else if theme.name === 'noel'}
      <a href="#/evenements/nouveau" class="event-banner">
        <Icon name="star" size={18} />
        <span class="event-text"><strong>Organiser Noël</strong> · qui vient, qui fait quoi</span>
        <Icon name="chevron-right" size={15} />
      </a>
    {/if}
  </header>

  {#if error}
    <div class="state error-msg" role="alert">
      <p>Impossible de charger les recettes du jour.</p>
      <p class="state-detail">{error}</p>
    </div>
  {:else if !loading && recipes.length === 0}
    <div class="state">
      <p class="state-icon"><Icon name="book" size={48} strokeWidth={1.5} /></p>
      <p>Aucune recette pour le moment.</p>
      <a href="#/nouvelle-recette" class="btn btn-primary state-cta">Créer la première recette</a>
    </div>
  {:else}
    <section
      class="float-zone"
      aria-label="Recettes du jour"
      aria-busy={loading}
      bind:clientWidth={zoneW}
      bind:clientHeight={zoneH}
      style:min-height="{MIN_ZONE_HEIGHT}px"
      style:--px={px}
      style:--py={py}
      onpointermove={onPointerMove}
      onpointerleave={resetParallax}
    >
      {#each layout.slots as slot, i (i)}
        <FloatingRecipeCard
          {slot}
          index={i}
          recipe={loading ? null : (recipes[i] ?? null)}
          featured={i === 0}
          onplan={openPlan}
        />
      {/each}
    </section>

    <!-- Hors de la zone flottante : la zone (flex: 1) rétrécit d'autant et
         computeFloatLayout reçoit la hauteur restante → aucune carte dessous. -->
    <a href={href('frigo')} class="fridge-cta">
      <span class="fridge-icon"><Icon name="chef" size={20} /></span>
      <span class="fridge-text">
        <strong>Qu'est-ce qu'on mange&nbsp;?</strong>
        <span>Selon ce qu'il y a dans le frigo</span>
      </span>
      <Icon name="chevron-right" size={18} />
    </a>

    <footer class="accueil-footer">
      <p class="countdown">
        <span class="dot" aria-hidden="true"></span>
        <span>Nouvelles idées dans <strong>{countdown}</strong></span>
      </p>
      <a href={href('recettes')} class="see-all">Toutes les recettes →</a>
    </footer>
  {/if}
</div>

<style>
  .accueil {
    position: relative;
    display: flex;
    flex-direction: column;
    /* svh = hauteur stable : ne bouge pas quand la barre d'adresse se replie,
       sinon les cartes seraient recalculées pendant le défilement */
    min-height: calc(100vh - 84px - env(safe-area-inset-bottom, 0px));
    min-height: calc(100svh - 84px - env(safe-area-inset-bottom, 0px));
    padding: var(--gutter);
    padding-top: calc(14px + env(safe-area-inset-top, 0px));
    padding-bottom: 8px;
    overflow: hidden;
    isolation: isolate;
  }

  /* ── En-tête ────────────────────────────────── */
  .hero {
    position: relative;
    padding-right: 56px; /* place pour l'avatar en haut à droite */
  }

  /* Thème Noël : grande cheminée dans le coin libre à droite du bonjour,
     sous l'avatar ; derrière le texte et les cartes (z-index -1, au-dessus du fond animé). */
  .hearth {
    position: absolute;
    top: 52px;
    right: -4px;
    z-index: -1;
    pointer-events: none;
  }
  /* La cheminée garde sa place : les cartes du jour commencent en dessous */
  .hero-noel { min-height: 188px; }

  /* Date : petite étiquette noire, comme un bandeau de rayon */
  .date-chip {
    display: inline-block;
    padding: 3px 8px;
    background: var(--band);
    color: var(--text-on-band);
    font-size: var(--fs-xs);
    font-weight: var(--fw-bold);
    text-transform: uppercase;
    letter-spacing: var(--tracking-caps);
    margin-bottom: var(--sp-2);
  }

  .hero h1 {
    font-size: clamp(30px, 9.5vw, 46px);
  }

  .subtitle {
    margin-top: var(--sp-1);
    color: var(--text);
    font-size: 15px;
    font-weight: var(--fw-medium);
  }

  /* « 5 idées » : surligné orange, comme au marqueur */
  .subtitle strong {
    padding: 0 3px;
    background: var(--accent);
    color: var(--on-accent);
    font-weight: var(--fw-bold);
  }

  /* Repas du jour : petit bloc blanc cliquable vers la fiche */
  /* Prochain événement : même allure que « Ce soir », couleur d'action */
  .event-banner {
    position: relative;
    z-index: 1;
    display: flex;
    align-items: center;
    gap: 8px;
    width: fit-content;
    max-width: calc(100% - 120px);
    min-height: 44px;
    margin-top: var(--sp-3);
    padding: 6px 10px;
    background: var(--accent);
    color: var(--on-accent);
    border: var(--line-w) solid var(--line);
    box-shadow: var(--shadow-sm);
    font-size: 14px;
    line-height: 1.25;
    touch-action: manipulation;
    transition: transform var(--dur-fast) var(--ease-out);
  }
  .event-banner:active { transform: translate(2px, 2px); box-shadow: none; }

  .today-meal {
    display: inline-flex;
    align-items: center;
    gap: 7px;
    max-width: calc(100% + 56px); /* l'avatar est plus haut : on récupère sa marge */
    min-height: 44px;
    margin-top: var(--sp-3);
    margin-right: -56px;
    padding: 6px 10px;
    background: var(--surface);
    border: var(--line-w) solid var(--line);
    box-shadow: var(--shadow-sm);
    color: var(--text-secondary);
    font-size: 13px;
    line-height: 1.25;
    text-decoration: none;
    touch-action: manipulation;
    transition: transform var(--dur-fast) var(--ease-out);
  }

  .today-meal > :global(svg:first-child) { flex-shrink: 0; color: var(--text); }
  .today-meal > :global(svg:last-child) { flex-shrink: 0; color: var(--text); }

  /* Titre long ou petit écran : on passe à la ligne (2 lignes max) plutôt que de couper le cuisinier */
  .today-text {
    min-width: 0;
    display: -webkit-box;
    -webkit-line-clamp: 2;
    line-clamp: 2;
    -webkit-box-orient: vertical;
    overflow: hidden;
  }

  .today-cook { white-space: nowrap; }

  .today-when { color: var(--text-secondary); }
  .today-meal strong { color: var(--text); font-weight: var(--fw-bold); }

  .today-meal:active { transform: translate(var(--press), var(--press)); box-shadow: none; }

  /* ── Zone flottante ─────────────────────────── */
  .float-zone {
    position: relative;
    flex: 1;
    /* bord à bord : on récupère les marges latérales pour des cartes plus grandes */
    margin: 4px calc(var(--gutter) * -1) 0;
  }

  /* ── « Qu'est-ce qu'on mange ? » ────────────── */
  .fridge-cta {
    display: flex;
    align-items: center;
    gap: var(--sp-3);
    min-height: 60px;
    margin-top: 6px;
    padding: 0 14px 0 0;
    background: var(--surface);
    border: var(--line-w) solid var(--line);
    box-shadow: var(--shadow-md);
    color: var(--text);
    text-decoration: none;
    touch-action: manipulation;
    transition: transform var(--dur-fast) var(--ease-out);
  }

  .fridge-cta:active { transform: translate(4px, 4px); box-shadow: none; }

  /* Bloc orange collé à gauche, plein hauteur */
  .fridge-icon {
    flex-shrink: 0;
    align-self: stretch;
    width: 56px;
    display: flex;
    align-items: center;
    justify-content: center;
    background: var(--accent);
    border-right: var(--line-w) solid var(--line);
    color: var(--on-accent);
  }

  .fridge-text {
    flex: 1;
    min-width: 0;
    display: flex;
    flex-direction: column;
    line-height: 1.2;
  }

  .fridge-text strong {
    font-family: var(--font-display);
    font-size: var(--fs-base);
    font-weight: var(--fw-bold);
    text-transform: uppercase;
  }

  .fridge-text span {
    margin-top: 2px;
    font-size: 13px;
    color: var(--text-secondary);
  }

  .fridge-cta > :global(svg) { flex-shrink: 0; color: var(--text); }

  /* Grand écran : bouton centré, pas en bandeau sur toute la largeur */
  @media (min-width: 700px) {
    .fridge-cta { align-self: center; width: min(100%, 460px); }
  }

  /* Téléphones courts (360 × 740…) : bouton sur une ligne, pour laisser
     la hauteur aux cartes (la zone flottante ne descend pas sous MIN_ZONE_HEIGHT) */
  @media (max-height: 780px) {
    .fridge-cta { min-height: 50px; margin-top: 4px; }
    .fridge-icon { width: 48px; }
    .fridge-text span { display: none; }
    .today-meal { margin-top: 6px; }
  }

  @media (hover: hover) and (pointer: fine) {
    .fridge-cta:hover, .today-meal:hover, .see-all:hover { background: var(--surface-hover); }
  }

  /* ── Pied de page ───────────────────────────── */
  .accueil-footer {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: var(--sp-3);
    padding-top: 10px;
  }

  .countdown {
    display: flex;
    align-items: center;
    gap: var(--sp-2);
    min-width: 0;
    font-size: 13px;
    line-height: 1.25;
    color: var(--text);
  }

  .countdown strong {
    white-space: nowrap; /* « 15 h 39 » ne doit jamais être coupé */
    font-weight: var(--fw-bold);
  }

  /* Carré vert qui clignote sèchement (opacity seulement) */
  .dot {
    flex-shrink: 0;
    width: 10px;
    height: 10px;
    background: var(--success);
    border: var(--line-thin) solid var(--line);
    animation: blink 1.6s steps(2, jump-none) infinite;
  }

  @keyframes blink {
    50% { opacity: 0.25; }
  }

  .see-all {
    flex-shrink: 0;
    min-height: 44px; /* zone de tap confortable */
    display: inline-flex;
    align-items: center;
    padding: 0 14px;
    background: var(--surface);
    border: var(--line-w) solid var(--line);
    box-shadow: var(--shadow-sm);
    color: var(--text);
    font-size: var(--fs-sm);
    font-weight: var(--fw-bold);
    touch-action: manipulation;
    transition: transform var(--dur-fast) var(--ease-out);
  }

  .see-all:active {
    transform: translate(var(--press), var(--press));
    box-shadow: none;
  }

  /* ── États ──────────────────────────────────── */
  .state {
    flex: 1;
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    gap: var(--sp-1);
    text-align: center;
    padding: 32px 16px;
    color: var(--text-secondary);
  }

  .state-icon { color: var(--text); }

  .state-detail { font-size: var(--fs-xs); }

  .error-msg { color: var(--error); font-weight: var(--fw-medium); }

  .state-cta {
    margin-top: var(--sp-4);
    width: auto;
    padding: 0 24px;
  }

  /* Très petits écrans (iPhone SE, vieux Android) */
  @media (max-width: 359px) {
    .countdown { font-size: var(--fs-xs); }
    .see-all { padding: 0 10px; font-size: 13px; }
  }

  /* Très petits téléphones (iPhone SE, 375 × 667) : on retire le superflu
     (date, compte à rebours) pour que tout tienne sans défiler. */
  @media (max-height: 700px) {
    .date-chip { display: none; }
    .countdown { display: none; }
    .see-all { margin-inline: auto; }
    .accueil-footer { justify-content: center; padding-top: 2px; }
  }
</style>
