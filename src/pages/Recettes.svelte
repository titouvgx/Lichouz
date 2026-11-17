<script lang="ts">
  import Icon from '../components/Icon.svelte'
  import { profileState } from '../lib/profile.svelte'
  import { href } from '../lib/router.svelte'
  import { sizedImage } from '../lib/images'
  import { categoryColor } from '../lib/categoryColors'
  import {
    fetchRecipeCategories,
    fetchRecipeIndex,
    fetchArchivedRecipes,
    fetchRecipesByIds,
    filterRecipeIndex,
    RECIPES_PAGE_SIZE,
    type RecipeIndexEntry,
  } from '../lib/api/recipes'
  import type { RecipeWithCategory, RecipeCategory } from '../lib/types'
  import FiltersDialog from '../components/FiltersDialog.svelte'
  import {
    BUDGETS, NO_FILTERS, REGIMES, cleanKeys, countFilters, origineLabel, regimeLabel, themeLabel, tempsLabel, budgetLabel,
    type TagFilters,
  } from '../lib/etiquettes'
  import { loadRecipeFilters, saveRecipeFilters } from '../lib/recipeFilters'

  // ── Données ──
  // index : TOUTES les recettes en version légère (id, titre, catégorie).
  // La recherche et le filtre s'appliquent sur l'index (toute la base),
  // puis on charge les recettes complètes page par page.
  let index: RecipeIndexEntry[] = $state([])
  let categories: RecipeCategory[] = $state([])
  let shown: RecipeWithCategory[] = $state([])
  let indexLoading = $state(true)
  let pageLoading = $state(false)
  let loadingMore = $state(false)
  let error = $state<string | null>(null)
  let reloadTick = $state(0)

  // Recettes archivées (migration 22) : visibles par les admins, pour les restaurer
  const canSeeArchives = $derived(
    profileState.profile?.role === 'admin' || !!profileState.context?.isSuperAdmin,
  )
  let archived = $state<RecipeWithCategory[] | null>(null)
  let archivedLoading = $state(false)
  async function toggleArchived() {
    if (archived) { archived = null; return }
    archivedLoading = true
    try {
      archived = await fetchArchivedRecipes()
    } catch (e: any) {
      error = e.message
    } finally {
      archivedLoading = false
    }
  }

  /** Recettes complètes déjà chargées (évite de redemander les mêmes). */
  const cache = new Map<string, RecipeWithCategory>()
  /** Numéro de la dernière requête : une réponse plus ancienne est ignorée. */
  let requestSeq = 0

  // ── Filtres ──
  let search = $state('')
  let query = $state('') // recherche appliquée (après le délai)
  let selectedCategory = $state<string | null>(null)

  // Filtres par étiquettes (v1.8.0), gardés pendant la session (retour depuis une fiche,
  // ou étiquette touchée sur une fiche : src/lib/recipeFilters.ts)
  let tagFilters = $state<TagFilters>(loadRecipeFilters())
  let filtersOpen = $state(false)
  const activeFilters = $derived(countFilters(tagFilters))
  $effect(() => saveRecipeFilters($state.snapshot(tagFilters)))
  const usedOrigins = $derived(new Set(index.map((r) => r.origin).filter((o): o is string => !!o)))

  /** Puces des filtres actifs (un appui les retire). */
  const activeChips = $derived.by(() => {
    const f = tagFilters
    const out: { label: string; remove: () => void }[] = []
    for (const d of f.diets) out.push({ label: regimeLabel(d), remove: () => (tagFilters = { ...tagFilters, diets: tagFilters.diets.filter((x) => x !== d) }) })
    if (f.budgetMax) out.push({ label: `Budget ≤ ${BUDGETS.find((b) => b.value === f.budgetMax)?.label}`, remove: () => (tagFilters = { ...tagFilters, budgetMax: null }) })
    for (const t of f.themes) out.push({ label: themeLabel(t), remove: () => (tagFilters = { ...tagFilters, themes: tagFilters.themes.filter((x) => x !== t) }) })
    for (const o of f.origins) out.push({ label: origineLabel(o), remove: () => (tagFilters = { ...tagFilters, origins: tagFilters.origins.filter((x) => x !== o) }) })
    if (f.timeMax) out.push({ label: `${tempsLabel(f.timeMax)} max`, remove: () => (tagFilters = { ...tagFilters, timeMax: null }) })
    return out
  })

  // Délai de 250 ms pendant la frappe ; effacer s'applique tout de suite.
  $effect(() => {
    const value = search.trim()
    if (!value) {
      query = ''
      return
    }
    const t = setTimeout(() => (query = value), 250)
    return () => clearTimeout(t)
  })

  // ── Chargement de l'index + catégories ──
  // Les recettes sont partagées entre tous les foyers (RLS is_member()) :
  // pas besoin d'attendre le profil pour les charger.
  $effect(() => {
    void reloadTick
    indexLoading = true
    error = null
    let cancelled = false

    Promise.all([fetchRecipeIndex(), fetchRecipeCategories()])
      .then(([idx, cats]) => {
        if (cancelled) return
        index = idx
        categories = cats
      })
      .catch((e) => {
        if (!cancelled) error = e?.message ?? 'Impossible de charger les recettes.'
      })
      .finally(() => {
        if (!cancelled) indexLoading = false
      })

    return () => { cancelled = true }
  })

  // Profil chargé mais sans foyer : la base ne renvoie aucune recette
  const noFamily = $derived(!profileState.loading && !profileState.profile?.family_id)

  /** Étiquettes affichées sur une carte (v1.99.0) : 2 régimes au plus + budget, pour rester sur une ligne. */
  function cardTags(r: RecipeWithCategory): string[] {
    const out = cleanKeys(r.diets ?? [], REGIMES).slice(0, 2).map(regimeLabel)
    if (r.budget) out.push(budgetLabel(r.budget))
    return out
  }

  // Toute la base filtrée (instantané, côté client)
  const matches = $derived(filterRecipeIndex(index, query, selectedCategory, tagFilters))
  const hasMore = $derived(shown.length < matches.length)
  const isFiltered = $derived(!!query || !!selectedCategory || activeFilters > 0)

  /** Charge (si besoin) les recettes complètes d'une liste d'id. */
  async function resolve(ids: string[]): Promise<RecipeWithCategory[]> {
    const missing = ids.filter((id) => !cache.has(id))
    if (missing.length > 0) {
      for (const r of await fetchRecipesByIds(missing)) cache.set(r.id, r)
    }
    return ids.map((id) => cache.get(id)).filter((r): r is RecipeWithCategory => !!r)
  }

  // Première page à chaque changement de recherche / catégorie
  $effect(() => {
    if (indexLoading || error) return
    const ids = matches.slice(0, RECIPES_PAGE_SIZE).map((r) => r.id)
    const seq = ++requestSeq
    loadingMore = false

    // Tout est déjà en cache : pas de requête
    if (ids.every((id) => cache.has(id))) {
      shown = ids.map((id) => cache.get(id)!)
      pageLoading = false
      return
    }

    pageLoading = true
    resolve(ids)
      .then((list) => {
        if (seq !== requestSeq) return // réponse obsolète
        shown = list
      })
      .catch((e) => {
        if (seq === requestSeq) error = e?.message ?? 'Impossible de charger les recettes.'
      })
      .finally(() => {
        if (seq === requestSeq) pageLoading = false
      })
  })

  // Page suivante (dans les résultats filtrés)
  async function loadMore() {
    if (loadingMore || pageLoading) return
    const ids = matches.slice(shown.length, shown.length + RECIPES_PAGE_SIZE).map((r) => r.id)
    if (ids.length === 0) return
    const seq = requestSeq
    loadingMore = true
    try {
      const list = await resolve(ids)
      if (seq !== requestSeq) return // la recherche a changé entre-temps
      shown = [...shown, ...list]
    } catch (e: any) {
      if (seq === requestSeq) error = e?.message ?? 'Impossible de charger la suite.'
    } finally {
      if (seq === requestSeq) loadingMore = false
    }
  }

  function retry() {
    cache.clear()
    shown = []
    reloadTick++
  }

  function clearFilters() {
    search = ''
    query = ''
    selectedCategory = null
    tagFilters = { ...NO_FILTERS }
  }

  function formatTime(min: number | null): string {
    if (!min) return ''
    if (min < 60) return `${min} min`
    const h = Math.floor(min / 60)
    const m = min % 60
    return m ? `${h}h${String(m).padStart(2, '0')}` : `${h}h`
  }

  const countLabel = $derived.by(() => {
    if (isFiltered) {
      const n = matches.length
      return n === 0 ? 'Aucun résultat' : `${n} résultat${n > 1 ? 's' : ''}`
    }
    const n = index.length
    return `${n} recette${n > 1 ? 's' : ''}`
  })
