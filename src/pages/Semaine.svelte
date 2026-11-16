<script lang="ts">
  import Icon from '../components/Icon.svelte'
  import { onDestroy } from 'svelte'
  import { profileState } from '../lib/profile.svelte'
  import { supabase } from '../lib/supabase'
  import type { RealtimeChannel } from '@supabase/supabase-js'
  import { href } from '../lib/router.svelte'
  import {
    getMonday,
    toISODate,
    shiftWeek,
    fetchOrCreatePlan,
    fetchSlots,
    setSlot,
    removeSlot,
    updateSlotPortions,
    addLeftover,
    COURSES,
    courseLabel,
    mealRank,
  } from '../lib/api/meals'
  import WeekTools from '../components/WeekTools.svelte'
  import { fetchRecipes } from '../lib/api/recipes'
  import { sizedImage } from '../lib/images'
  import { categoryColor } from '../lib/categoryColors'
  import { fetchFamilyMembers, setSlotCook } from '../lib/api/household'
  import { toast } from '../lib/toast.svelte'
  import CookPicker from '../components/CookPicker.svelte'
  import type { Course, FamilyMember, MealSlotWithRecipe, RecipeWithCategory } from '../lib/types'

  // ── État principal ──
  let weekMonday: Date = $state(getMonday(new Date()))
  let planId: string | null = $state(null)
  let slots: MealSlotWithRecipe[] = $state([])
  let loading = $state(true)
  let error = $state<string | null>(null)

  // ── Picker modal ──
  let pickerOpen = $state(false)
  let pickerDay = $state(0)
  let pickerMeal = $state<'midi' | 'soir'>('midi')
  let pickerCourse = $state<Course>('plat')
  let pickerSearch = $state('')
  let pickerRecipes: RecipeWithCategory[] = $state([])
  let pickerLoading = $state(false)
  let savingSlot = $state(false)

  // ── Portions editor ──
  let editingSlotId = $state<string | null>(null)
  let editingPortions = $state(4)

  // Jours de la semaine
  const DAY_NAMES = ['Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam', 'Dim']
  const DAY_NAMES_FULL = ['Lundi', 'Mardi', 'Mercredi', 'Jeudi', 'Vendredi', 'Samedi', 'Dimanche']

  // ── Charger le plan quand la semaine ou le profil change ──
  $effect(() => {
    if (profileState.loading) return
    const familyId = profileState.profile?.family_id
    if (!familyId) {
      loading = false
      error = 'Profil introuvable.'
      return
    }

    const weekStr = toISODate(weekMonday)

    loading = true
    error = null
    planId = null
    slots = []

    fetchOrCreatePlan(familyId, weekStr)
      .then(async (plan) => {
        planId = plan.id
        slots = await fetchSlots(plan.id)
      })
      .catch((e) => {
        error = e.message
      })
      .finally(() => {
        loading = false
      })
  })

  // ── Temps réel : le planning est partagé entre les membres du foyer ──
  // Quand quelqu'un ajoute / retire / modifie un repas, on recharge la semaine.
  // (Variable NON réactive : l'effet qui s'abonne la lit puis la modifie.)
  let channel: RealtimeChannel | null = null
  let refreshTimer: ReturnType<typeof setTimeout> | undefined

  function unsubscribe() {
    if (channel) {
      supabase?.removeChannel(channel)
      channel = null
    }
  }

  $effect(() => {
    const id = planId
    unsubscribe()
    if (!id || !supabase) return
    channel = supabase
      .channel(`meal-slots-${id}`)
      .on(
        'postgres_changes',
        { event: '*', schema: 'public', table: 'meal_slots', filter: `meal_plan_id=eq.${id}` },
        () => {
          // Plusieurs événements arrivent souvent ensemble (remplacement = suppression + ajout)
          clearTimeout(refreshTimer)
          refreshTimer = setTimeout(async () => {
            if (planId === id) slots = await fetchSlots(id)
          }, 250)
        },
      )
      .subscribe()
  })

  onDestroy(() => {
    clearTimeout(refreshTimer)
    unsubscribe()
  })

  // ── Helpers ──

  const COURSE_ORDER: Record<Course, number> = { entree: 0, plat: 1, dessert: 2 }
  const courseOf = (s: MealSlotWithRecipe): Course => s.course ?? 'plat'

  /** Tous les plats d'un repas (entrée, plat, dessert), dans l'ordre. */
  function mealSlots(day: number, meal: 'midi' | 'soir'): MealSlotWithRecipe[] {
    return slots
      .filter((s) => s.day_of_week === day && s.meal_type === meal)
      .sort((a, b) => COURSE_ORDER[courseOf(a)] - COURSE_ORDER[courseOf(b)])
  }

  /** Le plat mis en grand dans la tuile : le plat principal, sinon le premier. */
  function mainSlot(list: MealSlotWithRecipe[]): MealSlotWithRecipe | undefined {
    return list.find((s) => courseOf(s) === 'plat') ?? list[0]
  }

  const SHORT_MEAL = { midi: 'midi', soir: 'soir' } as const
  function mealName(s: { day_of_week: number; meal_type: 'midi' | 'soir' }): string {
    return `${DAY_NAMES[s.day_of_week]} ${SHORT_MEAL[s.meal_type]}`
  }

  /** Repas cuisiné dont ce créneau est les restes (s'il est dans la semaine affichée). */
  function parentOf(s: MealSlotWithRecipe): MealSlotWithRecipe | undefined {
    return s.leftover_of ? slots.find((x) => x.id === s.leftover_of) : undefined
  }

  /** Restes prévus d'un repas cuisiné (dans la semaine affichée). */
  function leftoversOf(s: MealSlotWithRecipe): MealSlotWithRecipe[] {
    return slots.filter((x) => x.leftover_of === s.id)
  }

  function weekLabel(): string {
    const end = new Date(weekMonday)
    end.setDate(end.getDate() + 6)
    const opts: Intl.DateTimeFormatOptions = { day: 'numeric', month: 'short' }
    const startStr = weekMonday.toLocaleDateString('fr-FR', opts)
    const endStr = end.toLocaleDateString('fr-FR', opts)
    return `${startStr} – ${endStr}`
  }

  function dayDate(dayIndex: number): string {
    const d = new Date(weekMonday)
    d.setDate(d.getDate() + dayIndex)
    return d.toLocaleDateString('fr-FR', { day: 'numeric', month: 'short' })
  }

  function isToday(dayIndex: number): boolean {
    const d = new Date(weekMonday)
    d.setDate(d.getDate() + dayIndex)
    const now = new Date()
    return d.getFullYear() === now.getFullYear()
      && d.getMonth() === now.getMonth()
      && d.getDate() === now.getDate()
  }

  // ── Navigation semaines ──

  function prevWeek() {
    weekMonday = shiftWeek(weekMonday, -1)
  }

  function nextWeek() {
    weekMonday = shiftWeek(weekMonday, 1)
  }

  function goToday() {
    weekMonday = getMonday(new Date())
  }

  // ── Picker ──

  function openPicker(day: number, meal: 'midi' | 'soir', course: Course = 'plat') {
    pickerDay = day
    pickerMeal = meal
    pickerCourse = course
    pickerSearch = ''
    pickerOpen = true
    loadPickerRecipes()
  }

  function closePicker() {
    pickerOpen = false
  }

  async function loadPickerRecipes() {
    pickerLoading = true
    try {
      const page = await fetchRecipes(0, 200)
      pickerRecipes = page.recipes
    } catch (e: any) {
      console.error('Erreur chargement recettes:', e.message)
    } finally {
      pickerLoading = false
    }
  }

  const filteredPickerRecipes = $derived.by(() => {
    const q = pickerSearch.trim().toLowerCase()
    if (!q) return pickerRecipes
    return pickerRecipes.filter((r) => r.title.toLowerCase().includes(q))
  })

  async function selectRecipe(recipeId: string, defaultPortions: number) {
    if (!planId || savingSlot) return
    savingSlot = true
    try {
      await setSlot(planId, pickerDay, pickerMeal, recipeId, defaultPortions, pickerCourse)
      slots = await fetchSlots(planId)
      closePicker()
    } catch (e: any) {
      error = e.message
    } finally {
      savingSlot = false
    }
  }

  /** Repas cuisinés plus tôt dans la semaine : on peut en prévoir les restes. */
  const leftoverSources = $derived(
    slots
      .filter((s) => !s.leftover_of && s.recipes && mealRank(s.day_of_week, s.meal_type) < mealRank(pickerDay, pickerMeal))
      .sort((a, b) => mealRank(b.day_of_week, b.meal_type) - mealRank(a.day_of_week, a.meal_type)),
  )

  async function selectLeftover(from: MealSlotWithRecipe) {
    if (!planId || savingSlot) return
    savingSlot = true
    try {
      await addLeftover(planId, pickerDay, pickerMeal, pickerCourse, from, from.portions)
      slots = await fetchSlots(planId)
      closePicker()
      toast.success(`Restes de ${mealName(from)} prévus`)
    } catch (e: any) {
      toast.error(e?.message ?? 'Les restes n’ont pas pu être prévus.')
    } finally {
      savingSlot = false
    }
  }

  // ── Recopier une semaine, semaines types ──
  let toolsOpen = $state(false)
  async function afterTools() {
    if (planId) slots = await fetchSlots(planId)
  }

  // ── Supprimer un slot ──

  async function handleRemoveSlot(slotId: string) {
    if (!planId) return
    try {
      await removeSlot(slotId)
      slots = await fetchSlots(planId)
    } catch (e: any) {
      error = e.message
    }
  }

  // ── Éditer les portions ──

  function startEditPortions(slot: MealSlotWithRecipe) {
    editingSlotId = slot.id
    editingPortions = slot.portions
  }

  async function savePortions() {
    if (!editingSlotId || !planId) return
    try {
      await updateSlotPortions(editingSlotId, editingPortions)
      slots = await fetchSlots(planId)
    } catch (e: any) {
      error = e.message
    } finally {
      editingSlotId = null
    }
  }

  function cancelEditPortions() {
    editingSlotId = null
  }

  // ── Affichage ──

  const MEALS: { key: 'midi' | 'soir'; label: string; icon: 'sun' | 'moon' }[] = [
    { key: 'midi', label: 'Midi', icon: 'sun' },
    { key: 'soir', label: 'Soir', icon: 'moon' },
  ]

  /** Nombre de repas déjà prévus sur les 14 de la semaine (entrée + plat + dessert = 1 repas). */
  const plannedCount = $derived(new Set(slots.map((s) => `${s.day_of_week}-${s.meal_type}`)).size)

  const isCurrentWeek = $derived(toISODate(weekMonday) === toISODate(getMonday(new Date())))

  /** Jour déjà passé (uniquement dans la semaine en cours) : affiché en retrait. */
  function isPast(dayIndex: number): boolean {
    const d = new Date(weekMonday)
    d.setDate(d.getDate() + dayIndex)
    d.setHours(23, 59, 59, 999)
    return d.getTime() < Date.now()
  }

  function dayNumber(dayIndex: number): number {
    const d = new Date(weekMonday)
    d.setDate(d.getDate() + dayIndex)
    return d.getDate()
  }

  // ── Qui cuisine ? ──

  let members: FamilyMember[] = $state([])
  let membersLoading = $state(false)
  let membersFamily: string | null = null // foyer déjà chargé (non réactif : évite de recharger)

  // Membres du foyer : chargés une fois (et de nouveau seulement si le foyer change)
  $effect(() => {
    const familyId = profileState.profile?.family_id
    if (!familyId || familyId === membersFamily) return
    membersFamily = familyId
    membersLoading = true
    fetchFamilyMembers(familyId)
      .then((list) => {
        if (membersFamily === familyId) members = list
      })
      .catch((e) => {
        console.error('Erreur chargement membres:', e?.message ?? e)
        membersFamily = null // on réessaiera à la prochaine ouverture du sélecteur
      })
      .finally(() => {
        membersLoading = false
      })
  })

  const myId = $derived(profileState.profile?.id ?? null)

  /** Nom du cuisinier d'un créneau (null = personne ou colonne absente). */
  function cookName(slot: MealSlotWithRecipe): string | null {
    const id = slot.cook_id
    if (!id) return null
    if (id === myId && profileState.profile?.display_name) return profileState.profile.display_name
    return members.find((m) => m.id === id)?.display_name ?? null
  }

  function initialOf(name: string | null): string {
    return name?.trim().charAt(0).toUpperCase() || '?'
  }

  let cookSlotId = $state<string | null>(null)
  const cookSlot = $derived(cookSlotId ? slots.find((s) => s.id === cookSlotId) : undefined)

  function openCookPicker(slot: MealSlotWithRecipe) {
    cookSlotId = slot.id
    // Les membres n'ont pas pu être chargés au départ : nouvel essai
    const familyId = profileState.profile?.family_id
    if (familyId && membersFamily === null && !membersLoading) {
      membersFamily = familyId
      membersLoading = true
      fetchFamilyMembers(familyId)
        .then((list) => (members = list))
        .catch(() => {
          membersFamily = null
          toast.error('Impossible de charger les membres du foyer.')
        })
        .finally(() => (membersLoading = false))
    }
  }

  function closeCookPicker() {
    cookSlotId = null
  }

  function patchCook(slotId: string, cookId: string | null) {
    slots = slots.map((s) => (s.id === slotId ? { ...s, cook_id: cookId } : s))
  }

  async function chooseCook(cookId: string | null) {
    const slot = cookSlot
    closeCookPicker()
    if (!slot) return
    const previous = slot.cook_id ?? null
    if (previous === cookId) return

    patchCook(slot.id, cookId) // optimiste
    try {
      await setSlotCook(slot.id, cookId)
    } catch (e: any) {
      // Retour arrière, sauf si quelqu'un a changé le créneau entre-temps
      const now = slots.find((s) => s.id === slot.id)
      if (now && (now.cook_id ?? null) === cookId) patchCook(slot.id, previous)
      const msg = `${e?.message ?? ''} ${e?.code ?? ''}`
      if (/cook_id|PGRST204|42703/.test(msg)) {
        toast.error("« Qui cuisine ? » n'est pas encore activé sur la base.")
      } else {
        toast.error("Le cuisinier n'a pas pu être enregistré. Réessaie.")
      }
      console.error('Erreur choix du cuisinier:', e?.message ?? e)
    }
  }

  // ── Filtre « Mes repas » ──
  let onlyMine = $state(false)
  const myMealsCount = $derived(myId ? slots.filter((s) => s.cook_id === myId).length : 0)
