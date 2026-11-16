<script lang="ts">
  import Icon from '../components/Icon.svelte'
  import ConfirmDialog from '../components/ConfirmDialog.svelte'
  import { profileState } from '../lib/profile.svelte'
  import { toast } from '../lib/toast.svelte'
  import {
    fetchCompletedLists,
    fetchListItems,
    fetchListSummaries,
    deleteList,
    type ListSummary,
  } from '../lib/api/shopping'
  import type {
    ShoppingList,
    ShoppingCategory,
    ShoppingListItemWithCategory,
  } from '../lib/types'

  // ── État ──
  let lists: ShoppingList[] = $state([])
  let summaries = $state(new Map<string, ListSummary>())
  let loading = $state(true)
  let error = $state<string | null>(null)
  let reloadTick = $state(0)

  // ── Détail ouvert (une liste à la fois) ──
  let openListId = $state<string | null>(null)
  let detailItems: ShoppingListItemWithCategory[] = $state([])
  let detailLoading = $state(false)
  let detailError = $state<string | null>(null)
  const detailCache = new Map<string, ShoppingListItemWithCategory[]>()
  let detailSeq = 0

  // ── Suppression ──
  let deleteTarget = $state<ShoppingList | null>(null)
  /** Comme la base : seul un admin du foyer supprime une liste */
  const isAdmin = $derived(profileState.profile?.role === 'admin')
  let deleting = $state(false)

  // ── Chargement initial ──
  $effect(() => {
    void reloadTick
    if (profileState.loading) return
    const familyId = profileState.profile?.family_id
    if (!familyId) {
      // Le profil peut arriver juste après (connexion en cours) : on attend
      // un peu avant d'afficher l'erreur, pour éviter un clignotement.
      loading = true
      const t = setTimeout(() => {
        loading = false
        error = 'Profil introuvable. Vérifie que ton compte est bien lié à une famille.'
      }, 1500)
      return () => clearTimeout(t)
    }

    loading = true
    error = null
    let cancelled = false

    fetchCompletedLists(familyId)
      .then(async (data) => {
        if (cancelled) return
        lists = data
        // Résumés (pris / total, aperçu) : en bonus, la page marche sans
        try {
          const s = await fetchListSummaries(data.map((l) => l.id))
          if (!cancelled) summaries = s
        } catch {
          /* on affiche les cartes sans résumé */
        }
      })
      .catch((e) => {
        if (!cancelled) error = e?.message ?? 'Impossible de charger l’historique.'
      })
      .finally(() => {
        if (!cancelled) loading = false
      })

    return () => { cancelled = true }
  })

  // ── Dates ──

  function startOfDay(d: Date): number {
    return new Date(d.getFullYear(), d.getMonth(), d.getDate()).getTime()
  }

  /** « Aujourd'hui », « Hier », « Mardi », puis « Sam. 7 nov. » (année si différente). */
  function relativeDay(iso: string | null): string {
    if (!iso) return 'Date inconnue'
    const d = new Date(iso)
    const now = new Date()
    const days = Math.round((startOfDay(now) - startOfDay(d)) / 86400000)
    if (days <= 0) return 'Aujourd’hui'
    if (days === 1) return 'Hier'
    if (days < 7) {
      const w = d.toLocaleDateString('fr-FR', { weekday: 'long' })
      return w.charAt(0).toUpperCase() + w.slice(1)
    }
    const s = d.toLocaleDateString('fr-FR', {
      weekday: 'short',
      day: 'numeric',
      month: 'short',
      ...(d.getFullYear() !== now.getFullYear() ? { year: 'numeric' } : {}),
    })
    return s.charAt(0).toUpperCase() + s.slice(1)
  }

  /** Ligne secondaire : heure + date complète ou « il y a X jours ». */
  function detailDate(iso: string | null): string {
    if (!iso) return ''
    const d = new Date(iso)
    const time = d.toLocaleTimeString('fr-FR', { hour: '2-digit', minute: '2-digit' })
    const days = Math.round((startOfDay(new Date()) - startOfDay(d)) / 86400000)
    if (days < 2) return `à ${time}`
    if (days < 7) return `il y a ${days} jours · ${time}`
    return `il y a ${days >= 14 ? `${Math.floor(days / 7)} semaines` : '1 semaine'} · ${time}`
  }

  function fullDate(iso: string | null): string {
    if (!iso) return ''
    return new Date(iso).toLocaleDateString('fr-FR', {
      weekday: 'long', day: 'numeric', month: 'long', year: 'numeric',
    })
  }

  // ── Ouvrir / fermer le détail ──

  async function toggleDetail(listId: string) {
    if (openListId === listId) {
      openListId = null
      return
    }

    openListId = listId
    detailError = null
    const seq = ++detailSeq

    const cached = detailCache.get(listId)
    if (cached) {
      detailItems = cached
      detailLoading = false
      return
    }

    detailItems = []
    detailLoading = true
    try {
      const items = await fetchListItems(listId)
      detailCache.set(listId, items)
      if (seq === detailSeq) detailItems = items
    } catch (e: any) {
      if (seq === detailSeq) detailError = e?.message ?? 'Impossible de charger les articles.'
    } finally {
      if (seq === detailSeq) detailLoading = false
    }
  }

  // ── Supprimer une liste ──

  async function confirmDelete() {
    const target = deleteTarget
    if (!target || deleting) return
    deleting = true
    try {
      await deleteList(target.id)
      lists = lists.filter((l) => l.id !== target.id)
      detailCache.delete(target.id)
      if (openListId === target.id) {
        openListId = null
        detailItems = []
      }
      deleteTarget = null
      toast.success('Liste supprimée de l’historique')
    } catch (e: any) {
      toast.error(e?.message ?? 'Suppression impossible')
    } finally {
      deleting = false
    }
  }

  // ── Groupement des articles du détail par rayon (ordre des rayons) ──
  const groupedDetailItems = $derived.by(() => {
    const groups = new Map<string, {
      category: ShoppingCategory | null
      items: ShoppingListItemWithCategory[]
    }>()

    for (const item of detailItems) {
      const catId = item.shopping_category_id || '__none__'
      if (!groups.has(catId)) groups.set(catId, { category: item.shopping_categories, items: [] })
      groups.get(catId)!.items.push(item)
    }

    return Array.from(groups.values()).sort((a, b) => {
      // Sans rayon en dernier
      if (!a.category) return 1
      if (!b.category) return -1
      return a.category.position - b.category.position
    })
  })

  function previewText(s: ListSummary): string {
    const rest = s.total - s.preview.length
    return s.preview.join(', ') + (rest > 0 ? ` +${rest}` : '')
  }