</script>

<div class="page">
  <header class="head deco-boules">
    <h1>Recettes</h1>
    {#if !indexLoading && !error && index.length > 0}
      <p class="head-sub" aria-live="polite">{countLabel}</p>
    {/if}
  </header>

  <!-- Barre de recherche + filtres -->
  <div class="search-row">
  <div class="search-bar" role="search">
    <svg class="search-icon" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="square" aria-hidden="true">
      <circle cx="11" cy="11" r="7"/><path d="m21 21-5-5"/>
    </svg>
    <input
      type="search"
      class="search-input"
      placeholder="Rechercher…"
      aria-label="Rechercher une recette"
      autocomplete="off"
      enterkeyhint="search"
      bind:value={search}
    />
    {#if search}
      <button class="search-clear" onclick={() => { search = ''; query = '' }} aria-label="Effacer la recherche">
        <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="square" aria-hidden="true"><path d="M18 6 6 18M6 6l12 12"/></svg>
      </button>
    {/if}
  </div>
  <button
    class="filter-btn"
    class:on={activeFilters > 0}
    onclick={() => (filtersOpen = true)}
    aria-haspopup="dialog"
    aria-label={activeFilters > 0 ? `Filtres (${activeFilters} actif${activeFilters > 1 ? 's' : ''})` : 'Filtres'}
  >
    <Icon name="filter" size={20} />
    <span class="filter-txt">Filtres</span>
    {#if activeFilters > 0}<span class="filter-count" aria-hidden="true">{activeFilters}</span>{/if}
  </button>
  </div>

  {#if activeChips.length > 0}
    <ul class="active-filters" aria-label="Filtres actifs">
      {#each activeChips as c (c.label)}
        <li>
          <button class="active-chip" onclick={c.remove} aria-label="Retirer le filtre {c.label}">
            {c.label} <Icon name="x" size={14} />
          </button>
        </li>
      {/each}
    </ul>
  {/if}

  <!-- Puces de catégorie (défilement horizontal sur téléphone) -->
  {#if categories.length > 0}
    <div class="chips" role="group" aria-label="Catégories">
      <button
        class="chip"
        class:active={!selectedCategory}
        onclick={() => (selectedCategory = null)}
        aria-pressed={!selectedCategory}
      >Tout</button>
      {#each categories as cat (cat.id)}
        <button
          class="chip"
          class:active={selectedCategory === cat.id}
          onclick={() => (selectedCategory = selectedCategory === cat.id ? null : cat.id)}
          aria-pressed={selectedCategory === cat.id}
          style="--chip-color: {categoryColor(cat.name)}"
        ><span class="chip-dot" aria-hidden="true"></span>{cat.name}</button>
      {/each}
    </div>
  {/if}

  <!-- Contenu -->
  {#if indexLoading || (pageLoading && shown.length === 0 && matches.length > 0)}
    <div class="recipe-grid" aria-busy="true" aria-label="Chargement des recettes">
      {#each Array(6) as _, i (i)}
        <div class="recipe-card skeleton" style="animation-delay: {i * 80}ms">
          <div class="card-visual"></div>
          <div class="card-body">
            <span class="sk-line sk-short"></span>
            <span class="sk-line"></span>
            <span class="sk-line sk-mid"></span>
          </div>
        </div>
      {/each}
    </div>
  {:else if error}
    <div class="card state">
      <p class="state-title">Oups, les recettes n’ont pas pu être chargées</p>
      <p class="state-text error-text">{error}</p>
      <button class="btn btn-outline state-btn" onclick={retry}>
        <Icon name="refresh" /> Réessayer
      </button>
    </div>
  {:else if index.length === 0}
    <div class="card state">
      <span class="state-icon"><Icon name="book" size={44} strokeWidth={1.5} /></span>
      {#if noFamily}
        <p class="state-title">Profil introuvable</p>
        <p class="state-text">Vérifie que ton compte est bien lié à un foyer.</p>
      {:else}
        <p class="state-title">Aucune recette pour le moment</p>
        <p class="state-text">Ajoute ta première recette, elle sera partagée avec tout ton foyer.</p>
        <a href="#/nouvelle-recette" class="btn btn-primary state-cta">Ajouter une recette</a>
      {/if}
    </div>
  {:else if matches.length === 0}
    <div class="card state">
      <svg class="state-icon" width="40" height="40" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" aria-hidden="true">
        <circle cx="11" cy="11" r="8"/><path d="m21 21-4.35-4.35M8 11h6"/>
      </svg>
      <p class="state-title">Aucun résultat</p>
      <p class="state-text">
        {#if query}Aucune recette ne correspond à « {query} »{:else if activeFilters > 0}Aucune recette ne correspond à ces filtres{:else}Aucune recette dans cette catégorie{/if}{#if (query || activeFilters > 0) && selectedCategory} dans cette catégorie{/if}{#if query && activeFilters > 0} avec ces filtres{/if}.
      </p>
      <button class="btn btn-outline state-btn" onclick={clearFilters}>Tout afficher</button>
    </div>
  {:else}
    <div class="recipe-grid" class:refreshing={pageLoading}>
      {#each shown as recipe, i (recipe.id)}
        <a href={href('recette', recipe.id)} class="recipe-card" style="--i: {Math.min(i, 8)}">
          <div class="card-visual" style="--cat: {categoryColor(recipe.recipe_categories?.name)}">
            {#if sizedImage(recipe.image_url, 240, 180)}
              <img
                src={sizedImage(recipe.image_url, 240, 180)}
                alt=""
                class="card-img"
                loading="lazy"
                decoding="async"
              />
            {:else}
              <span class="card-initial" aria-hidden="true">{recipe.title.trim().charAt(0)}</span>
            {/if}
          </div>
          <div class="card-body">
            {#if recipe.recipe_categories}
              <span class="card-badge" style="--cat: {categoryColor(recipe.recipe_categories.name)}">{recipe.recipe_categories.name}</span>
            {/if}
            <h2 class="card-title">{recipe.title}</h2>
            <div class="card-meta">
              <span><Icon name="users" size={13} /> {recipe.default_portions} parts</span>
              {#if recipe.prep_time_min}
                <span><Icon name="clock" size={13} /> {formatTime(recipe.prep_time_min)}</span>
              {/if}
            </div>
            {#if cardTags(recipe).length > 0}
              <ul class="card-tags" aria-label="Étiquettes">
                {#each cardTags(recipe) as t (t)}<li>{t}</li>{/each}
              </ul>
            {/if}
          </div>
        </a>
      {/each}
    </div>

    {#if hasMore}
      <div class="load-more-wrap">
        <button class="btn btn-outline btn-load-more" onclick={loadMore} disabled={loadingMore || pageLoading}>
          {#if loadingMore}
            <span class="btn-spinner"></span>
            Chargement…
          {:else}
            Voir plus ({matches.length - shown.length})
          {/if}
        </button>
      </div>
    {/if}
  {/if}

  {#if canSeeArchives && !indexLoading}
    <section class="archives">
      <button class="btn btn-outline" onclick={toggleArchived} disabled={archivedLoading} aria-expanded={!!archived}>
        {archived ? 'Masquer les recettes archivées' : 'Recettes archivées'}
      </button>
      {#if archived}
        {#if archived.length === 0}
          <p class="archives-empty">Aucune recette archivée.</p>
        {:else}
          <ul>
            {#each archived as r (r.id)}
              <li><a href={href('recette', r.id)}>{r.title}</a></li>
            {/each}
          </ul>
        {/if}
      {/if}
    </section>
  {/if}

  <!-- FAB : ajouter une recette (au-dessus de la barre d'onglets) -->
  <a href="#/nouvelle-recette" class="fab" aria-label="Nouvelle recette">
    <svg width="28" height="28" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="3" stroke-linecap="square" aria-hidden="true">
      <path d="M12 5v14M5 12h14"/>
    </svg>
  </a>
  {#if filtersOpen}
    <FiltersDialog bind:filters={tagFilters} resultCount={matches.length} {usedOrigins} onclose={() => (filtersOpen = false)} />
  {/if}
</div>

<style>
  .page {
    padding: var(--gutter);
    padding-top: calc(var(--gutter) + env(safe-area-inset-top, 0px));
    /* Place pour le bouton + sous la dernière rangée */
    padding-bottom: calc(var(--gutter) + 76px);
    max-width: 1400px;
    margin: 0 auto;
  }

  /* ── En-tête ── */
  .head { margin-bottom: var(--sp-4); }

  .head h1 { padding-right: 56px; /* avatar en haut à droite */ }

  .head-sub {
    margin-top: var(--sp-1);
    font-size: 15px;
    font-weight: var(--fw-medium);
    color: var(--text-secondary);
  }

  /* ── Recherche ── */
  .search-row {
    display: flex;
    gap: 10px;
    margin-bottom: var(--sp-3);
    max-width: 640px;
  }

  .search-bar {
    position: relative;
    flex: 1;
    min-width: 0;
  }

  .search-icon {
    position: absolute;
    left: 13px;
    top: 50%;
    transform: translateY(-50%);
    color: var(--text);
    pointer-events: none;
  }

  .search-input {
    width: 100%;
    height: 48px;
    padding: 0 44px 0 42px;
    border: var(--line-w) solid var(--line);
    border-radius: 0;
    background: var(--bg);
    color: var(--text);
    font-family: var(--font-body);
    font-size: var(--fs-base);
    outline: none;
    -webkit-appearance: none;
    appearance: none;
  }

  .search-input::-webkit-search-cancel-button { display: none; }
  .search-input::placeholder { color: var(--text-placeholder); opacity: 1; }
  .search-input:focus { box-shadow: var(--shadow-sm); }

  .search-clear {
    position: absolute;
    right: 2px;
    top: 50%;
    transform: translateY(-50%);
    width: 44px;
    height: 44px;
    display: flex;
    align-items: center;
    justify-content: center;
    border: none;
    background: none;
    color: var(--text);
    cursor: pointer;
    touch-action: manipulation;
  }

  .filter-btn {
    flex-shrink: 0;
    display: inline-flex;
    align-items: center;
    gap: 6px;
    min-height: 48px;
    min-width: 48px;
    padding: 0 14px;
    border: var(--line-w) solid var(--line);
    background: var(--surface);
    color: var(--text);
    box-shadow: var(--shadow-sm);
    font-family: var(--font-body);
    font-size: 15px;
    font-weight: var(--fw-bold);
    cursor: pointer;
    touch-action: manipulation;
    transition: transform var(--dur-fast) var(--ease-out);
  }
  .filter-btn:active { transform: translate(var(--press), var(--press)); box-shadow: none; }
  .filter-btn.on { background: var(--accent); color: var(--on-accent); }

  .filter-count {
    display: inline-grid;
    place-items: center;
    min-width: 22px;
    height: 22px;
    padding: 0 4px;
    background: var(--ink);
    color: var(--butter);
    font-size: 12px;
    font-weight: var(--fw-bold);
  }

  @media (max-width: 360px) { .filter-txt { display: none; } }

  /* Filtres actifs : étiquettes à retirer d'un tap */
  .active-filters {
    list-style: none;
    margin: 0 0 var(--sp-3);
    padding: 0;
    display: flex;
    flex-wrap: wrap;
    gap: var(--sp-2);
  }

  .active-chip {
    position: relative;
    display: inline-flex;
    align-items: center;
    gap: 4px;
    min-height: 36px;
    padding: 0 8px 0 10px;
    border: var(--line-w) solid var(--line);
    background: var(--highlight);
    color: var(--text);
    font-family: var(--font-body);
    font-size: 13px;
    font-weight: var(--fw-bold);
    cursor: pointer;
    touch-action: manipulation;
  }
  /* zone de tap agrandie à 44 px sans changer le dessin */
  .active-chip::after { content: ''; position: absolute; inset: -4px 0; }

  /* ── Puces de catégorie ── */
  .chips {
    display: flex;
    gap: var(--sp-2);
    overflow-x: auto;
    margin: 0 calc(var(--gutter) * -1) var(--sp-4);
    padding: 2px var(--gutter) 6px; /* place pour l'ombre */
    scrollbar-width: none;
    -webkit-overflow-scrolling: touch;
  }
  .chips::-webkit-scrollbar { display: none; }

  .chip { min-height: 44px; flex-shrink: 0; }

  /* Petit carré de la couleur de la catégorie */
  .chip-dot {
    width: 10px;
    height: 10px;
    background: var(--chip-color);
    border: var(--line-thin) solid var(--ink);
  }

  /* ── Grille de recettes ── */
  .recipe-grid {
    display: grid;
    grid-template-columns: repeat(2, minmax(0, 1fr));
    gap: 14px;
    transition: opacity var(--dur-base);
  }

  .recipe-grid.refreshing { opacity: 0.55; }

  @media (min-width: 640px) {
    .recipe-grid { grid-template-columns: repeat(3, minmax(0, 1fr)); gap: 16px; }
  }
  @media (min-width: 960px) {
    .recipe-grid { grid-template-columns: repeat(4, minmax(0, 1fr)); gap: 18px; }
  }
  @media (min-width: 1240px) {
    .recipe-grid { grid-template-columns: repeat(5, minmax(0, 1fr)); }
  }

  /* Carte : bloc carré, ombre franche ; apparaît en montant, l'une après l'autre */
  .recipe-card {
    display: flex;
    flex-direction: column;
    min-width: 0;
    background: var(--surface);
    border: var(--line-w) solid var(--line);
    box-shadow: var(--shadow-md);
    color: var(--text);
    text-decoration: none;
    touch-action: manipulation;
    animation: fade-up var(--dur-sheet) var(--ease-out) calc(var(--i, 0) * 45ms) backwards;
    transition: transform var(--dur-fast) var(--ease-out);
  }

  .recipe-card:active { transform: translate(4px, 4px); box-shadow: none; }

  .card-visual {
    position: relative;
    aspect-ratio: 4 / 3;
    overflow: hidden;
    background: var(--cat, var(--surface-sunken));
    border-bottom: var(--line-w) solid var(--line);
  }

  .card-img {
    width: 100%;
    height: 100%;
    object-fit: cover;
    display: block;
  }

  /* Recette sans photo : grande initiale noire sur l'aplat de la catégorie */
  .card-initial {
    position: absolute;
    inset: 0;
    display: flex;
    align-items: center;
    justify-content: center;
    font-family: var(--font-display);
    font-size: 72px;
    font-weight: var(--fw-bold);
    line-height: 1;
    text-transform: uppercase;
    color: var(--ink);
  }

  .card-body {
    display: flex;
    flex-direction: column;
    gap: 5px;
    padding: 9px 10px 11px;
    min-width: 0;
  }

  .card-badge {
    align-self: flex-start;
    max-width: 100%;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
    padding: 1px 5px;
    border: var(--line-thin) solid var(--ink);
    background: var(--cat);
    color: var(--ink);
    font-size: 10px;
    font-weight: var(--fw-bold);
    letter-spacing: var(--tracking-caps);
    text-transform: uppercase;
  }

  .card-title {
    font-size: 15px;
    font-weight: var(--fw-bold);
    line-height: 1.2;
    letter-spacing: -0.01em;
    display: -webkit-box;
    -webkit-line-clamp: 2;
    line-clamp: 2;
    -webkit-box-orient: vertical;
    overflow: hidden;
    overflow-wrap: break-word;
    hyphens: auto;
  }

  .card-meta {
    display: flex;
    flex-wrap: wrap;
    gap: 4px 10px;
    font-size: 12px;
    color: var(--text-secondary);
  }

  .card-meta span {
    display: inline-flex;
    align-items: center;
    gap: 3px;
    white-space: nowrap;
  }

  /* Étiquettes de la carte : petites, carrées, sur une ligne */
  .card-tags {
    list-style: none;
    margin: 2px 0 0;
    padding: 0;
    display: flex;
    flex-wrap: wrap;
    gap: 4px;
  }
  .card-tags li {
    padding: 0 5px;
    border: var(--line-thin) solid var(--line);
    background: var(--surface-sunken);
    font-size: 11px;
    font-weight: var(--fw-medium);
    line-height: 18px;
    white-space: nowrap;
  }

  /* ── Chargement ── */
  .skeleton { animation: sk-pulse 1s ease-in-out infinite alternate; }
  .skeleton .card-visual { background: var(--surface-sunken); }

  .sk-line {
    display: block;
    width: 90%;
    height: 12px;
    background: var(--surface-sunken);
  }
  .sk-short { width: 40%; height: 10px; }
  .sk-mid { width: 65%; }

  @keyframes sk-pulse {
    from { opacity: 1; }
    to   { opacity: 0.5; }
  }

  /* ── États (vide, erreur) ── */
  .state {
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: var(--sp-2);
    padding: 32px 20px;
    text-align: center;
  }

  .state-icon { color: var(--text); }

  .state-title {
    font-size: var(--fs-lg);
    font-weight: var(--fw-bold);
  }

  .state-text {
    font-size: var(--fs-sm);
    color: var(--text-secondary);
    max-width: 320px;
  }

  .error-text { color: var(--error); }

  .state-btn { margin-top: var(--sp-2); }
  .state-cta { margin-top: var(--sp-3); width: auto; padding: 0 24px; }

  /* ── Voir plus ── */
  .load-more-wrap {
    display: flex;
    justify-content: center;
    margin-top: var(--sp-5);
  }

  .btn-spinner {
    width: 14px;
    height: 14px;
    background: var(--accent);
    border: var(--line-w) solid var(--line);
    animation: spin 0.6s var(--ease-snap) infinite;
  }

  @keyframes spin { to { transform: rotate(90deg); } }

  /* ── Archives ── */
  .archives {
    margin: 32px 0 8px;
    display: flex;
    flex-direction: column;
    align-items: flex-start;
    gap: var(--sp-3);
  }
  .archives ul {
    list-style: none;
    margin: 0;
    padding: 0;
    width: 100%;
    background: var(--surface);
    border: var(--line-w) solid var(--line);
  }
  .archives li + li { border-top: var(--line-thin) solid var(--line); }
  .archives li a {
    display: flex;
    align-items: center;
    min-height: 48px;
    padding: 0 var(--sp-3);
    color: var(--text);
    font-weight: var(--fw-medium);
    text-decoration: none;
  }
  .archives-empty { margin: 0; color: var(--text-secondary); font-size: var(--fs-sm); }

  /* Le bouton + : styles communs dans app.css (.fab) */
  .fab { text-decoration: none; touch-action: manipulation; }

  @media (hover: hover) and (pointer: fine) {
    .recipe-card:hover { transform: translate(-2px, -2px); box-shadow: var(--shadow-lg); }
    .filter-btn:hover:not(.on) { background: var(--surface-hover); }
    .archives li a:hover { background: var(--surface-hover); }
  }
</style>
