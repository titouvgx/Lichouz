<script lang="ts">
  // « Mes recettes » (#/mes-recettes), depuis Mon compte : les recettes dont je
  // suis l'auteur, rangées en « Toutes nos familles », « Ma famille seulement »
  // et « Archivées ». Actions : modifier, changer qui la voit, archiver /
  // restaurer (admin de la famille). Le catalogue n'apparaît pas ici.
  // Les droits sont vérifiés par la base : l'écran ne fait que montrer les bons boutons.
  import Icon from '../components/Icon.svelte'
  import ErrorState from '../components/ErrorState.svelte'
  import { sizedImage } from '../lib/images'
  import { categoryColor } from '../lib/categoryColors'
  import { auth } from '../lib/auth.svelte'
  import { profileState } from '../lib/profile.svelte'
  import { href } from '../lib/router.svelte'
  import { toast } from '../lib/toast.svelte'
  import {
    fetchMyRecipes, groupMyRecipes, setRecipeVisibility, setRecipeArchived,
  } from '../lib/api/recipes'
  import type { RecipeWithCategory } from '../lib/types'

  const isAdmin = $derived(profileState.profile?.role === 'admin' || !!profileState.context?.isSuperAdmin)
  const userId = $derived(auth.user?.id ?? null)

  let recipes = $state<RecipeWithCategory[]>([])
  let loading = $state(true)
  let loadError = $state<string | null>(null)
  let busyId = $state<string | null>(null)

  const groups = $derived(groupMyRecipes(recipes))

  $effect(() => {
    const id = userId
    if (!id) return
    loading = true
    loadError = null
    fetchMyRecipes(id)
      .then((r) => (recipes = r))
      .catch((e: any) => (loadError = e?.message ?? 'Chargement impossible'))
      .finally(() => (loading = false))
  })

  function patch(id: string, change: Partial<RecipeWithCategory>) {
    recipes = recipes.map((r) => (r.id === id ? { ...r, ...change } : r))
  }

  async function toggleShare(r: RecipeWithCategory) {
    if (busyId) return
    const next = r.visibility === 'super_famille' ? 'famille' : 'super_famille'
    busyId = r.id
    try {
      await setRecipeVisibility(r.id, next)
      patch(r.id, { visibility: next })
      toast.success(next === 'super_famille' ? 'Partagée avec toute la famille' : 'Gardée pour ton foyer')
    } catch (e: any) {
      toast.error(e?.message ?? 'Action impossible')
    } finally {
      busyId = null
    }
  }

  async function toggleArchive(r: RecipeWithCategory) {
    if (busyId) return
    const archive = !r.archived_at
    busyId = r.id
    try {
      await setRecipeArchived(r.id, archive)
      patch(r.id, { archived_at: archive ? new Date().toISOString() : null })
      toast.success(archive ? 'Recette archivée' : 'Recette restaurée')
    } catch (e: any) {
      toast.error(e?.message ?? 'Action impossible')
    } finally {
      busyId = null
    }
  }

  const sections = $derived([
    { key: 'super_famille', title: 'Toute la famille', sub: 'Visibles par tous les foyers de ta famille.', items: groups.super_famille },
    { key: 'famille', title: 'Mon foyer seulement', sub: 'Visibles par ton foyer uniquement.', items: groups.famille },
    { key: 'archivee', title: 'Archivées', sub: 'Plus dans les listes ni la recherche ; toujours dans les plannings.', items: groups.archivee },
  ] as const)
</script>