</script>

<div class="page">
  <!-- En-tête : titre + navigation semaine -->
  <header class="week-header">
    <div class="title-row">
      <h1>Semaine</h1>
      <div class="week-nav">
        <button class="nav-btn" onclick={prevWeek} aria-label="Semaine précédente">
          <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="square" stroke-linejoin="miter" aria-hidden="true"><path d="m15 18-6-6 6-6"/></svg>
        </button>
        <span class="week-label">{isCurrentWeek ? 'Cette semaine' : weekLabel()}</span>
        <button class="nav-btn" onclick={nextWeek} aria-label="Semaine suivante">
          <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="square" stroke-linejoin="miter" aria-hidden="true"><path d="m9 18 6-6-6-6"/></svg>
        </button>
      </div>
    </div>

    <div class="summary">
      <span class="summary-text">
        <strong>{plannedCount}</strong>/14 repas prévus
        {#if isCurrentWeek}<span class="summary-range">· {weekLabel()}</span>{/if}
      </span>
      {#if !isCurrentWeek}
        <button class="today-btn" onclick={goToday}>Revenir à cette semaine</button>
      {/if}
    </div>
    <div class="summary-bar" aria-hidden="true">
      <div class="summary-fill" style:transform="scaleX({plannedCount / 14})"></div>
    </div>

    {#if !loading && !error && myId}
      <div class="filter-row">
        <button class="filter-chip" onclick={() => (toolsOpen = true)} aria-haspopup="dialog">
          <Icon name="copy" size={16} />
          Recopier, semaines types
        </button>
        <button class="filter-chip" class:active={onlyMine} aria-pressed={onlyMine} onclick={() => (onlyMine = !onlyMine)}>
          <Icon name="chef" size={16} />
          Mes repas
          <span class="filter-count">{myMealsCount}</span>
        </button>
        {#if onlyMine}
          <span class="filter-hint" role="status">
            {myMealsCount === 0 ? 'Tu ne cuisines aucun repas cette semaine' : myMealsCount === 1 ? 'Tu cuisines 1 repas' : `Tu cuisines ${myMealsCount} repas`}
          </span>
        {/if}
      </div>
    {/if}
  </header>

  {#if loading}
    <div class="center-msg"><div class="spinner"></div></div>
  {:else if error}
    <div class="center-msg error-msg">{error}</div>
  {:else}
    <div class="days-grid">
      {#each Array(7) as _, dayIdx}
        {@const today = isToday(dayIdx)}
        {@const past = isCurrentWeek && !today && isPast(dayIdx)}
        <section class="day-card" style="--i: {dayIdx}" class:is-today={today} class:is-past={past} aria-label={DAY_NAMES_FULL[dayIdx]}>
          <div class="day-header">
            <div class="day-badge">
              <span class="day-name">{DAY_NAMES[dayIdx]}</span>
              <span class="day-num">{dayNumber(dayIdx)}</span>
            </div>
            <span class="day-full">{DAY_NAMES_FULL[dayIdx]} {dayDate(dayIdx)}</span>
            {#if today}<span class="today-chip">Aujourd'hui</span>{/if}
          </div>

          <div class="slots">
            {#each MEALS as meal (meal.key)}
              {@const list = mealSlots(dayIdx, meal.key)}
              {@render slotTile(dayIdx, meal, mainSlot(list), list)}
            {/each}
          </div>
        </section>
      {/each}
    </div>
  {/if}
</div>

<!-- Une tuile repas (remplie ou vide) -->
{#snippet slotTile(dayIdx: number, meal: (typeof MEALS)[number], slot: MealSlotWithRecipe | undefined, list: MealSlotWithRecipe[])}
  {#if slot}
    {@const cook = cookName(slot)}
    {@const mine = !!myId && list.some((x) => x.cook_id === myId)}
    {@const parent = parentOf(slot)}
    {@const kids = leftoversOf(slot)}
    {@const extras = list.filter((x) => x.id !== slot.id)}
    {@const missing = COURSES.filter((c) => !list.some((x) => courseOf(x) === c.key))}
    <div class="slot filled" class:dimmed={onlyMine && !mine} class:mine={onlyMine && mine} class:leftover={!!slot.leftover_of}>
      {#if !slot.leftover_of}
      <button
        class="cook-btn"
        onclick={() => openCookPicker(slot)}
        aria-label={cook ? `Qui cuisine ? ${cook}` : 'Choisir qui cuisine'}
        aria-haspopup="dialog"
        title={cook ? `${cook} cuisine` : 'Choisir qui cuisine'}
      >
        {#if cook}
          <span class="cook-dot" aria-hidden="true">{initialOf(cook)}</span>
        {:else}
          <span class="cook-dot cook-dot-empty" aria-hidden="true"><Icon name="chef" size={15} /></span>
        {/if}
      </button>
      {/if}
      <a href={href('recette', slot.recipes.id)} class="slot-visual" aria-label={slot.recipes.title}>
        {#if sizedImage(slot.recipes.image_url, 260, 110)}
          <img src={sizedImage(slot.recipes.image_url, 260, 110)} alt="" loading="lazy" />
        {:else}
          <span class="slot-monogram" aria-hidden="true">{slot.recipes.title.trim().charAt(0)}</span>
        {/if}
        <span class="meal-chip"><Icon name={meal.icon} size={12} /> {meal.label}{#if courseOf(slot) !== 'plat'} · {courseLabel(courseOf(slot))}{/if}</span>
        {#if slot.leftover_of}<span class="leftover-chip">Restes</span>{/if}
      </a>
      <div class="slot-body">
        <a href={href('recette', slot.recipes.id)} class="slot-title">{slot.recipes.title}</a>
        {#if slot.leftover_of}
          <span class="leftover-note">{parent ? `Cuisiné ${mealName(parent)}` : 'Cuisiné la semaine d’avant'}</span>
        {:else if kids.length > 0}
          <span class="leftover-note">+ restes {kids.map(mealName).join(', ')}</span>
        {/if}
        <div class="slot-actions">
          {#if editingSlotId === slot.id}
            <div class="portions-edit">
              <button class="portions-btn" onclick={() => { if (editingPortions > 1) editingPortions-- }} aria-label="Moins">−</button>
              <span class="portions-val">{editingPortions}</span>
              <button class="portions-btn" onclick={() => editingPortions++} aria-label="Plus">+</button>
              <button class="portions-save" onclick={savePortions} aria-label="Valider"><Icon name="check" size={14} strokeWidth={2.5} /></button>
            </div>
          {:else}
            <button class="portions-display" onclick={() => startEditPortions(slot)} aria-label="Modifier les portions">
              <Icon name="users" size={14} /> {slot.portions}
            </button>
            <button class="remove-btn" onclick={() => handleRemoveSlot(slot.id)} aria-label="Retirer {slot.recipes.title}">
              <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="square" stroke-linejoin="miter" aria-hidden="true"><path d="M18 6 6 18M6 6l12 12"/></svg>
            </button>
          {/if}
        </div>
      </div>
      <!-- Autres plats du repas (entrée, dessert) -->
      {#if extras.length > 0}
        <ul class="courses" aria-label="Autres plats du repas">
          {#each extras as x (x.id)}
            <li class="course-row">
              <span class="course-tag">{courseLabel(courseOf(x))}{#if x.leftover_of} · restes{/if}</span>
              <a href={href('recette', x.recipes.id)} class="course-title">{x.recipes.title}</a>
              <button class="course-remove" onclick={() => handleRemoveSlot(x.id)} aria-label="Retirer {x.recipes.title}">
                <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="square" stroke-linejoin="miter" aria-hidden="true"><path d="M18 6 6 18M6 6l12 12"/></svg>
              </button>
            </li>
          {/each}
        </ul>
      {/if}
      {#if missing.length > 0}
        <div class="course-add">
          {#each missing as c (c.key)}
            <button class="course-add-btn" onclick={() => openPicker(dayIdx, meal.key, c.key)} aria-label="Ajouter {c.label.toLowerCase()} : {DAY_NAMES_FULL[dayIdx]} {meal.label}">+ {c.label}</button>
          {/each}
        </div>
      {/if}
    </div>
  {:else}
    <button class="slot empty" class:dimmed={onlyMine} onclick={() => openPicker(dayIdx, meal.key)} aria-label="Ajouter un repas : {DAY_NAMES_FULL[dayIdx]} {meal.label}">
      <span class="empty-meal"><Icon name={meal.icon} size={14} /> {meal.label}</span>
      <span class="empty-plus">
        <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="square" stroke-linejoin="miter" aria-hidden="true"><path d="M12 5v14M5 12h14"/></svg>
      </span>
    </button>
  {/if}
{/snippet}

<!-- Modal picker de recettes -->
{#if pickerOpen}
  <!-- svelte-ignore a11y_no_static_element_interactions -->
  <!-- svelte-ignore a11y_click_events_have_key_events -->
  <div class="ui-overlay" onclick={closePicker}>
    <!-- svelte-ignore a11y_click_events_have_key_events -->
    <!-- svelte-ignore a11y_no_static_element_interactions -->
    <div class="ui-sheet picker" onclick={(e) => e.stopPropagation()}>
      <div class="picker-header">
        <h2>{DAY_NAMES_FULL[pickerDay]} · {pickerMeal === 'midi' ? 'Midi' : 'Soir'}</h2>
        <button class="picker-close" onclick={closePicker} aria-label="Fermer">
          <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="square" stroke-linejoin="miter" aria-hidden="true"><path d="M18 6 6 18M6 6l12 12"/></svg>
        </button>
      </div>

      <div class="course-switch" role="radiogroup" aria-label="Sorte de plat">
        {#each COURSES as c (c.key)}
          <button
            type="button"
            role="radio"
            class="course-opt"
            class:on={pickerCourse === c.key}
            aria-checked={pickerCourse === c.key}
            onclick={() => (pickerCourse = c.key)}
          >{c.label}</button>
        {/each}
      </div>

      {#if leftoverSources.length > 0}
        <details class="leftovers">
          <summary>Utiliser des restes ({leftoverSources.length})</summary>
          <p class="leftovers-hint">Le repas choisi sera cuisiné en plus grande quantité : les courses comptent les deux.</p>
          <ul>
            {#each leftoverSources as src (src.id)}
              <li>
                <button class="picker-item" disabled={savingSlot} onclick={() => selectLeftover(src)}>
                  <span class="leftover-when">{mealName(src)}</span>
                  <span class="picker-item-title">{src.recipes.title}</span>
                  <span class="picker-item-time"><Icon name="users" size={13} /> {src.portions}</span>
                </button>
              </li>
            {/each}
          </ul>
        </details>
      {/if}

      <div class="picker-search">
        <svg class="search-icon" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="square" stroke-linejoin="miter" aria-hidden="true">
          <circle cx="11" cy="11" r="8"/><path d="m21 21-4.35-4.35"/>
        </svg>
        <input
          type="search"
          class="search-input"
          placeholder="Rechercher une recette…"
          bind:value={pickerSearch}
        />
      </div>

      <div class="picker-list">
        {#if pickerLoading}
          <div class="center-msg"><div class="spinner"></div></div>
        {:else if filteredPickerRecipes.length === 0}
          <p class="picker-empty">Aucune recette trouvée.</p>
        {:else}
          {#each filteredPickerRecipes as recipe (recipe.id)}
            <button
              class="picker-item"
              disabled={savingSlot}
              onclick={() => selectRecipe(recipe.id, recipe.default_portions)}
            >
              {#if sizedImage(recipe.image_url, 44, 44)}
                <img src={sizedImage(recipe.image_url, 44, 44)} alt="" class="picker-thumb" loading="lazy" />
              {:else}
                <span class="picker-emoji" aria-hidden="true" style="background: {categoryColor(recipe.recipe_categories?.name)}">{recipe.title.trim().charAt(0)}</span>
              {/if}
              <div class="picker-item-info">
                <span class="picker-item-title">{recipe.title}</span>
                {#if recipe.recipe_categories}
                  <span
                    class="tag picker-item-cat"
                    style="background: {categoryColor(recipe.recipe_categories.name)}; color: var(--ink)"
                  >{recipe.recipe_categories.name}</span>
                {/if}
              </div>
              {#if recipe.prep_time_min}
                <span class="picker-item-time"><Icon name="clock" size={13} /> {recipe.prep_time_min} min</span>
              {/if}
            </button>
          {/each}
        {/if}
      </div>
    </div>
  </div>
{/if}

{#if toolsOpen && planId && profileState.profile?.family_id}
  <WeekTools
    familyId={profileState.profile.family_id}
    {planId}
    {weekMonday}
    weekHasMeals={slots.length > 0}
    onchanged={afterTools}
    onclose={() => (toolsOpen = false)}
  />
{/if}

<!-- Fenêtre « Qui cuisine ? » -->
{#if cookSlot}
  <CookPicker
    members={members}
    currentId={cookSlot.cook_id ?? null}
    meId={myId}
    loading={membersLoading}
    subtitle="{DAY_NAMES_FULL[cookSlot.day_of_week]} {cookSlot.meal_type === 'midi' ? 'midi' : 'soir'} · {cookSlot.recipes.title}"
    onselect={chooseCook}
    onclose={closeCookPicker}
  />
{/if}

<style>
  .page {
    padding: var(--gutter);
    padding-top: calc(var(--gutter) + env(safe-area-inset-top, 0px));
    padding-bottom: calc(84px + env(safe-area-inset-bottom, 0px));
    max-width: 1600px;
    margin: 0 auto;
  }

  /* ── En-tête ── */
  .week-header { margin-bottom: var(--sp-4); }

  /* Téléphone : titre, puis navigation sur toute la largeur (évite l'avatar) */
  .title-row {
    display: flex;
    flex-direction: column;
    align-items: stretch;
    gap: var(--sp-3);
    margin-bottom: 14px;
  }

  .title-row h1 { padding-right: 56px; /* avatar en haut à droite */ }

  @media (min-width: 640px) {
    .title-row {
      flex-direction: row;
      align-items: center;
      justify-content: space-between;
      padding-right: 60px;
    }
  }

  .week-nav {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: var(--sp-1);
    background: var(--surface);
    border: var(--line-w) solid var(--line);
    box-shadow: var(--shadow-sm);
  }

  .nav-btn {
    display: flex;
    align-items: center;
    justify-content: center;
    width: 44px;
    height: 44px;
    border: none;
    background: transparent;
    color: var(--text);
    cursor: pointer;
    touch-action: manipulation;
    transition: transform var(--dur-fast) var(--ease-out);
  }

  .nav-btn:active { transform: translate(2px, 2px); background: var(--surface-hover); }

  .week-label {
    font-size: var(--fs-base);
    font-weight: var(--fw-bold);
    text-transform: uppercase;
    letter-spacing: var(--tracking-caps);
    color: var(--text);
    padding: 0 6px;
    white-space: nowrap;
    min-width: 140px;
    text-align: center;
  }

  .summary {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: var(--sp-2);
    font-size: var(--fs-sm);
    font-weight: var(--fw-medium);
    color: var(--text);
    margin-bottom: var(--sp-2);
  }

  .summary strong { font-size: var(--fs-lg); font-weight: var(--fw-bold); }
  .summary-range { margin-left: 2px; color: var(--text-secondary); }

  .today-btn {
    min-height: 44px;
    border: none;
    background: none;
    color: var(--text);
    font-family: var(--font-body);
    font-size: 13px;
    font-weight: var(--fw-bold);
    text-decoration: underline;
    text-decoration-thickness: 2px;
    text-underline-offset: 3px;
    cursor: pointer;
    touch-action: manipulation;
  }

  /* Progression : bloc carré bordé, remplissage orange (scaleX) */
  .summary-bar {
    height: 14px;
    border: var(--line-w) solid var(--line);
    background: var(--surface);
    overflow: hidden;
  }

  .summary-fill {
    height: 100%;
    background: var(--accent);
    transform-origin: left center;
    transition: transform var(--dur-sheet) var(--ease-out);
  }

  /* ── Grille des jours ──
     Téléphone : une carte par ligne, Midi et Soir côte à côte
     Tablette  : 2 colonnes de jours
     Ordinateur: les 7 jours en colonnes (Midi au-dessus de Soir) */
  .days-grid {
    display: grid;
    grid-template-columns: 1fr;
    gap: var(--sp-4);
  }

  @media (min-width: 640px) {
    .days-grid { grid-template-columns: repeat(2, 1fr); }
  }

  @media (min-width: 1100px) {
    .days-grid { grid-template-columns: repeat(7, 1fr); gap: var(--sp-3); }
  }

  /* Un jour = carte blanche + bandeau */
  .day-card {
    display: flex;
    flex-direction: column;
    background: var(--surface);
    border: var(--line-w) solid var(--line);
    box-shadow: var(--shadow-md);
    animation: fade-up var(--dur-sheet) var(--ease-out) calc(var(--i, 0) * 45ms) backwards;
  }

  /* Jour passé : seul le bandeau passe en retrait (la carte reste lisible) */
  .is-past .day-header { opacity: 0.6; }

  .day-header {
    display: flex;
    align-items: center;
    gap: var(--sp-3);
    padding: 6px 10px;
    background: var(--band);
    color: var(--text-on-band);
  }

  /* Aujourd'hui : bandeau orange, texte noir */
  .is-today .day-header {
    background: var(--accent);
    color: var(--on-accent);
  }

  .day-badge {
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    width: 40px;
    height: 40px;
    background: var(--text-on-band);
    color: var(--band);
    line-height: 1;
    flex-shrink: 0;
  }

  .is-today .day-badge {
    background: var(--ink);
    color: var(--butter);
  }

  .day-name {
    font-size: 10px;
    font-weight: var(--fw-bold);
    text-transform: uppercase;
    letter-spacing: var(--tracking-caps);
  }

  .day-num {
    font-family: var(--font-display);
    font-size: var(--fs-lg);
    font-weight: var(--fw-bold);
    margin-top: 2px;
  }

  .day-full {
    font-size: var(--fs-base);
    font-weight: var(--fw-bold);
    text-transform: uppercase;
    letter-spacing: var(--tracking-caps);
  }

  .today-chip {
    margin-left: auto;
    padding: 1px 6px;
    border: var(--line-thin) solid var(--ink);
    background: var(--ink);
    color: var(--butter);
    font-size: var(--fs-xs);
    font-weight: var(--fw-bold);
    text-transform: uppercase;
    letter-spacing: var(--tracking-caps);
  }

  /* Midi / Soir : côte à côte sur téléphone et tablette, l'un sous l'autre en 7 colonnes */
  .slots {
    display: grid;
    grid-template-columns: 1fr 1fr;
    gap: var(--sp-2);
    padding: var(--sp-2);
    flex: 1;
  }

  @media (min-width: 1100px) {
    .slots { grid-template-columns: 1fr; grid-auto-rows: 1fr; }
    .day-full { display: none; }
    .today-chip { margin-left: 0; }
    /* sélecteurs plus précis : ces règles passent devant celles de base, écrites plus bas */
    .slots .slot-visual { height: 120px; }
    .slots .slot { min-height: 150px; }
    .slots .slot.empty { flex-direction: column; justify-content: center; gap: var(--sp-3); }
  }

  .slot { min-height: 64px; }

  /* ── Mini-carte repas planifié ── */
  .slot.filled {
    position: relative;
    display: flex;
    flex-direction: column;
    background: var(--surface);
    border: var(--line-w) solid var(--line);
    overflow: hidden;
  }

  .slot-visual {
    position: relative;
    display: block;
    height: 76px;
    background: var(--highlight);
    border-bottom: var(--line-w) solid var(--line);
    overflow: hidden;
  }

  .slot-visual img {
    width: 100%;
    height: 100%;
    object-fit: cover;
    display: block;
  }

  .slot-monogram {
    position: absolute;
    inset: 0;
    display: flex;
    align-items: center;
    justify-content: center;
    font-family: var(--font-display);
    font-weight: var(--fw-bold);
    font-size: 40px;
    text-transform: uppercase;
    color: var(--text);
  }

  .meal-chip {
    position: absolute;
    top: 0;
    left: 0;
    display: inline-flex;
    align-items: center;
    gap: 4px;
    padding: 3px 8px;
    background: var(--band);
    color: var(--text-on-band);
    font-size: 11px;
    font-weight: var(--fw-bold);
    text-transform: uppercase;
    letter-spacing: var(--tracking-caps);
  }

  .slot-body {
    display: flex;
    flex-direction: column;
    gap: 6px;
    padding: 8px 10px;
    flex: 1;
  }

  .slot-title {
    font-size: var(--fs-sm);
    font-weight: var(--fw-bold);
    line-height: 1.25;
    color: var(--text);
    display: -webkit-box;
    -webkit-line-clamp: 2;
    line-clamp: 2;
    -webkit-box-orient: vertical;
    overflow: hidden;
  }

  .slot-actions {
    display: flex;
    align-items: center;
    justify-content: space-between;
    margin-top: auto;
  }

  .portions-display {
    display: inline-flex;
    align-items: center;
    gap: 5px;
    min-height: 44px;
    padding: 0 8px;
    border: none;
    background: transparent;
    color: var(--text);
    font-family: var(--font-body);
    font-size: 13px;
    font-weight: var(--fw-bold);
    cursor: pointer;
    touch-action: manipulation;
  }

  .remove-btn {
    display: flex;
    align-items: center;
    justify-content: center;
    width: 44px;
    height: 44px;
    margin: -6px -8px -6px 0;
    border: none;
    background: transparent;
    color: var(--text-secondary);
    cursor: pointer;
    touch-action: manipulation;
  }

  .remove-btn:active { background: var(--error-bg); color: var(--error); }

  .portions-edit {
    display: flex;
    align-items: center;
    gap: var(--sp-1);
  }

  .portions-btn,
  .portions-save {
    width: 32px;
    height: 32px;
    border: var(--line-w) solid var(--line);
    background: var(--surface);
    color: var(--text);
    font-size: var(--fs-base);
    font-weight: var(--fw-bold);
    cursor: pointer;
    display: flex;
    align-items: center;
    justify-content: center;
    padding: 0;
    font-family: var(--font-body);
    line-height: 1;
    touch-action: manipulation;
    transition: transform var(--dur-fast) var(--ease-out);
  }

  .portions-btn:active,
  .portions-save:active { transform: translate(2px, 2px); }

  .portions-save { background: var(--accent); color: var(--on-accent); }

  .portions-val {
    font-size: var(--fs-sm);
    font-weight: var(--fw-bold);
    min-width: 18px;
    text-align: center;
    color: var(--text);
  }

  /* ── Créneau vide : bloc carré, bordure pointillée 2 px ── */
  .slot.empty {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: var(--sp-2);
    padding: 0 var(--sp-3);
    border: var(--line-w) dashed var(--line);
    background: transparent;
    color: var(--text);
    font-family: var(--font-body);
    cursor: pointer;
    touch-action: manipulation;
    transition: transform var(--dur-fast) var(--ease-out);
  }

  .slot.empty:active { transform: translate(2px, 2px); background: var(--surface-hover); }

  .empty-meal {
    display: inline-flex;
    align-items: center;
    gap: 6px;
    font-size: 13px;
    font-weight: var(--fw-bold);
    text-transform: uppercase;
    letter-spacing: var(--tracking-caps);
  }

  .empty-plus {
    display: flex;
    align-items: center;
    justify-content: center;
    width: 28px;
    height: 28px;
    background: var(--accent);
    color: var(--on-accent);
    border: var(--line-w) solid var(--line);
  }

  /* ── Qui cuisine ? : puce carrée en haut à droite de la photo ──
     Zone tactile 44 px, visuel 28 px */
  .cook-btn {
    position: absolute;
    top: 0;
    right: 0;
    z-index: 1;
    display: flex;
    align-items: center;
    justify-content: center;
    width: 44px;
    height: 44px;
    padding: 0;
    border: none;
    background: transparent;
    cursor: pointer;
    touch-action: manipulation;
  }

  .cook-dot {
    display: flex;
    align-items: center;
    justify-content: center;
    width: 28px;
    height: 28px;
    border: var(--line-w) solid var(--ink);
    background: var(--accent);
    color: var(--on-accent);
    font-size: 13px;
    font-weight: var(--fw-bold);
    line-height: 1;
    transition: transform var(--dur-fast) var(--ease-out);
  }

  /* Personne : toque sur fond beurre */
  .cook-dot-empty { background: var(--butter); color: var(--ink); }

  .cook-btn:active .cook-dot { transform: translate(2px, 2px); }

  /* ── Filtre « Mes repas » ── */
  .filter-row {
    display: flex;
    align-items: center;
    flex-wrap: wrap;
    gap: var(--sp-1) var(--sp-3);
    margin-top: var(--sp-3);
  }

  .filter-chip {
    display: inline-flex;
    align-items: center;
    gap: 7px;
    min-height: 44px;
    padding: 0 8px 0 14px;
    border: var(--line-w) solid var(--line);
    background: var(--surface);
    color: var(--text);
    font-family: var(--font-body);
    font-size: var(--fs-sm);
    font-weight: var(--fw-bold);
    cursor: pointer;
    touch-action: manipulation;
    transition: transform var(--dur-fast) var(--ease-out);
  }

  .filter-chip:active { transform: translate(2px, 2px); }

  .filter-chip.active {
    background: var(--accent);
    color: var(--on-accent);
    box-shadow: var(--shadow-sm);
  }

  .filter-count {
    display: inline-flex;
    align-items: center;
    justify-content: center;
    min-width: 26px;
    height: 26px;
    padding: 0 7px;
    background: var(--band);
    color: var(--text-on-band);
    font-size: 13px;
  }

  .filter-hint { font-size: 13px; color: var(--text-secondary); }

  /* Filtre actif : mes repas mis en avant, les autres atténués (rien n'est caché) */
  .slot.dimmed { opacity: 0.4; }

  /* ── Restes (v1.99.0) ── */
  .slot.filled.leftover { border-style: dashed; }
  .leftover-chip {
    position: absolute;
    right: 0;
    bottom: 0;
    padding: 2px 7px;
    border-top: var(--line-w) solid var(--line);
    border-left: var(--line-w) solid var(--line);
    background: var(--highlight);
    color: var(--text);
    font-size: 11px;
    font-weight: var(--fw-bold);
    text-transform: uppercase;
    letter-spacing: var(--tracking-caps);
  }
  .leftover-note {
    font-size: 12px;
    font-weight: var(--fw-medium);
    color: var(--text-secondary);
  }

  /* ── Autres plats du repas : entrée, dessert ── */
  .courses {
    list-style: none;
    margin: 0;
    padding: 0;
    border-top: var(--line-thin) solid var(--line);
  }
  .course-row {
    display: flex;
    align-items: center;
    gap: 6px;
    min-height: 44px;
    padding-left: 8px;
  }
  .course-row + .course-row { border-top: var(--line-thin) solid var(--line); }
  .course-tag {
    flex: none;
    padding: 0 4px;
    background: var(--band);
    color: var(--text-on-band);
    font-size: 10px;
    font-weight: var(--fw-bold);
    text-transform: uppercase;
    letter-spacing: var(--tracking-caps);
  }
  .course-title {
    flex: 1;
    min-width: 0;
    font-size: 13px;
    font-weight: var(--fw-bold);
    color: var(--text);
    text-decoration: none;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }
  .course-remove {
    flex: none;
    display: grid;
    place-items: center;
    width: 40px;
    height: 44px;
    border: none;
    background: transparent;
    color: var(--text-secondary);
    cursor: pointer;
    touch-action: manipulation;
  }
  .course-add {
    display: flex;
    border-top: var(--line-thin) solid var(--line);
  }
  .course-add-btn {
    flex: 1;
    min-height: 44px;
    padding: 0 4px;
    border: none;
    background: transparent;
    color: var(--text);
    font-family: var(--font-body);
    font-size: 12px;
    font-weight: var(--fw-bold);
    cursor: pointer;
    touch-action: manipulation;
  }
  .course-add-btn + .course-add-btn { border-left: var(--line-thin) solid var(--line); }
  .course-add-btn:active { background: var(--accent); color: var(--on-accent); }

  /* ── Fenêtre de choix : sorte de plat et restes ── */
  .course-switch {
    display: flex;
    margin: 0 0 var(--sp-3);
    border: var(--line-w) solid var(--line);
  }
  .course-opt {
    flex: 1;
    min-height: 44px;
    border: none;
    background: var(--surface);
    color: var(--text);
    font-family: var(--font-body);
    font-size: var(--fs-sm);
    font-weight: var(--fw-bold);
    cursor: pointer;
    touch-action: manipulation;
  }
  .course-opt + .course-opt { border-left: var(--line-w) solid var(--line); }
  .course-opt.on { background: var(--accent); color: var(--on-accent); }

  .leftovers {
    margin: 0 0 var(--sp-3);
    border: var(--line-w) solid var(--line);
    background: var(--surface);
  }
  .leftovers summary {
    display: flex;
    align-items: center;
    min-height: 44px;
    padding: 0 var(--sp-3);
    background: var(--highlight);
    font-weight: var(--fw-bold);
    cursor: pointer;
  }
  .leftovers[open] summary { border-bottom: var(--line-w) solid var(--line); }
  .leftovers-hint {
    margin: var(--sp-2) var(--sp-3);
    font-size: 13px;
    color: var(--text-secondary);
  }
  .leftovers ul { list-style: none; margin: 0; padding: 0; }
  .leftover-when {
    flex: none;
    min-width: 58px;
    font-size: 12px;
    font-weight: var(--fw-bold);
    text-transform: uppercase;
  }

  .slot.filled.mine { box-shadow: var(--shadow-sm); }

  @media (hover: hover) and (pointer: fine) {
    .slot.dimmed:hover { opacity: 0.75; }
    .nav-btn:hover { background: var(--surface-hover); }
    .slot.empty:hover { background: var(--surface-hover); }
    .slot-title:hover { text-decoration: underline; text-decoration-thickness: 2px; }
    .remove-btn:hover { background: var(--error-bg); color: var(--error); }
    .picker-item:not(:disabled):hover { background: var(--surface-hover); }
  }

  /* ── Fenêtre de choix de recette (.ui-overlay / .ui-sheet globaux) ── */
  .picker {
    display: flex;
    flex-direction: column;
    overflow: hidden;
    padding: 0;
    max-height: 80dvh;
  }

  .picker-header {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: var(--sp-3);
    padding: var(--sp-4) var(--gutter) var(--sp-2);
    flex-shrink: 0;
  }

  .picker-header h2 { font-size: var(--fs-lg); text-transform: uppercase; color: var(--text); }

  .picker-close {
    display: flex;
    align-items: center;
    justify-content: center;
    flex: none;
    width: 44px;
    height: 44px;
    border: var(--line-w) solid var(--line);
    background: var(--surface);
    color: var(--text);
    box-shadow: var(--shadow-sm);
    cursor: pointer;
    touch-action: manipulation;
    transition: transform var(--dur-fast) var(--ease-out);
  }

  .picker-close:active { transform: translate(var(--press), var(--press)); box-shadow: none; }

  .picker-search {
    position: relative;
    padding: 0 var(--gutter) var(--sp-3);
    flex-shrink: 0;
  }

  .picker-search .search-icon {
    position: absolute;
    left: calc(var(--gutter) + 13px);
    top: 24px;
    transform: translateY(-50%);
    color: var(--text);
    pointer-events: none;
  }

  .picker-search .search-input {
    width: 100%;
    height: var(--tap);
    padding: 0 12px 0 42px;
    border: var(--line-w) solid var(--line);
    border-radius: 0;
    background: var(--bg);
    color: var(--text);
    font-size: var(--fs-base);
    font-family: var(--font-body);
    -webkit-appearance: none;
    appearance: none;
  }

  .picker-search .search-input:focus { outline: none; box-shadow: var(--shadow-sm); }
  .picker-search .search-input::placeholder { color: var(--text-placeholder); opacity: 1; }

  .picker-list {
    flex: 1;
    overflow-y: auto;
    -webkit-overflow-scrolling: touch;
    padding: var(--sp-1) var(--gutter) var(--sp-5);
  }

  .picker-empty {
    text-align: center;
    padding: var(--sp-6) var(--sp-4);
    color: var(--text-secondary);
    font-size: var(--fs-sm);
  }

  .picker-item {
    display: flex;
    align-items: center;
    gap: 10px;
    width: 100%;
    min-height: 56px;
    padding: 6px 10px 6px 6px;
    border: var(--line-w) solid var(--line);
    background: var(--surface);
    text-align: left;
    cursor: pointer;
    font-family: var(--font-body);
    margin-bottom: var(--sp-2);
    transition: transform var(--dur-fast) var(--ease-out);
  }

  .picker-item:active:not(:disabled) { transform: translate(2px, 2px); }
  .picker-item:disabled { opacity: 0.5; cursor: not-allowed; }

  .picker-thumb {
    width: 44px;
    height: 44px;
    border: var(--line-w) solid var(--line);
    object-fit: cover;
    flex-shrink: 0;
  }

  .picker-emoji {
    width: 44px;
    height: 44px;
    display: flex;
    align-items: center;
    justify-content: center;
    border: var(--line-w) solid var(--line);
    font-family: var(--font-display);
    font-weight: var(--fw-bold);
    font-size: 20px;
    text-transform: uppercase;
    color: var(--ink); /* toujours noir : posé sur l'aplat de la catégorie */
    flex-shrink: 0;
  }

  .picker-item-info {
    flex: 1;
    min-width: 0;
    display: flex;
    flex-direction: column;
    align-items: flex-start;
    gap: 2px;
  }

  .picker-item-title {
    max-width: 100%;
    font-size: var(--fs-sm);
    font-weight: var(--fw-bold);
    color: var(--text);
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }

  .picker-item-cat {
    font-size: 11px;
    font-weight: var(--fw-bold);
    text-transform: uppercase;
    letter-spacing: var(--tracking-caps);
    border-color: var(--ink);
  }

  .picker-item-time {
    display: inline-flex;
    align-items: center;
    gap: 3px;
    font-size: 12px;
    font-weight: var(--fw-medium);
    color: var(--text-secondary);
    flex-shrink: 0;
  }

  /* ── Communs ── */
  .center-msg {
    display: flex;
    justify-content: center;
    padding: 48px 16px;
  }

  .error-msg { color: var(--error); font-size: var(--fs-sm); font-weight: var(--fw-medium); }

  /* Rond d'une icône dessinée (indicateur de chargement) */
  .spinner {
    width: 28px;
    height: 28px;
    border: 3px solid var(--line);
    border-top-color: var(--accent);
    animation: spin 0.7s linear infinite;
  }

  @keyframes spin { to { transform: rotate(360deg); } }
</style>
