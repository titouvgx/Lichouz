<script lang="ts">
  // Fiche recette « magazine » :
  //   grande photo bord à bord → titre + infos → ingrédients (portions ajustables, cochables)
  //   → étapes (touchables pour les marquer faites) → mode « En cuisine » plein écran.
  // Les actions principales (semaine / courses) sont dans une barre collée en bas, au pouce.
  import Icon from '../components/Icon.svelte'
  import StarRating from '../components/StarRating.svelte'
  import ErrorState from '../components/ErrorState.svelte'
  import ConfirmDialog from '../components/ConfirmDialog.svelte'
  import PlanRecipeDialog from '../components/PlanRecipeDialog.svelte'
  import CookMode from '../components/CookMode.svelte'
  import { router, href, navigate } from '../lib/router.svelte'
  import { profileState } from '../lib/profile.svelte'
  import { fetchRecipe, setRecipeArchived } from '../lib/api/recipes'
  import { formatIngredient } from '../lib/quantities'
  import { sizedImage } from '../lib/images'
  import { categoryColor } from '../lib/categoryColors'
  import { toast } from '../lib/toast.svelte'
  import type { RecipeDetail } from '../lib/types'
  import { openRecipesWithTag, type TagRef } from '../lib/recipeFilters'
  import { budgetLabel, cleanKeys, origineLabel, regimeLabel, REGIMES, themeLabel, THEMES, BUDGETS } from '../lib/etiquettes'

  const MIN_PORTIONS = 1
  const MAX_PORTIONS = 30

  let recipe = $state<RecipeDetail | null>(null)
  let loading = $state(true)
  let error = $state<string | null>(null)
  let deleting = $state(false)
  let showDeleteConfirm = $state(false)

  // ── Planifier / ajouter aux courses (fenêtre en 2 étapes) ──
  // 'plan' : choisir un créneau puis proposer les ingrédients ; 'cart' : seulement les ingrédients
  let dialogMode = $state<'plan' | 'cart' | null>(null)

  // ── État local de la fiche (rien n'est enregistré) ──
  let portions = $state(4)
  /** Ingrédients déjà sortis du placard (id → true) */
  let gotIng = $state<Record<string, boolean>>({})
  /** Étapes faites (id → true) */
  let doneStep = $state<Record<string, boolean>>({})
  let cookOpen = $state(false)

  $effect(() => {
    const id = router.recipeId
    if (!id) return

    loading = true
    error = null
    recipe = null
    gotIng = {}
    doneStep = {}
    // Changement de recette (lien, retour arrière…) : on referme tout ce qui était ouvert
    cookOpen = false
    dialogMode = null
    showDeleteConfirm = false

    fetchRecipe(id)
      .then((r) => {
        recipe = r
        if (!r) error = 'Recette introuvable.'
        else portions = r.default_portions || 4
      })
      .catch((e) => {
        error = e.message
      })
      .finally(() => {
        loading = false
      })
  })

  const isAdmin = $derived(profileState.profile?.role === 'admin')
  // Les recettes sont partagées entre foyers, mais seul le foyer qui l'a créée
  // peut la modifier (tout membre) ou la supprimer (son admin) — comme la base.
  const ownRecipe = $derived(
    Boolean(recipe && profileState.profile && recipe.family_id === profileState.profile.family_id)
  )
  // Recettes du catalogue commun (livrées avec l'appli) : lecture seule, sauf super-admin
  const isSuperAdmin = $derived(!!profileState.context?.isSuperAdmin)
  const isCatalogue = $derived(recipe?.visibility === 'catalogue')
  const canEdit = $derived(isSuperAdmin || (ownRecipe && !isCatalogue))
  const canDelete = $derived(isSuperAdmin || (ownRecipe && isAdmin && !isCatalogue))
  const visibilityLabel = $derived(
    recipe?.visibility === 'catalogue' ? 'Catalogue commun'
      : recipe?.visibility === 'super_famille' ? 'Toute la famille'
      : 'Mon foyer',
  )

  const defaultPortions = $derived(recipe?.default_portions || 4)
  const scale = $derived(portions / defaultPortions)
  // Étiquettes (migration 25), dans l'ordre de la liste de référence
  const tagChips = $derived.by(() => {
    if (!recipe) return []
    // Chaque étiquette ouvre Recettes filtré sur elle seule (v1.99.0)
    const out: { label: string; title?: string; ref: TagRef }[] = []
    for (const d of cleanKeys(recipe.diets ?? [], REGIMES)) out.push({ label: regimeLabel(d), ref: { kind: 'diet', key: d } })
    if (recipe.origin) out.push({ label: origineLabel(recipe.origin), title: 'Origine', ref: { kind: 'origin', key: recipe.origin } })
    for (const t of cleanKeys(recipe.themes ?? [], THEMES)) out.push({ label: themeLabel(t), ref: { kind: 'theme', key: t } })
    if (recipe.budget) out.push({ label: budgetLabel(recipe.budget), title: BUDGETS.find((b) => b.value === recipe!.budget)?.long, ref: { kind: 'budget', value: recipe.budget } })
    return out
  })
  const catColor = $derived(categoryColor(recipe?.recipe_categories?.name))

  const gotCount = $derived(recipe ? recipe.recipe_ingredients.filter((i) => gotIng[i.id]).length : 0)
  const doneCount = $derived(recipe ? recipe.recipe_steps.filter((s) => doneStep[s.id]).length : 0)
  /** Le mode cuisine reprend à la première étape pas encore faite */
  const cookStart = $derived.by(() => {
    if (!recipe) return 0
    const i = recipe.recipe_steps.findIndex((s) => !doneStep[s.id])
    return i === -1 ? 0 : i
  })

  // Photo à la bonne taille (calculée une fois : inutile de recharger au redimensionnement)
  const wide = typeof window !== 'undefined' && window.innerWidth >= 900
  const heroW = typeof window !== 'undefined' ? Math.min(window.innerWidth, 1080) : 400
  const heroH = Math.round(wide ? heroW / 3 : heroW * 0.75)
  const heroSrc = $derived(recipe?.image_url ? sizedImage(recipe.image_url, heroW, heroH) : null)

  function formatTime(min: number | null): string {
    if (!min) return ''
    if (min < 60) return `${min} min`
    const h = Math.floor(min / 60)
    const m = min % 60
    return m ? `${h} h ${String(m).padStart(2, '0')}` : `${h} h`
  }

  function setPortions(n: number) {
    portions = Math.min(MAX_PORTIONS, Math.max(MIN_PORTIONS, n))
  }

  const isArchived = $derived(!!recipe?.archived_at)

  async function setArchived(archived: boolean) {
    if (!recipe || deleting) return
    deleting = true
    try {
      await setRecipeArchived(recipe.id, archived)
      if (archived) {
        toast.success('Recette archivée')
        navigate('recettes')
      } else {
        recipe.archived_at = null
        toast.success('Recette restaurée')
      }
    } catch (e: any) {
      toast.error(e?.message ?? 'Action impossible')
    } finally {
      deleting = false
      showDeleteConfirm = false
    }
  }
