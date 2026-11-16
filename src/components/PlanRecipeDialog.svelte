<script lang="ts">
  // Fenêtre centrée en 2 étapes pour une recette :
  //   1. « Quand ? »  : portions + choix du créneau (4 semaines, on fait défiler)
  //   2. « Les courses » : ajouter les ingrédients (cochés, quantités ajustées) à la liste
  // mode 'plan' → étapes 1 puis 2 ; mode 'cart' → directement l'étape 2 (sans planifier).
  import { onMount, onDestroy, untrack } from 'svelte'
  import Icon from './Icon.svelte'
  import { profileState } from '../lib/profile.svelte'
  import { toast } from '../lib/toast.svelte'
  import {
    getMonday, toISODate, shiftWeek, fetchOrCreatePlan, setSlot, fetchSlotsForWeeks, courseFromCategory, courseLabel,
  } from '../lib/api/meals'
  import { addIngredientsToList, type IngredientToAdd } from '../lib/api/shopping'
  import { formatIngredient } from '../lib/quantities'
  import type { RecipeDetail, MealSlotWithRecipe } from '../lib/types'

  interface Props {
    recipe: RecipeDetail
    mode: 'plan' | 'cart'
    onclose: () => void
  }
  let { recipe, mode, onclose }: Props = $props()

  const WEEKS_SHOWN = 4
  const DAY_SHORT = ['Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam', 'Dim']
  const DAY_FULL = ['lundi', 'mardi', 'mercredi', 'jeudi', 'vendredi', 'samedi', 'dimanche']

  // ── État ──
  // La fenêtre est recréée à chaque ouverture : on lit volontairement les valeurs de départ.
  let step = $state<'plan' | 'cart'>(untrack(() => mode))
  let portions = $state(untrack(() => recipe.default_portions) || 4)
  let dialogEl: HTMLDivElement | undefined = $state()
  let saving = $state(false)
  /** Créneau choisi à l'étape 1 (affiché en haut de l'étape 2) */
  let planned = $state<{ label: string; replaced: string | null } | null>(null)

  // ── Semaines affichées ──
  interface DayRow { weekStart: string; dayIdx: number; date: Date; isToday: boolean; isPast: boolean }
  interface WeekGroup { weekStart: string; title: string; days: DayRow[] }

  const thisMonday = getMonday(new Date())
  const todayStr = toISODate(new Date())

  const weeks: WeekGroup[] = Array.from({ length: WEEKS_SHOWN }, (_, w) => {
    const monday = shiftWeek(thisMonday, w)
    const weekStart = toISODate(monday)
    const title = w === 0 ? 'Cette semaine'
      : w === 1 ? 'Semaine prochaine'
      : `Semaine du ${monday.toLocaleDateString('fr-FR', { day: 'numeric', month: 'long' })}`
    const days: DayRow[] = []
    for (let d = 0; d < 7; d++) {
      const date = new Date(monday)
      date.setDate(date.getDate() + d)
      const iso = toISODate(date)
      // Jours passés : seulement ceux de la semaine en cours (noter après coup ce
      // qu'on a mangé, pour l'Historique) ; repliés par défaut pour garder
      // aujourd'hui en haut. Semaines précédentes : onglet Semaine.
      days.push({ weekStart, dayIdx: d, date, isToday: iso === todayStr, isPast: iso < todayStr })
    }
    return { weekStart, title, days }
  })

  /** Jours déjà passés de la semaine en cours : repliés par défaut. */
  let showPastDays = $state(false)
  const pastDaysCount = weeks[0].days.filter((d) => d.isPast).length

  // Créneaux déjà pris (chargés en arrière-plan, la liste s'affiche tout de suite)
  let taken = $state<Record<string, MealSlotWithRecipe[]>>({})
  // Entrée, plat ou dessert d'après la catégorie (v1.99.0) : une entrée s'ajoute
  // à côté du plat déjà prévu au lieu de le remplacer.
  const course = courseFromCategory(untrack(() => recipe.recipe_categories?.name))
  function takenSlot(weekStart: string, dayIdx: number, meal: 'midi' | 'soir') {
    return taken[weekStart]?.find((s) => s.day_of_week === dayIdx && s.meal_type === meal && (s.course ?? 'plat') === course)
  }

  onMount(() => {
    const familyId = profileState.profile?.family_id
    if (mode === 'plan' && familyId) {
      fetchSlotsForWeeks(familyId, weeks.map((w) => w.weekStart))
        .then((r) => (taken = r))
        .catch(() => {}) // non bloquant : on peut planifier sans cette info
    }
    // Empêche la page derrière de défiler pendant que la fenêtre est ouverte
    document.body.style.overflow = 'hidden'
    dialogEl?.focus()
  })
  onDestroy(() => {
    document.body.style.overflow = ''
  })

  function onKey(e: KeyboardEvent) {
    if (e.key === 'Escape') onclose()
  }

  // ── Étape 1 : planifier ──
  async function choose(day: DayRow, meal: 'midi' | 'soir') {
    const familyId = profileState.profile?.family_id
    if (!familyId || saving) {
      if (!familyId) toast.error('Profil introuvable.')
      return
    }
    saving = true
    try {
      const previous = takenSlot(day.weekStart, day.dayIdx, meal)
      const plan = await fetchOrCreatePlan(familyId, day.weekStart)
      await setSlot(plan.id, day.dayIdx, meal, recipe.id, portions, course)
      const dateLabel = day.date.toLocaleDateString('fr-FR', { day: 'numeric', month: 'short' })
      planned = {
        label: `${DAY_FULL[day.dayIdx]} ${dateLabel} à ${meal === 'midi' ? 'midi' : 'soir'}${course !== 'plat' ? ` (${courseLabel(course).toLowerCase()})` : ''}`,
        replaced: previous && previous.recipes.id !== recipe.id ? previous.recipes.title : null,
      }
      resetCart()
      if (recipe.recipe_ingredients.length === 0) {
        toast.success(`${recipe.title} ajoutée ${planned.label}`)
        onclose()
      } else {
        step = 'cart'
      }
    } catch (e: any) {
      toast.error(e.message)
    } finally {
      saving = false
    }
  }

  // ── Étape 2 : les courses ──
  let checked = $state<Record<string, boolean>>({})
  function resetCart() {
    checked = Object.fromEntries(recipe.recipe_ingredients.map((i) => [i.id, true]))
  }
  resetCart()

  const selectedCount = $derived(Object.values(checked).filter(Boolean).length)
  const allSelected = $derived(selectedCount === recipe.recipe_ingredients.length)

  function toggleAll() {
    const v = !allSelected
    for (const i of recipe.recipe_ingredients) checked[i.id] = v
  }

  /** Quantité ajustée aux portions, avec son unité : « 1 kg », « 2,5 » */
  function scaledQty(qty: number | null, unit: string | null): string {
    return formatIngredient(qty, unit, portions / (recipe.default_portions || 4))
  }

  async function addToCart() {
    const familyId = profileState.profile?.family_id
    if (!familyId || saving) return
    const selected: IngredientToAdd[] = recipe.recipe_ingredients
      .filter((i) => checked[i.id])
      .map((i) => ({ name: i.name, quantity: i.quantity, unit: i.unit, shopping_category_id: i.shopping_category_id }))
    if (selected.length === 0) return
    saving = true
    try {
      // Recette non planifiée (« Juste les ingrédients ») → articles « ajoutés à la main »,
      // conservés si la liste est régénérée depuis le planning
      const n = await addIngredientsToList(familyId, selected, portions, recipe.default_portions, recipe.id, !planned)
      toast.success(
        planned
          ? `Planifiée et ${n} ingrédient${n > 1 ? 's' : ''} ajouté${n > 1 ? 's' : ''} aux courses`
          : `${n} ingrédient${n > 1 ? 's' : ''} ajouté${n > 1 ? 's' : ''} aux courses`,
      )
      onclose()
    } catch (e: any) {
      toast.error(e.message)
    } finally {
      saving = false
    }
  }

  function skipCart() {
    if (planned) toast.success(`${recipe.title} ajoutée ${planned.label}`)
    onclose()
  }
