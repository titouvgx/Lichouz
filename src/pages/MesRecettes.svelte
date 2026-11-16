<script lang="ts">
  // « Mes recettes » (#/mes-recettes), depuis Mon compte : les recettes dont je
  // suis l'auteur, rangées en « Toutes nos familles », « Ma famille seulement »
  // et « Archivées ». Actions : modifier, changer qui la voit, archiver /
  // restaurer (admin de la famille). Le catalogue n'apparaît pas ici.
  // Les droits sont vérifiés par la base : l'écran ne fait que montrer les bons boutons.
  import Icon from '../components/Icon.svelte'
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
      toast.success(next === 'super_famille' ? 'Partagée avec toutes vos familles' : 'Gardée pour ta famille')
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
    { key: 'super_famille', title: 'Toutes nos familles', sub: 'Visibles par les familles de ta super-famille.', items: groups.super_famille },
    { key: 'famille', title: 'Ma famille seulement', sub: 'Visibles par ta famille uniquement.', items: groups.famille },
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
    <p class="error" role="alert">{loadError}</p>
  {:else if recipes.length === 0}
    <div class="empty">
      <p>Tu n’as pas encore créé de recette.</p>
      <a class="btn btn-outline" href={href('nouvelle-recette')}><Icon name="plus" size={18} /> Créer une recette</a>
    </div>
  {:else}
    {#each sections as section (section.key)}
      {#if section.items.length > 0}
        <section class="group" aria-labelledby="g-{section.key}">
          <h2 id="g-{section.key}">{section.title} <span class="count">{section.items.length}</span></h2>
          <p class="group-sub">{section.sub}</p>
          <ul>
            {#each section.items as r (r.id)}
              <li class="row">
                <a class="row-title" href={href('recette', r.id)}>{r.title}</a>
                <div class="row-actions">
                  {#if !r.archived_at}
                    <a class="act" href={href('editer-recette', r.id)}>Modifier</a>
                    <button class="act" onclick={() => toggleShare(r)} disabled={busyId === r.id}>
                      {r.visibility === 'super_famille' ? 'Garder pour ma famille' : 'Partager'}
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
      <p class="muted small">Seul un administrateur de ta famille peut archiver une recette.</p>
    {/if}
  {/if}
</div>

<style>
  .page {
    padding: var(--gutter);
    padding-top: 0;
    max-width: 560px;
    margin: 0 auto;
    padding-bottom: 32px;
    display: flex;
    flex-direction: column;
    gap: 12px;
  }
  .back-link {
    display: inline-flex;
    align-items: center;
    align-self: flex-start;
    gap: 6px;
    min-height: 44px;
    margin-top: calc(8px + env(safe-area-inset-top, 0px));
    color: var(--primary);
    font-weight: 600;
    touch-action: manipulation;
  }
  .head { margin-bottom: 4px; }
  .head h1 { font-family: var(--font-display); font-size: 28px; padding-right: 48px; }
  .head-sub { margin-top: 4px; font-size: 15px; color: var(--text-secondary); }

  .group {
    background: var(--surface);
    border: 1px solid var(--border);
    border-radius: var(--radius-xl);
    padding: 16px 18px 6px;
  }
  .group h2 { font-size: 17px; display: flex; align-items: center; gap: 8px; }
  .count { font-size: 14px; font-weight: 500; color: var(--text-secondary); }
  .group-sub { margin: 2px 0 6px; font-size: 13px; color: var(--text-secondary); }
  .group ul { list-style: none; margin: 0; padding: 0; }

  .row { padding: 10px 0; border-top: 1px solid var(--border); }
  .row:first-child { border-top: 0; }
  .row-title {
    display: block;
    font-weight: 600;
    color: var(--text);
    text-decoration: none;
    padding: 4px 0;
  }
  .row-actions { display: flex; flex-wrap: wrap; gap: 4px 16px; }
  .act {
    min-height: 44px;
    display: inline-flex;
    align-items: center;
    padding: 0;
    border: 0;
    background: none;
    font: inherit;
    font-size: 14px;
    font-weight: 600;
    color: var(--primary);
    text-decoration: none;
    cursor: pointer;
    touch-action: manipulation;
  }
  .act.danger { color: #FF8A8D; } /* rouge éclairci : lisible sur le fond bleu nuit */
  .act:disabled { opacity: 0.5; }

  .empty { display: flex; flex-direction: column; align-items: flex-start; gap: 12px; }
  .muted { color: var(--text-secondary); }
  .small { font-size: 13px; }
  .error { color: #FF8A8D; }
</style>
