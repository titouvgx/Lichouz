<script lang="ts">
  // Tendances (#/tendances, v2.3.0) : top des recettes par étoiles (25 ou 50),
  // les plus cuisinées du mois dans mon foyer, les nouvelles recettes.
  // Chaque bloc se charge seul : si l'un échoue, les autres s'affichent.
  import Icon from '../components/Icon.svelte'
  import ErrorState from '../components/ErrorState.svelte'
  import { sizedImage } from '../lib/images'
  import { categoryColor } from '../lib/categoryColors'
  import { profileState } from '../lib/profile.svelte'
  import { href } from '../lib/router.svelte'
  import { fetchRecipesByIds } from '../lib/api/recipes'
  import { formatAverage } from '../lib/api/ratings'
  import {
    fetchTopRated, fetchMostCooked, fetchNewRecipes,
    type RankedRecipe, type CookedCount,
  } from '../lib/tendances'
  import type { RecipeWithCategory } from '../lib/types'

  let topSize = $state<25 | 50>(25)

  // Top par étoiles : on charge 50 une fois, on affiche 25 ou 50
  let top = $state<RankedRecipe[]>([])
  let topLoading = $state(true)
  let topError = $state<string | null>(null)

  let cooked = $state<CookedCount[]>([])
  let cookedLoading = $state(true)
  let cookedError = $state<string | null>(null)

  let fresh = $state<RecipeWithCategory[]>([])
  let freshLoading = $state(true)
  let freshError = $state<string | null>(null)

  /** Photos et catégories des recettes affichées (top + plus cuisinées) */
  let details = $state(new Map<string, RecipeWithCategory>())

  const shownTop = $derived(top.slice(0, topSize))
  const monthName = new Date().toLocaleDateString('fr-FR', { month: 'long' })

  async function loadDetails(ids: string[]) {
    const missing = ids.filter((id) => !details.has(id))
    if (!missing.length) return
    try {
      const rows = await fetchRecipesByIds(missing)
      const next = new Map(details)
      for (const r of rows) next.set(r.id, r)
      details = next
    } catch { /* les lignes s'affichent sans photo */ }
  }

  $effect(() => {
    topLoading = true
    fetchTopRated(50)
      .then((r) => { top = r; void loadDetails(r.map((x) => x.id)) })
      .catch((e: any) => (topError = e?.message ?? 'Chargement impossible'))
      .finally(() => (topLoading = false))

    fetchNewRecipes(10)
      .then((r) => (fresh = r))
      .catch((e: any) => (freshError = e?.message ?? 'Chargement impossible'))
      .finally(() => (freshLoading = false))
  })

  $effect(() => {
    if (profileState.loading) return
    const familyId = profileState.profile?.family_id
    if (!familyId) { cookedLoading = false; return }
    cookedLoading = true
    fetchMostCooked(familyId, 10)
      .then((r) => { cooked = r; void loadDetails(r.map((x) => x.recipeId)) })
      .catch((e: any) => (cookedError = e?.message ?? 'Chargement impossible'))
      .finally(() => (cookedLoading = false))
  })

  function dayLabel(iso: string): string {
    return new Date(iso).toLocaleDateString('fr-FR', { day: 'numeric', month: 'short' })
  }
</script>