</script>

<svelte:window onkeydown={onKey} />

<!-- svelte-ignore a11y_click_events_have_key_events -->
<!-- svelte-ignore a11y_no_static_element_interactions -->
<div class="ui-overlay dlg-overlay" onclick={onclose}>
  <!-- svelte-ignore a11y_click_events_have_key_events -->
  <!-- svelte-ignore a11y_no_static_element_interactions -->
  <div
    class="ui-sheet dlg"
    bind:this={dialogEl}
    tabindex="-1"
    role="dialog"
    aria-modal="true"
    aria-labelledby="dlg-title"
    onclick={(e) => e.stopPropagation()}
  >
    <!-- En-tête -->
    <header class="dlg-header">
      <div class="dlg-titles">
        {#if mode === 'plan'}
          <span class="dlg-step">Étape {step === 'plan' ? 1 : 2} sur 2</span>
        {/if}
        <h2 id="dlg-title">
          {#if step === 'plan'}Quand la cuisiner ?{:else if planned}Et pour les courses ?{:else}Ajouter aux courses{/if}
        </h2>
        <p class="dlg-recipe">{recipe.title}</p>
      </div>
      <button class="btn btn-icon dlg-close" onclick={onclose} aria-label="Fermer">
        <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="square" stroke-linejoin="miter" aria-hidden="true"><path d="M18 6 6 18M6 6l12 12"/></svg>
      </button>
    </header>

    <!-- Portions (communes aux deux étapes) -->
    <div class="portions card">
      <span class="portions-label"><Icon name="users" size={16} /> Portions</span>
      <div class="stepper">
        <button class="btn btn-icon" onclick={() => { if (portions > 1) portions-- }} aria-label="Moins de portions" disabled={portions <= 1}>−</button>
        <span class="stepper-val" aria-live="polite">{portions}</span>
        <button class="btn btn-icon" onclick={() => portions++} aria-label="Plus de portions">+</button>
      </div>
    </div>

    {#if step === 'plan'}
      <!-- ── Étape 1 : créneaux sur 4 semaines ── -->
      <div class="dlg-scroll">
        {#each weeks as week, w (week.weekStart)}
          {#if week.days.length > 0}
            <h3 class="week-title">{week.title}</h3>
            {#if w === 0 && pastDaysCount > 0}
              <button
                type="button"
                class="past-toggle"
                aria-expanded={showPastDays}
                onclick={() => (showPastDays = !showPastDays)}
              >
                <span class="chev" class:open={showPastDays}><Icon name="chevron-down" size={16} /></span>
                {showPastDays ? 'Masquer les jours passés' : `Jours déjà passés (${pastDaysCount})`}
              </button>
            {/if}
            <div class="day-list">
              {#each week.days.filter((d) => !d.isPast || showPastDays) as day, di (day.weekStart + day.dayIdx)}
                <div class="day-row" class:is-today={day.isToday} class:is-past={day.isPast} style="--i: {Math.min(di, 8)}">
                  <div class="day-badge">
                    <span class="day-short">{DAY_SHORT[day.dayIdx]}</span>
                    <span class="day-num">{day.date.getDate()}</span>
                  </div>
                  <div class="meal-btns">
                    {#each ['midi', 'soir'] as const as meal (meal)}
                      {@const t = takenSlot(day.weekStart, day.dayIdx, meal)}
                      <button
                        class="meal-btn"
                        class:taken={!!t}
                        disabled={saving}
                        onclick={() => choose(day, meal)}
                        aria-label="{DAY_FULL[day.dayIdx]} {day.date.getDate()} {meal}{t ? `, déjà prévu : ${t.recipes.title} (sera remplacé)` : ''}"
                      >
                        <span class="meal-name"><Icon name={meal === 'midi' ? 'sun' : 'moon'} size={14} /> {meal === 'midi' ? 'Midi' : 'Soir'}</span>
                        {#if t}<span class="meal-taken">{t.recipes.title}</span>{/if}
                      </button>
                    {/each}
                  </div>
                </div>
              {/each}
            </div>
          {/if}
        {/each}
      </div>
      <p class="dlg-hint">Un créneau déjà pris sera remplacé.</p>
    {:else}
      <!-- ── Étape 2 : ingrédients ── -->
      {#if planned}
        <div class="planned-banner">
          <Icon name="check-circle" size={18} />
          <span>
            Prévue <strong>{planned.label}</strong>
            {#if planned.replaced}<span class="replaced">(remplace « {planned.replaced} »)</span>{/if}
          </span>
        </div>
      {/if}

      <div class="cart-toolbar">
        <button class="btn btn-ghost btn-sm link-btn" onclick={toggleAll}>{allSelected ? 'Tout décocher' : 'Tout cocher'}</button>
        <span class="cart-count">{selectedCount}/{recipe.recipe_ingredients.length}</span>
      </div>

      <div class="dlg-scroll">
        <div class="ing-list card">
          {#each recipe.recipe_ingredients as ing (ing.id)}
            <label class="row ing" class:off={!checked[ing.id]}>
              <input type="checkbox" class="check" bind:checked={checked[ing.id]} />
              <span class="ing-qty">{scaledQty(ing.quantity, ing.unit)}</span>
              <span class="ing-name">{ing.name}</span>
            </label>
          {/each}
        </div>
      </div>

      <div class="dlg-actions">
        <button class="btn btn-primary long" onclick={addToCart} disabled={saving || selectedCount === 0}>
          <Icon name="cart" />
          {saving ? 'Ajout…' : `Ajouter ${selectedCount} ingrédient${selectedCount > 1 ? 's' : ''} aux courses`}
        </button>
        {#if planned}
          <button class="btn btn-ghost skip-btn" onclick={skipCart} disabled={saving}>Pas maintenant</button>
        {/if}
      </div>
    {/if}
  </div>
</div>

<style>
  /* Fenêtre qui monte du bas : voile, cadre et animation dans app.css
     (.ui-overlay, .ui-sheet). Ici : en-tête fixe, contenu qui défile, pied fixe. */
  .dlg-overlay { padding-top: max(16px, env(safe-area-inset-top, 0px)); }

  .dlg {
    display: flex;
    flex-direction: column;
    overflow: hidden;
    max-height: min(88svh, 760px);
    padding: 0;
    width: min(480px, 100%);
  }

  @media (min-width: 640px) {
    .dlg-overlay { align-items: center; padding: var(--sp-4); }
    .dlg { border-bottom: var(--line-w) solid var(--line); box-shadow: var(--shadow-lg); }
  }

  /* ── En-tête ── */
  .dlg-header {
    display: flex;
    align-items: flex-start;
    justify-content: space-between;
    gap: var(--sp-3);
    padding: var(--sp-4) var(--gutter) var(--sp-3);
  }

  .dlg-titles { min-width: 0; }

  .dlg-step {
    display: inline-block;
    padding: 2px 8px;
    margin-bottom: 6px;
    background: var(--band);
    color: var(--text-on-band);
    font-size: 11px;
    font-weight: var(--fw-bold);
    letter-spacing: var(--tracking-caps);
    text-transform: uppercase;
  }

  .dlg-header h2 {
    font-size: var(--fs-xl);
    text-transform: uppercase;
    color: var(--text);
  }

  .dlg-recipe {
    margin-top: 2px;
    font-size: var(--fs-sm);
    color: var(--text-secondary);
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }

  /* ── Portions ── */
  .portions {
    display: flex;
    align-items: center;
    justify-content: space-between;
    margin: 0 var(--gutter) var(--sp-3);
    padding: var(--sp-2) var(--sp-2) var(--sp-2) var(--sp-3);
    box-shadow: var(--shadow-sm);
  }

  .portions-label {
    display: inline-flex;
    align-items: center;
    gap: var(--sp-2);
    font-size: var(--fs-sm);
    font-weight: var(--fw-bold);
    text-transform: uppercase;
    letter-spacing: var(--tracking-caps);
    color: var(--text);
  }

  .stepper {
    display: flex;
    align-items: center;
    gap: var(--sp-2);
  }

  .stepper .btn { font-size: 20px; }
  .stepper .btn:disabled { opacity: 0.35; }

  .stepper-val {
    min-width: 28px;
    text-align: center;
    font-family: var(--font-display);
    font-size: 20px;
    font-weight: var(--fw-bold);
    color: var(--text);
  }

  /* ── Zone qui défile ── */
  .dlg-scroll {
    flex: 1;
    min-height: 0;
    overflow-y: auto;
    overscroll-behavior: contain;
    -webkit-overflow-scrolling: touch;
    padding: 0 var(--gutter) var(--sp-2);
  }

  /* Titre de semaine : bandeau noir collé en haut pendant le défilement */
  .week-title {
    position: sticky;
    top: 0;
    z-index: 1;
    margin: var(--sp-2) 0 var(--sp-2);
    padding: 5px 10px;
    background: var(--band);
    color: var(--text-on-band);
    font-size: 13px;
    font-weight: var(--fw-bold);
    text-transform: uppercase;
    letter-spacing: var(--tracking-caps);
  }

  .day-list {
    display: flex;
    flex-direction: column;
    gap: var(--sp-2);
    margin-bottom: var(--sp-3);
  }

  /* Jour = ligne carrée ; aujourd'hui surligné */
  .day-row {
    display: flex;
    align-items: stretch;
    gap: var(--sp-2);
    padding: 6px;
    background: var(--surface);
    border: var(--line-w) solid var(--line);
    animation: fade-up var(--dur-sheet) var(--ease-out) calc(var(--i, 0) * 45ms) backwards;
  }

  .day-row.is-today { background: var(--highlight); box-shadow: var(--shadow-sm); }
  .day-row.is-past .day-badge { opacity: 0.6; }

  .past-toggle {
    display: inline-flex;
    align-items: center;
    gap: 6px;
    min-height: 44px;
    margin-bottom: var(--sp-1);
    padding: 0 6px;
    border: none;
    background: transparent;
    color: var(--text);
    font-family: var(--font-body);
    font-size: var(--fs-sm);
    font-weight: var(--fw-bold);
    text-decoration: underline;
    text-decoration-thickness: 2px;
    text-underline-offset: 3px;
    cursor: pointer;
    touch-action: manipulation;
  }
  .past-toggle .chev { display: inline-flex; transition: transform var(--dur-base) var(--ease-out); }
  .past-toggle .chev.open { transform: rotate(180deg); }

  .day-badge {
    width: 48px;
    flex-shrink: 0;
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    background: var(--band);
    color: var(--text-on-band);
    line-height: 1;
  }

  .day-short {
    font-size: 10px;
    font-weight: var(--fw-bold);
    text-transform: uppercase;
    letter-spacing: var(--tracking-caps);
  }

  .day-num {
    margin-top: 3px;
    font-family: var(--font-display);
    font-size: 18px;
    font-weight: var(--fw-bold);
  }

  .meal-btns {
    flex: 1;
    display: grid;
    grid-template-columns: 1fr 1fr;
    gap: 6px;
    min-width: 0;
  }

  .meal-btn {
    min-height: 48px;
    display: flex;
    flex-direction: column;
    align-items: flex-start;
    justify-content: center;
    gap: 2px;
    padding: 6px 10px;
    border: var(--line-w) solid var(--line);
    background: var(--surface);
    color: var(--text);
    font-family: var(--font-body);
    text-align: left;
    cursor: pointer;
    min-width: 0;
    touch-action: manipulation;
    transition: transform var(--dur-fast) var(--ease-out);
  }

  /* Créneau touché : orange, texte noir, il s'enfonce */
  .meal-btn:active:not(:disabled) {
    transform: translate(2px, 2px);
    background: var(--accent);
    color: var(--on-accent);
  }
  .meal-btn:active:not(:disabled) .meal-taken { color: var(--on-accent); }
  .meal-btn:disabled { opacity: 0.5; cursor: default; }

  .meal-name {
    display: inline-flex;
    align-items: center;
    gap: 6px;
    font-size: var(--fs-sm);
    font-weight: var(--fw-bold);
  }

  /* Déjà pris : en creux, bordure pointillée */
  .meal-btn.taken {
    border-style: dashed;
    background: var(--surface-sunken);
  }

  .meal-taken {
    max-width: 100%;
    font-size: 11px;
    color: var(--text-secondary);
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }

  .dlg-hint {
    padding: var(--sp-3) var(--gutter) max(var(--sp-4), env(safe-area-inset-bottom, 0px));
    font-size: 12px;
    color: var(--text-secondary);
    border-top: var(--line-w) solid var(--line);
  }

  /* ── Étape 2 ── */
  .planned-banner {
    display: flex;
    align-items: flex-start;
    gap: var(--sp-3);
    margin: 0 var(--gutter) var(--sp-3);
    padding: 10px var(--sp-3);
    background: var(--success-bg);
    border: var(--line-w) solid var(--line);
    color: var(--text);
    font-size: var(--fs-sm);
  }

  .planned-banner :global(svg) { flex-shrink: 0; }
  .planned-banner > span::first-letter { text-transform: uppercase; }
  .replaced { display: block; font-size: 12px; color: var(--text-secondary); }

  .cart-toolbar {
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: 0 var(--gutter) var(--sp-2);
  }

  .link-btn { padding: 0 var(--sp-2); margin-left: calc(var(--sp-2) * -1); }

  .cart-count {
    padding: 2px 8px;
    border: var(--line-w) solid var(--line);
    background: var(--surface);
    font-size: 13px;
    font-weight: var(--fw-bold);
    font-variant-numeric: tabular-nums;
  }

  .ing-list { display: flex; flex-direction: column; margin-bottom: var(--sp-2); }

  .ing {
    min-height: 48px;
    padding: 8px var(--sp-3);
    cursor: pointer;
    touch-action: manipulation;
  }
  .ing + .ing { border-top: var(--line-thin) solid var(--line); }

  .ing.off .ing-qty,
  .ing.off .ing-name { color: var(--text-secondary); text-decoration: line-through; text-decoration-thickness: 2px; }

  .ing-qty {
    min-width: 56px;
    font-size: var(--fs-sm);
    font-weight: var(--fw-bold);
  }

  .ing-name { font-size: 15px; color: var(--text); }

  .dlg-actions {
    display: flex;
    flex-direction: column;
    align-items: stretch;
    gap: var(--sp-2);
    padding: var(--sp-3) var(--gutter) max(var(--sp-4), env(safe-area-inset-bottom, 0px));
    border-top: var(--line-w) solid var(--line);
  }

  .dlg-actions .btn-primary {
    padding: 0 var(--sp-3);
    font-size: 15px;
  }

  @media (hover: hover) and (pointer: fine) {
    .meal-btn:hover:not(:disabled):not(.taken) { background: var(--surface-hover); }
    .meal-btn.taken:hover:not(:disabled) { background: var(--surface-hover); }
    .ing:hover { background: var(--surface-hover); }
  }
</style>