</script>

<div class="page">
  <header class="head">
    <h1>Historique</h1>
    {#if !loading && lists.length > 0}
      <p class="head-sub">{lists.length} liste{lists.length > 1 ? 's' : ''} terminée{lists.length > 1 ? 's' : ''}</p>
    {/if}
  </header>

  {#if loading}
    <div class="history-list" aria-busy="true" aria-label="Chargement de l’historique">
      {#each Array(3) as _, i (i)}
        <div class="card skeleton" style="animation-delay: {i * 100}ms">
          <span class="sk-line sk-title"></span>
          <span class="sk-line sk-mid"></span>
          <span class="sk-line"></span>
        </div>
      {/each}
    </div>
  {:else if error && lists.length === 0}
    <div class="card state">
      <p class="state-title">Oups, l’historique n’a pas pu être chargé</p>
      <p class="state-text error-text">{error}</p>
      <button class="btn btn-outline state-btn" onclick={() => reloadTick++}>
        <Icon name="refresh" /> Réessayer
      </button>
    </div>
  {:else if lists.length === 0}
    <div class="card state">
      <span class="state-icon"><Icon name="archive" size={44} strokeWidth={1.5} /></span>
      <p class="state-title">Aucun historique</p>
      <p class="state-text">Quand tu termines une liste de courses, elle est rangée ici.</p>
      <a href="#/courses" class="btn btn-outline state-btn"><Icon name="cart" /> Aller aux courses</a>
    </div>
  {:else}
    <div class="history-list">
      {#each lists as list, li (list.id)}
        {@const isOpen = openListId === list.id}
        {@const s = summaries.get(list.id)}
        <article class="card history-card" class:is-open={isOpen} style="--i: {Math.min(li, 8)}">
          <button
            class="card-header"
            onclick={() => toggleDetail(list.id)}
            aria-expanded={isOpen}
            aria-controls="detail-{list.id}"
          >
            <span class="header-row">
              <span class="card-icon" aria-hidden="true"><Icon name="check-circle" size={22} /></span>
              <span class="card-info">
                <span class="card-date" title={fullDate(list.completed_at)}>{relativeDay(list.completed_at)}</span>
                <span class="card-time">{detailDate(list.completed_at)}</span>
              </span>
              {#if s && s.total > 0}
                <span class="card-stat" class:complete={s.checked === s.total}>
                  <strong>{s.checked}</strong>/{s.total}
                  <span class="stat-label">pris</span>
                </span>
              {/if}
              <svg class="chevron" class:open={isOpen} width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="square" stroke-linejoin="miter" aria-hidden="true"><path d="m6 9 6 6 6-6"/></svg>
            </span>

            {#if s && !isOpen}
              <span class="card-preview">
                {#if s.total > 0}
                  <span class="mini-progress" aria-hidden="true"><span class="mini-fill" class:complete={s.checked === s.total} style:transform="scaleX({s.checked / s.total})"></span></span>
                  <span class="preview-text">{previewText(s)}</span>
                {:else}
                  <span class="preview-text">Liste vide</span>
                {/if}
              </span>
            {/if}
          </button>

          {#if isOpen}
            <div class="card-detail" id="detail-{list.id}">
              {#if detailLoading}
                <div class="detail-loading"><div class="spinner-sm"></div></div>
              {:else if detailError}
                <p class="detail-empty error-text">{detailError}</p>
              {:else if detailItems.length === 0}
                <p class="detail-empty">Liste vide.</p>
              {:else}
                {#each groupedDetailItems as group (group.category?.id ?? 'none')}
                  <section class="detail-group">
                    <h3 class="band detail-group-title">
                      <span class="rayon-icon" aria-hidden="true">{group.category?.icon || '🛒'}</span>
                      {group.category?.name || 'Sans rayon'}
                      <span class="rayon-count">{group.items.length}</span>
                    </h3>
                    <ul class="detail-items">
                      {#each group.items as item (item.id)}
                        <li class="detail-item" class:not-taken={!item.checked}>
                          <span class="tick" class:on={item.checked} aria-label={item.checked ? 'Pris' : 'Pas pris'}>
                            {#if item.checked}<Icon name="check" size={13} strokeWidth={3} />{/if}
                          </span>
                          <span class="detail-item-name">{item.name}</span>
                          {#if item.is_extra}
                            <span class="tag">ajouté</span>
                          {/if}
                          {#if item.quantity}
                            <span class="detail-item-qty">{item.quantity}</span>
                          {/if}
                        </li>
                      {/each}
                    </ul>
                  </section>
                {/each}
              {/if}

              <div class="detail-actions">
                {#if isAdmin}
                <button class="btn btn-delete" onclick={() => (deleteTarget = list)}>
                  <Icon name="trash" size={16} /> Supprimer cette liste
                </button>
                {/if}
              </div>
            </div>
          {/if}
        </article>
      {/each}
    </div>
  {/if}
</div>

{#if deleteTarget}
  {@const ds = summaries.get(deleteTarget.id)}
  <ConfirmDialog
    title="Supprimer cette liste ?"
    confirmLabel="Supprimer"
    danger
    busy={deleting}
    onconfirm={confirmDelete}
    oncancel={() => { if (!deleting) deleteTarget = null }}
  >
    La liste du <strong>{fullDate(deleteTarget.completed_at)}</strong>{#if ds && ds.total > 0}{' '}({ds.total} article{ds.total > 1 ? 's' : ''}){/if}
    sera définitivement supprimée de l’historique.
  </ConfirmDialog>
{/if}

<style>
  .page {
    padding: var(--gutter);
    padding-top: calc(var(--gutter) + env(safe-area-inset-top, 0px));
    padding-bottom: calc(84px + env(safe-area-inset-bottom, 0px));
    max-width: 640px;
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

  /* ── Cartes (.card global : blanc, bordure 2 px, ombre) ── */
  .history-list {
    display: flex;
    flex-direction: column;
    gap: var(--sp-4);
  }

  .history-card {
    overflow: hidden;
    animation: fade-up var(--dur-sheet) var(--ease-out) calc(var(--i, 0) * 45ms) backwards;
  }

  .card-header {
    display: flex;
    flex-direction: column;
    gap: var(--sp-2);
    width: 100%;
    min-height: 64px;
    padding: var(--sp-3) 14px;
    background: none;
    border: none;
    cursor: pointer;
    font-family: var(--font-body);
    text-align: left;
    color: var(--text);
    touch-action: manipulation;
  }

  .card-header:active { background: var(--surface-hover); }

  .header-row {
    display: flex;
    align-items: center;
    gap: var(--sp-3);
    width: 100%;
  }

  /* Puce carrée orange */
  .card-icon {
    flex-shrink: 0;
    width: 40px;
    height: 40px;
    border: var(--line-w) solid var(--line);
    display: flex;
    align-items: center;
    justify-content: center;
    background: var(--accent);
    color: var(--on-accent);
  }

  .card-info {
    flex: 1;
    min-width: 0;
    display: flex;
    flex-direction: column;
    gap: 2px;
  }

  .card-date {
    font-family: var(--font-display);
    font-size: var(--fs-lg);
    font-weight: var(--fw-bold);
    line-height: 1.2;
    text-transform: uppercase;
  }

  .card-time { font-size: 13px; color: var(--text-secondary); }

  /* Compteur « pris / total » : petit carré bordé */
  .card-stat {
    flex-shrink: 0;
    display: flex;
    align-items: baseline;
    gap: 1px;
    padding: 3px 8px;
    border: var(--line-w) solid var(--line);
    background: var(--surface);
    font-size: 13px;
    color: var(--text-secondary);
  }

  .card-stat strong { font-size: var(--fs-base); color: var(--text); }
  .card-stat.complete { background: var(--success-bg); }
  .card-stat.complete strong { color: var(--success); }
  .stat-label { margin-left: 4px; }

  .chevron {
    flex-shrink: 0;
    color: var(--text);
    transition: transform var(--dur-base) var(--ease-out);
  }

  .chevron.open { transform: rotate(180deg); }

  /* Aperçu sous l'en-tête (carte fermée) */
  .card-preview {
    display: flex;
    flex-direction: column;
    gap: var(--sp-2);
    width: 100%;
    padding: 0 0 2px 52px;
    color: var(--text-secondary);
  }

  /* Mini-progression : bloc carré bordé, remplissage orange (scaleX) */
  .mini-progress {
    display: block;
    height: 10px;
    border: var(--line-w) solid var(--line);
    background: var(--surface);
    overflow: hidden;
  }

  .mini-fill {
    display: block;
    height: 100%;
    background: var(--accent);
    transform-origin: left center;
  }

  .mini-fill.complete { background: var(--success); }

  .preview-text {
    font-size: var(--fs-sm);
    line-height: 1.35;
    display: -webkit-box;
    -webkit-line-clamp: 1;
    line-clamp: 1;
    -webkit-box-orient: vertical;
    overflow: hidden;
  }

  /* ── Détail ── */
  .card-detail { border-top: var(--line-w) solid var(--line); padding-bottom: var(--sp-3); }

  .detail-loading {
    display: flex;
    justify-content: center;
    padding: 20px;
  }

  .detail-empty {
    color: var(--text-secondary);
    font-size: var(--fs-sm);
    text-align: center;
    padding: var(--sp-4) 0;
  }

  .detail-group + .detail-group { margin-top: var(--sp-3); }

  /* Bandeau de rayon (.band global) */
  .detail-group-title {
    justify-content: flex-start;
    font-family: var(--font-body);
    letter-spacing: var(--tracking-caps);
  }

  .rayon-icon { font-size: 14px; line-height: 1; }

  .rayon-count {
    margin-left: auto;
    min-width: 22px;
    padding: 0 6px;
    background: var(--text-on-band);
    color: var(--band);
    font-size: var(--fs-xs);
    text-align: center;
  }

  .detail-items {
    list-style: none;
    margin: 0;
    padding: 0;
  }

  .detail-item {
    display: flex;
    align-items: center;
    gap: var(--sp-3);
    min-height: 44px;
    padding: 6px var(--sp-3);
  }

  .detail-item + .detail-item { border-top: var(--line-thin) solid var(--line); }

  /* Case carrée : orange si l'article a été pris */
  .tick {
    width: 24px;
    height: 24px;
    flex-shrink: 0;
    border: var(--line-w) solid var(--line);
    background: var(--surface);
    display: flex;
    align-items: center;
    justify-content: center;
  }

  .tick.on {
    background: var(--accent);
    color: var(--on-accent);
  }

  .detail-item-name {
    flex: 1;
    min-width: 0;
    font-size: var(--fs-base);
    font-weight: var(--fw-bold);
    color: var(--text);
    overflow-wrap: anywhere;
  }

  /* Article pas pris : en retrait */
  .not-taken .detail-item-name { color: var(--text-secondary); font-weight: var(--fw-medium); }

  .detail-item-qty {
    flex-shrink: 0;
    max-width: 45%;
    font-size: var(--fs-sm);
    font-weight: var(--fw-bold);
    color: var(--text);
    text-align: right;
  }

  .not-taken .detail-item-qty { color: var(--text-secondary); }

  /* ── Actions du détail ── */
  .detail-actions:not(:empty) {
    margin-top: var(--sp-3);
    padding: var(--sp-3) var(--sp-3) 0;
    border-top: var(--line-thin) solid var(--line);
  }

  .btn-delete {
    width: 100%;
    background: var(--error-bg);
    color: var(--error);
    border-color: var(--error);
    box-shadow: 3px 3px 0 var(--error);
    touch-action: manipulation;
  }

  .btn-delete:active:not(:disabled) { box-shadow: none; }

  /* ── États ── */
  .state {
    padding: var(--sp-6) var(--sp-5);
    text-align: center;
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: var(--sp-2);
  }

  .state-icon { color: var(--text); }

  .state-title {
    font-family: var(--font-display);
    font-size: var(--fs-xl);
    font-weight: var(--fw-bold);
    text-transform: uppercase;
    color: var(--text);
  }

  .state-text {
    font-size: 15px;
    line-height: 1.45;
    color: var(--text-secondary);
  }

  .error-text { color: var(--error); }

  .state-btn { margin-top: var(--sp-2); }

  /* ── Squelettes ── */
  .skeleton {
    display: flex;
    flex-direction: column;
    gap: 10px;
    padding: var(--sp-4);
    animation: sk-pulse 1.2s ease-in-out infinite alternate;
  }

  .sk-line {
    display: block;
    height: 12px;
    background: var(--surface-sunken);
    border: var(--line-thin) solid var(--line);
  }

  .sk-title { width: 45%; height: 18px; }
  .sk-mid { width: 30%; }

  @keyframes sk-pulse {
    from { opacity: 1; }
    to { opacity: 0.5; }
  }

  /* Rond d'une icône dessinée (indicateur de chargement) */
  .spinner-sm {
    width: 20px;
    height: 20px;
    border: 2px solid var(--line);
    border-top-color: var(--accent);
    animation: spin 0.7s linear infinite;
  }

  @keyframes spin { to { transform: rotate(360deg); } }

  @media (hover: hover) and (pointer: fine) {
    .card-header:hover { background: var(--surface-hover); }
  }
</style>