</script>

<div class="page detail">
  {#if loading}
    <a href={href('recettes')} class="back-link"><Icon name="arrow-left" size={18} /> Recettes</a>
    <div class="center-msg"><div class="spinner"></div></div>
  {:else if error}
    <a href={href('recettes')} class="back-link"><Icon name="arrow-left" size={18} /> Recettes</a>
    <ErrorState {error} message={error} />
  {:else if recipe}
    <!-- ── Photo (ou grande initiale) ── -->
    <header class="hero" class:no-photo={!heroSrc} style:--cat={catColor}>
      {#if heroSrc}
        <img
          src={heroSrc}
          alt=""
          class="hero-img"
          width={heroW}
          height={heroH}
          decoding="async"
          fetchpriority="high"
        />
      {:else}
        <span class="monogram" aria-hidden="true">{recipe.title.trim().charAt(0)}</span>
      {/if}
      <a href={href('recettes')} class="btn btn-icon hero-btn back" aria-label="Retour aux recettes">
        <Icon name="arrow-left" size={22} />
      </a>
      <!-- Pas de bouton à droite : le coin haut-droit est occupé par l'avatar (AppHeader, fixe) -->
    </header>

    <div class="content">
      <!-- ── Titre + infos ── -->
      <div class="intro">
        <h1>{recipe.title}</h1>
        <ul class="chips" aria-label="Infos">
          {#if recipe.recipe_categories}
            <li class="chip cat" style:--cat={catColor}>
              {recipe.recipe_categories.name}
            </li>
          {/if}
          {#if recipe.prep_time_min}
            <li class="chip"><Icon name="clock" size={16} /> {formatTime(recipe.prep_time_min)}</li>
          {/if}
          <li class="chip"><Icon name="users" size={16} /> {portions} portion{portions > 1 ? 's' : ''}</li>
          {#if recipe.visibility}
            <li class="chip" title="Qui voit cette recette">
              <Icon name={recipe.visibility === 'famille' ? 'lock' : 'users'} size={16} /> {visibilityLabel}
            </li>
          {/if}
        </ul>
        {#if tagChips.length > 0}
          <ul class="tags" aria-label="Étiquettes">
            {#each tagChips as t (t.label)}
              <li>
                <button type="button" class="tag tag-btn" title={t.title} onclick={() => openRecipesWithTag(t.ref)} aria-label="Voir les recettes « {t.label} »">{t.label}</button>
              </li>
            {/each}
          </ul>
        {/if}
        {#if recipe.recipe_steps.length > 0}
          <button class="btn cook-btn" onclick={() => (cookOpen = true)}>
            <Icon name="chef" size={20} />
            {doneCount > 0 && doneCount < recipe.recipe_steps.length ? 'Reprendre en cuisine' : 'En cuisine'}
            <span class="cook-hint">une étape à la fois</span>
          </button>
        {/if}
      </div>

      <!-- ── Étoiles (v2.2.0) ── -->
      <StarRating recipeId={recipe.id} />

      <div class="columns">
        <!-- ── Ingrédients ── -->
        {#if recipe.recipe_ingredients.length > 0}
          <section class="section ingredients" aria-labelledby="h-ing">
            <div class="section-head">
              <h2 id="h-ing" class="band-title">Ingrédients</h2>
              <div class="stepper" role="group" aria-label="Nombre de portions">
                <button
                  class="btn btn-icon step-btn"
                  onclick={() => setPortions(portions - 1)}
                  disabled={portions <= MIN_PORTIONS}
                  aria-label="Une portion de moins"
                ><Icon name="minus" size={18} strokeWidth={2.4} /></button>
                <output class="step-val" aria-live="polite">
                  <strong>{portions}</strong>
                  <span>pers.</span>
                </output>
                <button
                  class="btn btn-icon step-btn"
                  onclick={() => setPortions(portions + 1)}
                  disabled={portions >= MAX_PORTIONS}
                  aria-label="Une portion de plus"
                ><Icon name="plus" size={18} strokeWidth={2.4} /></button>
              </div>
            </div>

            <p class="hint">
              {#if portions !== defaultPortions}
                Quantités pour {portions} au lieu de {defaultPortions}.
                <button class="link-btn" onclick={() => (portions = defaultPortions)}>Revenir à {defaultPortions}</button>
              {:else if gotCount > 0}
                {gotCount} sur {recipe.recipe_ingredients.length} sortis du placard.
                <button class="link-btn" onclick={() => (gotIng = {})}>Tout décocher</button>
              {:else}
                Touchez un ingrédient une fois sorti du placard.
              {/if}
            </p>

            <ul class="ingredient-list card">
              {#each recipe.recipe_ingredients as ing, i (ing.id)}
                {@const qty = formatIngredient(ing.quantity, ing.unit, scale)}
                <li style="--i: {Math.min(i, 8)}">
                  <label class="row ingredient" class:got={gotIng[ing.id]}>
                    <input
                      type="checkbox"
                      class="check"
                      checked={!!gotIng[ing.id]}
                      onchange={(e) => (gotIng[ing.id] = e.currentTarget.checked)}
                    />
                    <span class="ing-name">{ing.name}</span>
                    {#if qty}<span class="ing-qty">{qty}</span>{/if}
                  </label>
                </li>
              {/each}
            </ul>
          </section>
        {/if}

        <!-- ── Étapes ── -->
        {#if recipe.recipe_steps.length > 0}
          <section class="section steps" aria-labelledby="h-steps">
            <div class="section-head">
              <h2 id="h-steps" class="band-title">Préparation</h2>
              <span class="count">{doneCount}/{recipe.recipe_steps.length}</span>
            </div>
            <p class="hint">
              {#if doneCount > 0}
                <button class="link-btn" onclick={() => (doneStep = {})}>Tout remettre à faire</button>
              {:else}
                Touchez une étape pour la marquer faite.
              {/if}
            </p>
            <ol class="step-list">
              {#each recipe.recipe_steps as step, i (step.id)}
                <li style="--i: {Math.min(i, 8)}">
                  <button
                    class="step"
                    class:done={doneStep[step.id]}
                    aria-pressed={!!doneStep[step.id]}
                    onclick={() => (doneStep[step.id] = !doneStep[step.id])}
                  >
                    <span class="step-num" aria-hidden="true">
                      {#if doneStep[step.id]}<Icon name="check" size={20} strokeWidth={2.8} />{:else}{i + 1}{/if}
                    </span>
                    <span class="step-text"><span class="sr-only">Étape {i + 1} : </span>{step.instruction}</span>
                  </button>
                </li>
              {/each}
            </ol>
          </section>
        {/if}
      </div>

      {#if canEdit}
        <div class="admin">
          <a href={href('editer-recette', recipe.id)} class="btn btn-outline admin-btn">
            <Icon name="pencil" size={18} /> Modifier
          </a>
          {#if canDelete && !isArchived}
            <button class="btn btn-outline admin-btn danger" onclick={() => (showDeleteConfirm = true)}>
              <Icon name="trash" size={18} /> Archiver
            </button>
          {/if}
        </div>
      {/if}
    </div>

    <!-- ── Barre d'actions au pouce (collée au-dessus de la barre d'onglets) ── -->
    {#if isArchived}
    <div class="action-bar archived-bar" role="status">
      <span>Recette archivée : elle n'apparaît plus dans les listes.</span>
      {#if canDelete}
        <button class="btn btn-outline act" onclick={() => setArchived(false)} disabled={deleting}>Restaurer</button>
      {/if}
    </div>
    {:else}
    <div class="action-bar">
      <button class="btn btn-primary act primary" onclick={() => (dialogMode = 'plan')}>
        <Icon name="calendar" size={19} /> Ajouter à ma semaine
      </button>
      <button class="btn btn-outline act secondary" onclick={() => (dialogMode = 'cart')} aria-label="Juste les ingrédients">
        <Icon name="cart" size={20} /> <span>Ingrédients</span>
      </button>
    </div>
    {/if}

    {#if showDeleteConfirm}
      <ConfirmDialog
        title="Archiver cette recette ?"
        confirmLabel="Archiver"
        danger
        busy={deleting}
        onconfirm={() => setArchived(true)}
        oncancel={() => (showDeleteConfirm = false)}
      >
        « {recipe.title} » disparaîtra des listes et de la recherche. Elle reste dans les plannings et l’historique, et un administrateur pourra la restaurer depuis « Recettes archivées ».
      </ConfirmDialog>
    {/if}

    {#if dialogMode}
      <PlanRecipeDialog {recipe} mode={dialogMode} onclose={() => (dialogMode = null)} />
    {/if}

    {#if cookOpen}
      <CookMode {recipe} {portions} start={cookStart} onclose={() => (cookOpen = false)} />
    {/if}
  {/if}
</div>

<style>
  .detail {
    max-width: 1080px;
    margin: 0 auto;
    padding-bottom: calc(84px + env(safe-area-inset-bottom, 0px));
  }

  .back-link {
    display: inline-flex;
    align-items: center;
    gap: 6px;
    min-height: 44px;
    margin: calc(8px + env(safe-area-inset-top, 0px)) var(--gutter) 0;
    color: var(--text);
    font-weight: var(--fw-bold);
    text-decoration: underline;
    text-decoration-thickness: 2px;
    text-underline-offset: 3px;
  }

  /* ── Grande photo : bloc carré bordé, ombre franche ── */
  .hero {
    position: relative;
    aspect-ratio: 4 / 3;
    max-height: 62svh;
    margin: calc(var(--gutter) + env(safe-area-inset-top, 0px)) var(--gutter) 0;
    overflow: hidden;
    background: var(--cat);
    border: var(--line-w) solid var(--line);
    box-shadow: var(--shadow-lg);
    container-type: inline-size;
  }
  .hero.no-photo { aspect-ratio: 16 / 10; }

  .hero-img {
    position: absolute;
    inset: 0;
    width: 100%;
    height: 100%;
    object-fit: cover;
  }

  /* Recette sans photo : grande initiale noire sur l'aplat de la catégorie */
  .monogram {
    position: absolute;
    inset: 0;
    display: flex;
    align-items: center;
    justify-content: center;
    font-family: var(--font-display);
    font-weight: var(--fw-bold);
    font-size: clamp(120px, 42cqw, 260px);
    line-height: 1;
    text-transform: uppercase;
    color: var(--ink);
  }

  .hero-btn {
    position: absolute;
    z-index: 1;
    top: var(--sp-3);
    left: var(--sp-3);
    color: var(--text);
  }

  /* ── Contenu ── */
  .content { padding: var(--sp-5) var(--gutter) var(--sp-2); }

  .intro h1 {
    font-size: clamp(30px, 8.4vw, 44px);
    overflow-wrap: break-word;
    hyphens: auto;
    text-wrap: balance;
  }

  .chips {
    list-style: none;
    margin: var(--sp-3) 0 0;
    padding: 0;
    display: flex;
    flex-wrap: wrap;
    gap: var(--sp-2);
  }

  /* Infos (temps, portions, visibilité) : simple texte avec icône, SANS cadre,
     pour ne pas ressembler à des boutons (on ne peut pas les toucher) */
  .chips .chip {
    min-height: 32px;
    padding: 0 6px 0 0;
    border-color: transparent;
    background: transparent;
    cursor: default;
    font-weight: var(--fw-bold);
    transition: none;
  }
  .chips .chip:active { transform: none; }
  .chips .chip.cat {
    padding: 0 10px;
    background: var(--cat);
    color: var(--ink);
    border-color: var(--ink);
    text-transform: uppercase;
    letter-spacing: var(--tracking-caps);
    font-size: 13px;
  }

  .tags {
    list-style: none;
    margin: var(--sp-3) 0 0;
    padding: 0;
    display: flex;
    flex-wrap: wrap;
    gap: 6px;
  }
  .tag { font-size: 13px; padding: 2px 8px; }
  /* Étiquette touchable : même dessin, zone de tap agrandie à 44 px, s'enfonce */
  .tag-btn {
    position: relative;
    min-height: 30px;
    font-family: var(--font-body);
    cursor: pointer;
    touch-action: manipulation;
    box-shadow: 2px 2px 0 var(--shadow-color);
    transition: transform var(--dur-fast) var(--ease-out);
  }
  .tag-btn::after { content: ''; position: absolute; inset: -7px -2px; }
  .tag-btn:active { transform: translate(2px, 2px); box-shadow: none; }
  @media (hover: hover) and (pointer: fine) {
    .tag-btn:hover { background: var(--accent); }
  }

  .cook-btn {
    margin-top: var(--sp-4);
    width: 100%;
    min-height: 54px;
    justify-content: flex-start;
    padding: 0 var(--sp-4);
    background: var(--band);
    color: var(--text-on-band);
    text-transform: uppercase;
    letter-spacing: 0.02em;
  }

  .cook-hint {
    margin-left: auto;
    font-size: 13px;
    font-weight: var(--fw-medium);
    text-transform: none;
    letter-spacing: 0;
  }

  .columns {
    margin-top: var(--sp-5);
    display: flex;
    flex-direction: column;
    gap: var(--sp-5);
  }

  .section-head {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: var(--sp-3);
  }

  /* Titre de rubrique : bandeau */
  .band-title {
    display: inline-block;
    padding: 5px 12px;
    background: var(--band);
    color: var(--text-on-band);
    font-size: var(--fs-base);
    font-weight: var(--fw-bold);
    text-transform: uppercase;
    letter-spacing: var(--tracking-caps);
  }

  .count {
    padding: 2px 8px;
    border: var(--line-w) solid var(--line);
    background: var(--surface);
    font-size: var(--fs-sm);
    font-weight: var(--fw-bold);
    font-variant-numeric: tabular-nums;
  }

  .hint {
    margin: var(--sp-2) 0 var(--sp-3);
    min-height: 20px;
    font-size: var(--fs-sm);
    color: var(--text-secondary);
  }

  .link-btn {
    background: none;
    border: none;
    padding: 6px 2px; /* zone de tap agrandie sans décaler le texte */
    margin: -6px 0;
    color: var(--text);
    font: inherit;
    font-weight: var(--fw-bold);
    text-decoration: underline;
    text-decoration-thickness: 2px;
    text-underline-offset: 3px;
    cursor: pointer;
    touch-action: manipulation;
  }

  /* ── Stepper portions ── */
  .stepper {
    display: inline-flex;
    align-items: center;
    gap: var(--sp-2);
  }

  .step-btn:disabled { opacity: 0.35; }

  .step-val {
    min-width: 46px;
    text-align: center;
    line-height: 1.05;
    display: flex;
    flex-direction: column;
  }
  .step-val strong {
    font-family: var(--font-display);
    font-size: 20px;
    font-variant-numeric: tabular-nums;
  }
  .step-val span {
    font-size: 11px;
    text-transform: uppercase;
    letter-spacing: var(--tracking-caps);
    color: var(--text-secondary);
  }

  /* ── Ingrédients : carte + lignes ── */
  .ingredient-list {
    list-style: none;
    margin: 0;
    padding: 0;
  }

  .ingredient-list li {
    animation: fade-up var(--dur-sheet) var(--ease-out) calc(var(--i, 0) * 45ms) backwards;
  }
  .ingredient-list li + li .ingredient { border-top: var(--line-thin) solid var(--line); }

  .ingredient {
    min-height: 52px;
    padding: 10px var(--sp-3);
    font-size: var(--fs-base);
    line-height: 1.3;
    cursor: pointer;
    touch-action: manipulation;
  }
  .ingredient:focus-within {
    outline: 3px solid var(--accent);
    outline-offset: -3px;
  }

  .ing-name {
    flex: 1;
    min-width: 0;
    overflow-wrap: break-word;
  }

  .ing-qty {
    flex-shrink: 0;
    font-weight: var(--fw-bold);
    font-variant-numeric: tabular-nums;
    text-align: right;
  }

  .ingredient.got .ing-name,
  .ingredient.got .ing-qty {
    color: var(--text-secondary);
    text-decoration: line-through;
    text-decoration-thickness: 2px;
  }

  /* ── Étapes ── */
  .step-list {
    list-style: none;
    margin: 0;
    padding: 0;
    display: flex;
    flex-direction: column;
    gap: var(--sp-3);
  }

  .step-list li {
    animation: fade-up var(--dur-sheet) var(--ease-out) calc(var(--i, 0) * 45ms) backwards;
  }

  .step {
    width: 100%;
    display: flex;
    align-items: flex-start;
    gap: var(--sp-3);
    padding: var(--sp-3);
    background: var(--surface);
    border: var(--line-w) solid var(--line);
    box-shadow: var(--shadow-sm);
    color: var(--text);
    font: inherit;
    text-align: left;
    cursor: pointer;
    touch-action: manipulation;
    transition: transform var(--dur-fast) var(--ease-out);
  }
  .step:active {
    transform: translate(var(--press), var(--press));
    box-shadow: none;
  }

  /* Numéro dans un carré noir */
  .step-num {
    flex-shrink: 0;
    width: 40px;
    height: 40px;
    background: var(--band);
    color: var(--text-on-band);
    font-family: var(--font-display);
    font-size: 20px;
    font-weight: var(--fw-bold);
    display: flex;
    align-items: center;
    justify-content: center;
  }

  .step-text {
    flex: 1;
    min-width: 0;
    padding-top: 6px;
    font-size: 17px;
    line-height: 1.55;
    overflow-wrap: break-word;
  }

  .step.done { background: var(--surface-sunken); box-shadow: none; }
  .step.done .step-text { color: var(--text-secondary); }
  .step.done .step-num { background: var(--accent); color: var(--on-accent); }

  /* ── Admin ── */
  .admin {
    display: flex;
    gap: var(--sp-3);
    margin-top: var(--sp-6);
    padding-top: var(--sp-4);
    border-top: var(--line-w) solid var(--line);
  }
  .admin-btn { flex: 1; }
  .admin-btn.danger { color: var(--error); }

  /* ── Barre d'actions collée en bas (au-dessus de la barre d'onglets, 64 px) ── */
  /* Pleine largeur, collée à la barre d'onglets, sur le fond de la page :
     la liste ne défile plus dans un interstice au-dessous */
  .action-bar {
    position: sticky;
    z-index: 50; /* sous la barre d'onglets (100) et les fenêtres (200) */
    bottom: calc(64px + env(safe-area-inset-bottom, 0px));
    margin: var(--sp-5) 0 0;
    display: flex;
    gap: var(--sp-3);
    padding: var(--sp-3) var(--gutter) calc(var(--sp-3) + 3px);
    background: var(--page);
    border-top: var(--line-w) solid var(--line);
  }

  .archived-bar {
    align-items: center;
    padding-left: var(--sp-3);
    font-size: var(--fs-sm);
    color: var(--text);
  }
  .archived-bar span { flex: 1; min-width: 0; }

  .act { white-space: nowrap; }
  /* Sans majuscules : « Ajouter à ma semaine » tient à côté du bouton Ingrédients */
  .act.primary { flex: 1; width: auto; min-width: 0; padding: 0 var(--sp-2); gap: 6px; text-transform: none; letter-spacing: 0; font-size: var(--fs-sm); }
  .act.secondary { flex: 0 0 auto; padding: 0 var(--sp-3); font-size: var(--fs-sm); }

  /* Très petits écrans : le bouton secondaire passe en icône seule */
  @media (max-width: 359px) {
    .act.secondary span { display: none; }
    .act.primary { font-size: var(--fs-sm); }
  }

  /* ── Grands écrans : photo en bandeau, ingrédients et étapes côte à côte ── */
  @media (min-width: 900px) {
    .hero {
      aspect-ratio: 3 / 1;
      max-height: 360px;
      margin-top: var(--sp-5);
    }
    .hero.no-photo { aspect-ratio: 4 / 1; }
    .content { padding: var(--sp-5) var(--gutter) var(--sp-2); }
    .intro {
      display: flex;
      flex-wrap: wrap;
      align-items: flex-end;
      column-gap: var(--sp-5);
    }
    .intro h1 { flex: 1 1 100%; }
    .cook-btn {
      width: auto;
      margin-left: auto;
      margin-top: var(--sp-3);
    }
    .columns {
      display: grid;
      grid-template-columns: minmax(300px, 380px) 1fr;
      align-items: start;
      gap: var(--sp-6);
    }
    .ingredients {
      position: sticky;
      top: 20px;
    }
    .action-bar {
      margin-inline: auto var(--gutter);
      width: min(480px, 100%);
    }
  }

  @media (hover: hover) and (pointer: fine) {
    .step:hover { background: var(--surface-hover); }
    .step.done:hover { background: var(--surface-sunken); }
    .ingredient:hover { background: var(--surface-hover); }
  }

  .center-msg {
    display: flex;
    justify-content: center;
    padding: 48px var(--sp-4);
  }


  /* Chargement : carré qui tourne par quarts (sec, pas de cercle) */
  .spinner {
    width: 28px;
    height: 28px;
    border: var(--line-w) solid var(--line);
    border-top-color: var(--accent);
    animation: spin 0.8s steps(4) infinite;
  }

  @keyframes spin {
    to { transform: rotate(360deg); }
  }
</style>
