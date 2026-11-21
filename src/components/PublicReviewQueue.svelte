<script lang="ts">
  // File de validation des recettes que leurs auteurs veulent rendre publiques
  // (page Administration, super-admin seulement : la base refuse tout autre rôle).
  import Icon from './Icon.svelte'
  import { href } from '../lib/router.svelte'
  import { toast } from '../lib/toast.svelte'
  import { fetchPublicReviewQueue, reviewPublicRecipe, type PublicReviewItem } from '../lib/api/recipes'
  import { REFUSAL_REASONS, type RefusalReason } from '../lib/publication'

  let items = $state<PublicReviewItem[]>([])
  let loading = $state(true)
  let error = $state<string | null>(null)
  let busyId = $state<string | null>(null)
  /** Recette en cours de refus + motif choisi */
  let refusingId = $state<string | null>(null)
  let reason = $state<RefusalReason>('recette_incomplete')

  async function load() {
    loading = true
    error = null
    try {
      items = await fetchPublicReviewQueue()
    } catch (e: any) {
      error = e?.message ?? 'Chargement impossible'
    } finally {
      loading = false
    }
  }
  $effect(() => {
    void load()
  })

  async function decide(it: PublicReviewItem, approve: boolean) {
    if (busyId) return
    busyId = it.recipe_id
    try {
      await reviewPublicRecipe(it.recipe_id, approve, approve ? undefined : reason)
      items = items.filter((x) => x.recipe_id !== it.recipe_id)
      refusingId = null
      toast.success(approve ? 'Recette validée : elle est publique' : 'Recette refusée')
    } catch (e: any) {
      toast.error(e?.message ?? 'Action impossible')
    } finally {
      busyId = null
    }
  }

  const date = (iso: string) => new Date(iso).toLocaleDateString('fr-FR', { day: 'numeric', month: 'short', hour: '2-digit', minute: '2-digit' })
</script>

<section class="card" aria-labelledby="review-title">
  <h2 id="review-title" class="band">
    Recettes à valider {#if items.length > 0}<span class="count">{items.length}</span>{/if}
  </h2>
  <p class="sub">Recettes que leurs auteurs veulent rendre publiques. Ouvre la fiche pour la lire avant de répondre.</p>
  {#if loading}
    <p class="muted" aria-busy="true">Chargement…</p>
  {:else if error}
    <p class="muted">{error}</p>
    <button class="link-btn" onclick={load}>Réessayer</button>
  {:else if items.length === 0}
    <p class="muted">Aucune demande en attente.</p>
  {:else}
    <ul>
      {#each items as it (it.recipe_id)}
        <li class="item">
          <a class="item-main" href={href('recette', it.recipe_id)}>
            <strong>{it.title}</strong>
            <span class="muted">par {it.author_pseudo ?? 'auteur supprimé'} · {date(it.requested_at)}</span>
          </a>
          {#if refusingId === it.recipe_id}
            <div class="refuse">
              <label for="reason-{it.recipe_id}">Motif du refus</label>
              <select id="reason-{it.recipe_id}" bind:value={reason}>
                {#each REFUSAL_REASONS as m (m.code)}<option value={m.code}>{m.label}</option>{/each}
              </select>
              <div class="actions">
                <button class="btn btn-outline" onclick={() => decide(it, false)} disabled={busyId === it.recipe_id}>Confirmer le refus</button>
                <button class="link-btn" onclick={() => (refusingId = null)}>Annuler</button>
              </div>
            </div>
          {:else}
            <div class="actions">
              <button class="btn btn-primary" onclick={() => decide(it, true)} disabled={busyId === it.recipe_id}>
                <Icon name="check" size={18} /> Valider
              </button>
              <button class="btn btn-outline" onclick={() => (refusingId = it.recipe_id)} disabled={busyId === it.recipe_id}>Refuser</button>
            </div>
          {/if}
        </li>
      {/each}
    </ul>
  {/if}
</section>

<style>
  .sub { margin: var(--sp-2) var(--sp-3); font-size: 13px; color: var(--text-secondary); }
  .muted { margin: var(--sp-2) var(--sp-3); color: var(--text-secondary); }
  ul { list-style: none; margin: 0; padding: 0; }
  .item { padding: var(--sp-2) var(--sp-3); display: flex; flex-direction: column; gap: var(--sp-2); }
  .item-main { display: flex; flex-direction: column; gap: 2px; min-height: 44px; color: var(--text); text-decoration: none; }
  .actions { display: flex; flex-wrap: wrap; align-items: center; gap: var(--sp-2); }
  .refuse { display: flex; flex-direction: column; gap: var(--sp-2); }
  .link-btn { background: none; border: 0; padding: 0; min-height: 44px; font: inherit; font-weight: var(--fw-bold); text-decoration: underline; color: var(--text); cursor: pointer; }
  .count {
    display: inline-grid; place-items: center;
    min-width: 22px; height: 22px; padding: 0 4px;
    background: var(--text-on-band); color: var(--band);
    font-size: 12px; font-weight: var(--fw-bold);
  }
</style>