<div class="page">
  <a href={href('compte')} class="back-link"><Icon name="arrow-left" size={18} /> Mon compte</a>

  <header class="head">
    <h1>Mes recettes</h1>
    <p class="head-sub">Les recettes que tu as créées.</p>
  </header>

  {#if loading}
    <p class="muted" aria-busy="true">Chargement…</p>
  {:else if loadError}
    <ErrorState error={loadError} message={loadError} />
  {:else if recipes.length === 0}
    <div class="empty">
      <p>Tu n’as pas encore créé de recette.</p>
      <a class="btn btn-outline" href={href('nouvelle-recette')}><Icon name="plus" size={18} /> Créer une recette</a>
    </div>
  {:else}
    {#each sections as section (section.key)}
      {#if section.items.length > 0}
        <section class="group card" aria-labelledby="g-{section.key}">
          <h2 id="g-{section.key}" class="band">{section.title} <span class="count">{section.items.length}</span></h2>
          <p class="group-sub">{section.sub}</p>
          <ul>
            {#each section.items as r, i (r.id)}
              <li class="row" style="--i: {Math.min(i, 8)}">
                <a class="row-main" href={href('recette', r.id)}>
                  <span class="thumb" style="--cat: {categoryColor(r.recipe_categories?.name)}" aria-hidden="true">
                    {#if sizedImage(r.image_url, 96, 96)}
                      <img src={sizedImage(r.image_url, 96, 96)} alt="" loading="lazy" decoding="async" />
                    {:else}
                      <span class="thumb-initial">{r.title.trim().charAt(0)}</span>
                    {/if}
                  </span>
                  <span class="row-title">{r.title}</span>
                </a>
                <div class="row-actions">
                  {#if !r.archived_at}
                    <a class="act" href={href('editer-recette', r.id)}>Modifier</a>
                    <button class="act" onclick={() => toggleShare(r)} disabled={busyId === r.id}>
                      {r.visibility === 'super_famille' ? 'Garder pour mon foyer' : 'Partager'}
                    </button>
                  {/if}
                  {#if isAdmin}
                    <button class="act" class:danger={!r.archived_at} onclick={() => toggleArchive(r)} disabled={busyId === r.id}>
                      {r.archived_at ? 'Restaurer' : 'Archiver'}
                    </button>
                  {/if}
                </div>
              </li>
            {/each}
          </ul>
        </section>
      {/if}
    {/each}
    {#if !isAdmin}
      <p class="muted small">Seul un administrateur de ton foyer peut archiver une recette.</p>
    {/if}
  {/if}
</div>

<style>
  .page {
    padding: var(--gutter);
    padding-top: 0;
    max-width: 560px;
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

  /* Un groupe = une carte, bandeau noir en tête */
  .group { padding: 0 0 var(--sp-1); }
  .group h2.band { font-size: 13px; letter-spacing: var(--tracking-caps); }
  .count {
    display: inline-grid; place-items: center;
    min-width: 22px; height: 22px; padding: 0 4px;
    background: var(--text-on-band); color: var(--band);
    font-size: 12px; font-weight: var(--fw-bold);
  }
  .group-sub { margin: var(--sp-2) var(--sp-3) var(--sp-1); font-size: 13px; color: var(--text-secondary); }
  .group ul { list-style: none; margin: 0; padding: 0; }

  .group .row {
    display: block;
    min-height: 0;
    padding: var(--sp-2) var(--sp-3);
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
  .row-title { font-weight: var(--fw-bold); min-width: 0; overflow-wrap: anywhere; }

  /* Vignette carrée : photo, sinon initiale noire sur l'aplat de la catégorie */
  .thumb {
    position: relative;
    flex: none;
    display: grid;
    place-items: center;
    width: 52px;
    height: 52px;
    overflow: hidden;
    border: var(--line-w) solid var(--line);
    background: var(--cat);
    color: var(--ink);
  }
  .thumb img { position: absolute; inset: 0; width: 100%; height: 100%; object-fit: cover; }
  .thumb-initial { font-weight: var(--fw-bold); font-size: var(--fs-2xl); line-height: 1; text-transform: uppercase; }

  .row-actions { display: flex; flex-wrap: wrap; gap: 0 var(--sp-3); }
  .act {
    min-height: 44px;
    display: inline-flex;
    align-items: center;
    padding: 0;
    border: 0;
    background: none;
    font: inherit;
    font-size: 14px;
    font-weight: var(--fw-bold);
    color: var(--text);
    text-decoration: underline;
    text-decoration-thickness: 2px;
    text-underline-offset: 3px;
    cursor: pointer;
    touch-action: manipulation;
  }
  .act:active:not(:disabled) { transform: translate(1px, 1px); }
  .act.danger { color: var(--error); }
  .act:disabled { opacity: 0.5; }

  .empty { display: flex; flex-direction: column; align-items: flex-start; gap: var(--sp-3); }
  .muted { color: var(--text-secondary); }
  .small { font-size: 13px; }
</style>