{#snippet thumb(r: RecipeWithCategory | undefined, title: string)}
  <span class="thumb" style="--cat: {categoryColor(r?.recipe_categories?.name)}" aria-hidden="true">
    {#if r && sizedImage(r.image_url, 96, 96)}
      <img src={sizedImage(r.image_url, 96, 96)} alt="" loading="lazy" decoding="async" />
    {:else}
      <span class="thumb-initial">{title.trim().charAt(0)}</span>
    {/if}
  </span>
{/snippet}

<div class="page">
  <header class="head deco-boules">
    <h1>Tendances</h1>
    <p class="head-sub">Ce que la famille aime et cuisine.</p>
  </header>

  <!-- Top par étoiles -->
  <section class="group card" aria-labelledby="t-top">
    <h2 id="t-top" class="band">Les mieux notées <Icon name="star" size={16} /></h2>
    <div class="switch" role="group" aria-label="Taille du classement">
      <button class="chip" aria-pressed={topSize === 25} onclick={() => (topSize = 25)}>Top 25</button>
      <button class="chip" aria-pressed={topSize === 50} onclick={() => (topSize = 50)}>Top 50</button>
    </div>
    {#if topLoading}
      <p class="muted pad" aria-busy="true">Chargement…</p>
    {:else if topError}
      <div class="pad"><ErrorState error={topError} message={topError} /></div>
    {:else if top.length === 0}
      <p class="muted pad">Aucune recette notée pour l’instant. Mets des étoiles sur une fiche recette pour lancer le classement.</p>
    {:else}
      <ol>
        {#each shownTop as r, i (r.id)}
          <li class="row" style="--i: {Math.min(i, 8)}">
            <a class="row-main" href={href('recette', r.id)}>
              <span class="rank" class:podium={i < 3}>{i + 1}</span>
              {@render thumb(details.get(r.id), r.title)}
              <span class="row-text">
                <span class="row-title">{r.title}</span>
                <span class="row-meta">
                  <Icon name="star" size={14} /> {formatAverage(r.average)}
                  · {r.votes} vote{r.votes > 1 ? 's' : ''}
                </span>
              </span>
            </a>
          </li>
        {/each}
      </ol>
      {#if topSize === 50 && top.length <= 25}
        <p class="muted small pad">Seulement {top.length} recette{top.length > 1 ? 's' : ''} notée{top.length > 1 ? 's' : ''} pour l’instant.</p>
      {/if}
    {/if}
  </section>

  <!-- Plus cuisinées du mois (mon foyer) -->
  <section class="group card" aria-labelledby="t-cooked">
    <h2 id="t-cooked" class="band">Chez nous en {monthName} <Icon name="flame" size={16} /></h2>
    {#if cookedLoading}
      <p class="muted pad" aria-busy="true">Chargement…</p>
    {:else if cookedError}
      <div class="pad"><ErrorState error={cookedError} message={cookedError} /></div>
    {:else if cooked.length === 0}
      <p class="muted pad">Rien de cuisiné ce mois-ci pour l’instant. Les repas de la Semaine comptent dès que leur jour est passé.</p>
    {:else}
      <ol>
        {#each cooked as c, i (c.recipeId)}
          {@const r = details.get(c.recipeId)}
          <li class="row" style="--i: {Math.min(i, 8)}">
            <a class="row-main" href={href('recette', c.recipeId)}>
              <span class="rank" class:podium={i < 3}>{i + 1}</span>
              {@render thumb(r, r?.title ?? '?')}
              <span class="row-text">
                <span class="row-title">{r?.title ?? 'Recette'}</span>
                <span class="row-meta">{c.count} fois</span>
              </span>
            </a>
          </li>
        {/each}
      </ol>
    {/if}
  </section>

  <!-- Nouvelles recettes -->
  <section class="group card" aria-labelledby="t-new">
    <h2 id="t-new" class="band">Nouvelles recettes <Icon name="plus" size={16} /></h2>
    {#if freshLoading}
      <p class="muted pad" aria-busy="true">Chargement…</p>
    {:else if freshError}
      <div class="pad"><ErrorState error={freshError} message={freshError} /></div>
    {:else if fresh.length === 0}
      <p class="muted pad">Pas de nouvelle recette ces 30 derniers jours.</p>
    {:else}
      <ul>
        {#each fresh as r, i (r.id)}
          <li class="row" style="--i: {Math.min(i, 8)}">
            <a class="row-main" href={href('recette', r.id)}>
              {@render thumb(r, r.title)}
              <span class="row-text">
                <span class="row-title">{r.title}</span>
                <span class="row-meta">Ajoutée le {dayLabel(r.created_at)}</span>
              </span>
            </a>
          </li>
        {/each}
      </ul>
    {/if}
  </section>
</div>

<style>
  .page {
    padding: var(--gutter);
    padding-top: calc(var(--gutter) + env(safe-area-inset-top, 0px));
    padding-bottom: calc(84px + env(safe-area-inset-bottom, 0px));
    max-width: 640px;
    margin: 0 auto;
    display: flex;
    flex-direction: column;
    gap: var(--sp-4);
  }
  .head h1 { padding-right: 56px; /* avatar en haut à droite */ }
  .head-sub { margin-top: var(--sp-1); font-size: 15px; font-weight: var(--fw-medium); color: var(--text-secondary); }

  .group { padding: 0 0 var(--sp-1); }
  .group h2.band { font-size: 13px; letter-spacing: var(--tracking-caps); }
  .group ol, .group ul { list-style: none; margin: 0; padding: 0; }
  .pad { padding: var(--sp-3); }
  .muted { color: var(--text-secondary); }
  .small { font-size: 13px; }

  .switch { display: flex; gap: var(--sp-2); padding: var(--sp-3) var(--sp-3) var(--sp-1); }

  .group .row {
    display: block;
    min-height: 0;
    padding: var(--sp-1) var(--sp-3);
    animation: fade-up var(--dur-sheet) var(--ease-out) calc(var(--i, 0) * 45ms) backwards;
  }
  .row-main {
    display: flex;
    align-items: center;
    gap: var(--sp-3);
    min-height: 56px;
    color: var(--text);
    text-decoration: none;
    touch-action: manipulation;
  }
  .row-main:active .row-title { text-decoration: underline; }
  .row-text { display: flex; flex-direction: column; min-width: 0; gap: 2px; }
  .row-title { font-weight: var(--fw-bold); overflow-wrap: anywhere; }
  .row-meta { display: inline-flex; align-items: center; gap: 4px; font-size: 13px; color: var(--text-secondary); }

  .rank {
    flex: none;
    display: grid;
    place-items: center;
    width: 30px;
    height: 30px;
    border: var(--line-w) solid var(--line);
    background: var(--surface);
    font-weight: var(--fw-bold);
    font-size: 14px;
  }
  .rank.podium { background: var(--accent); color: var(--on-accent); box-shadow: var(--shadow-sm); }

  .thumb {
    flex: none;
    display: grid;
    place-items: center;
    width: 48px;
    height: 48px;
    overflow: hidden;
    border: var(--line-w) solid var(--line);
    background: var(--cat);
  }
  .thumb img { width: 100%; height: 100%; object-fit: cover; }
  .thumb-initial { font-weight: var(--fw-bold); font-size: 20px; color: var(--text); }

  @media (prefers-reduced-motion: reduce) {
    .group .row { animation: none; }
  }
</style>
