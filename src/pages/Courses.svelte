<script lang="ts">
  // Liste de courses active du foyer.
  //   - articles à prendre groupés par rayon, articles pris dans « Dans le chariot »
  //   - temps réel entre membres (cochage, ajout, suppression)
  //   - hors connexion : dernière liste gardée sur le téléphone, cochages en attente
  //   - « Mettre à jour depuis le planning » ne perd ni les cochages ni les ajouts à la main
  //   - achats habituels (fenêtre « Habituels ») et placard (« Sûrement déjà à la maison »),
  //     masqués sans erreur si les tables n'existent pas encore côté base
  import { onMount, onDestroy } from 'svelte'
  import Icon from '../components/Icon.svelte'
  import { href } from '../lib/router.svelte'
  import ConfirmDialog from '../components/ConfirmDialog.svelte'
  import StaplesDialog from '../components/StaplesDialog.svelte'
  import PantryDialog from '../components/PantryDialog.svelte'
  import { profileState } from '../lib/profile.svelte'
  import { auth } from '../lib/auth.svelte'
  import { supabase } from '../lib/supabase'
  import { fetchOrCreatePlan, fetchSlots, getMonday, toISODate } from '../lib/api/meals'
  import { fetchShoppingCategories } from '../lib/api/recipes'
  import {
    fetchActiveList, fetchListItems, generateListFromPlan, regenerateList,
    toggleItem, addExtraItem, removeItem, completeList, shareListText,
  } from '../lib/api/shopping'
  import { fetchRecipeTitles } from '../lib/api/recipes'
  import { LIST_ITEM_NAME_MAX, LIST_ITEM_QTY_MAX } from '../lib/limits'
  import {
    loadCachedList, saveCachedList, queueToggle, applyPending, flushPending,
    pendingToggles, isNetworkError,
    loadCachedHousehold, saveCachedHousehold, queueNeeded, applyPendingNeeded, flushPendingNeeded,
  } from '../lib/offline'
  import { fetchStaples, fetchPantry, isProbablyAtHome, setItemNeeded } from '../lib/api/household'
  import type {
    ShoppingList, ShoppingListItemWithCategory, ShoppingCategory, Staple, PantryItem,
  } from '../lib/types'
  import type { RealtimeChannel } from '@supabase/supabase-js'
  import { toast } from '../lib/toast.svelte'
  import { tap } from '../lib/haptics'
  import { fly } from 'svelte/transition'
  import { flip } from 'svelte/animate'

  // Animations de liste (transform/opacity uniquement) ; coupées si
  // « réduire les animations » est activé sur le téléphone.
  const reduceMotion = typeof window !== 'undefined' && window.matchMedia('(prefers-reduced-motion: reduce)').matches
  const d = (ms: number) => (reduceMotion ? 0 : ms)

  // ── État ──
  let list: ShoppingList | null = $state(null)
  let items: ShoppingListItemWithCategory[] = $state([])
  let categories: ShoppingCategory[] = $state([])
  let loading = $state(true)
  let error = $state<string | null>(null)
  let busy = $state(false)

  // Hors connexion
  let offline = $state(typeof navigator !== 'undefined' ? !navigator.onLine : false)
  let cachedAt = $state<string | null>(null)
  let pendingCount = $state(pendingToggles().length)

  // Ajout manuel
  let showAddForm = $state(false)
  let newItemName = $state('')
  let newItemQty = $state('')
  let newItemCat = $state('')

  // Confirmations
  let confirm = $state<'complete' | 'regenerate' | null>(null)

  // « Dans le chariot » replié par défaut
  let cartOpen = $state(false)

  // Habituels et placard du foyer. null = indisponible (migration pas encore
  // passée, ou jamais chargé hors connexion) : les nouveautés restent masquées.
  let staples = $state<Staple[] | null>(null)
  let pantry = $state<PantryItem[] | null>(null)
  let dialog = $state<'staples' | 'pantry' | null>(null)
  // « Sûrement déjà à la maison » replié par défaut
  let homeOpen = $state(false)

  const familyId = $derived(profileState.profile?.family_id ?? null)

  // ── Chargement (cache d'abord, réseau ensuite) ──

  function persist() {
    if (familyId) saveCachedList(familyId, { list, items, categories })
  }

  /** Cochages et « il en manque » faits sans réseau, réappliqués à l'affichage */
  function withPending(list: ShoppingListItemWithCategory[]): ShoppingListItemWithCategory[] {
    return applyPendingNeeded(applyPending(list))
  }

  function persistHousehold() {
    if (familyId) saveCachedHousehold(familyId, { staples, pantry })
  }

  /**
   * Habituels + placard, à part : une erreur (table absente, réseau) ne doit
   * jamais gêner la liste. On garde la version du téléphone si le réseau manque.
   */
  async function loadHousehold(fid: string) {
    const [st, pa] = await Promise.allSettled([fetchStaples(fid), fetchPantry(fid)])
    const netDown = [st, pa].some((r) => r.status === 'rejected' && isNetworkError(r.reason))
    if (netDown) return // on reste sur le cache
    staples = st.status === 'fulfilled' ? st.value : null
    pantry = pa.status === 'fulfilled' ? pa.value : null
    persistHousehold()
  }

  async function load() {
    const fid = familyId
    if (!fid) return
    error = null

    const home = loadCachedHousehold(fid)
    if (home) {
      staples = home.staples
      pantry = home.pantry
    }

    const cache = loadCachedList(fid)
    if (cache) {
      list = cache.list
      items = withPending(cache.items)
      categories = cache.categories
      cachedAt = cache.savedAt
      loading = false // on affiche tout de suite la dernière version connue
    }

    try {
      await flushPending()
      await flushPendingNeeded().catch(() => 0)
      pendingCount = pendingToggles().length
      const [activeList, cats] = await Promise.all([
        fetchActiveList(fid),
        fetchShoppingCategories(),
        loadHousehold(fid).catch(() => {}),
      ])
      categories = cats
      list = activeList
      items = activeList ? withPending(await fetchListItems(activeList.id)) : []
      offline = false
      cachedAt = null
      persist()
    } catch (e: any) {
      if (isNetworkError(e) && cache) {
        offline = true // on reste sur la version du téléphone
      } else if (isNetworkError(e)) {
        offline = true
        error = 'Pas de réseau, et aucune liste enregistrée sur ce téléphone.'
      } else {
        error = e.message
      }
    } finally {
      loading = false
    }
  }

  $effect(() => {
    if (profileState.loading) return
    if (!familyId) {
      loading = false
      error = 'Profil introuvable.'
      return
    }
    load()
  })

  // Réseau qui revient / qui part
  function onOnline() {
    offline = false
    load().then(() => {
      if (pendingToggles().length === 0 && pendingCount === 0) return
    })
  }
  function onOffline() { offline = true }
  onMount(() => {
    window.addEventListener('online', onOnline)
    window.addEventListener('offline', onOffline)
  })
  onDestroy(() => {
    window.removeEventListener('online', onOnline)
    window.removeEventListener('offline', onOffline)
  })

  // ── Dérivés ──

  /** Articles du planning qui sont au placard : mis à part, hors des rayons et du compteur */
  const atHome = $derived(
    pantry && pantry.length > 0
      ? items.filter((i) => isProbablyAtHome(i, pantry!)).sort((a, b) => a.position - b.position)
      : [],
  )
  const atHomeIds = $derived(new Set(atHome.map((i) => i.id)))
  const toBuy = $derived(items.filter((i) => !i.checked && !atHomeIds.has(i.id)))
  const inCart = $derived(items.filter((i) => i.checked).sort((a, b) => a.position - b.position))

  /** Articles à prendre, groupés par rayon (ordre des rayons du magasin) */
  const groups = $derived.by(() => {
    const map = new Map<string, { category: ShoppingCategory | null; items: ShoppingListItemWithCategory[] }>()
    for (const item of [...toBuy].sort((a, b) => a.position - b.position)) {
      const key = item.shopping_category_id || '__none__'
      if (!map.has(key)) map.set(key, { category: item.shopping_categories, items: [] })
      map.get(key)!.items.push(item)
    }
    return [...map.values()].sort((a, b) => (a.category?.position ?? 999) - (b.category?.position ?? 999))
  })

  // ── À quelles recettes sert chaque article (migration 22) ──
  let recipeTitles = $state(new Map<string, string>())
  function sourcesOf(item: ShoppingListItemWithCategory): string[] {
    const ids = item.source_recipe_ids?.length ? item.source_recipe_ids : item.source_recipe_id ? [item.source_recipe_id] : []
    return ids.map((id) => recipeTitles.get(id)).filter((t): t is string => !!t)
  }
  $effect(() => {
    const missing = new Set<string>()
    for (const it of items) {
      for (const id of it.source_recipe_ids ?? (it.source_recipe_id ? [it.source_recipe_id] : [])) {
        if (!recipeTitles.has(id)) missing.add(id)
      }
    }
    if (missing.size === 0 || offline) return
    fetchRecipeTitles([...missing])
      .then((found) => {
        if (found.size === 0) return
        const next = new Map(recipeTitles)
        for (const [id, t] of found) next.set(id, t)
        recipeTitles = next
      })
      .catch(() => { /* pas bloquant : les articles restent affichés sans recettes */ })
  })

  // ── Partager la liste (WhatsApp, SMS… via le menu de partage du téléphone) ──
  async function shareList() {
    const text = shareListText(toBuy, 'Liste de courses Lichouz')
    try {
      if (navigator.share) {
        await navigator.share({ text })
        return
      }
      await navigator.clipboard.writeText(text)
      toast.success('Liste copiée : colle-la dans ton message')
    } catch (e: any) {
      if (e?.name === 'AbortError') return // partage annulé
      toast.error('Partage impossible sur ce téléphone')
    }
  }

  // « Sûrement déjà à la maison » ne compte pas : ni dans « N à prendre », ni dans la barre
  const total = $derived(items.length - atHome.length)
  const done = $derived(inCart.length)
  const allDone = $derived(total > 0 && done === total)

  let celebrated = false
  $effect(() => {
    if (allDone && !celebrated) {
      celebrated = true
      tap('success')
      toast.success('Tout est dans le chariot !')
    }
    if (!allDone) celebrated = false
  })

  // ── Temps réel ──
  // Variable NON réactive : l'effet qui s'abonne la lit puis la modifie.
  let channel: RealtimeChannel | null = null

  function unsubscribe() {
    if (channel) {
      supabase?.removeChannel(channel)
      channel = null
    }
  }

  function subscribe(listId: string) {
    unsubscribe()
    if (!supabase) return
    channel = supabase
      .channel(`shopping-items-${listId}`)
      .on('postgres_changes',
        { event: 'UPDATE', schema: 'public', table: 'shopping_list_items', filter: `shopping_list_id=eq.${listId}` },
        (payload) => {
          const u = payload.new as any
          items = items.map((i) => (i.id === u.id
            ? { ...i, checked: u.checked, checked_by: u.checked_by, checked_at: u.checked_at, quantity: u.quantity,
                needed: u.needed ?? i.needed }
            : i))
          persist()
        })
      .on('postgres_changes',
        { event: 'INSERT', schema: 'public', table: 'shopping_list_items', filter: `shopping_list_id=eq.${listId}` },
        async () => {
          // l'insertion ne renvoie pas le rayon joint : on recharge
          if (list) { items = withPending(await fetchListItems(list.id)); persist() }
        })
      .on('postgres_changes',
        { event: 'DELETE', schema: 'public', table: 'shopping_list_items' },
        (payload) => {
          const id = (payload.old as any)?.id
          if (id) { items = items.filter((i) => i.id !== id); persist() }
        })
      .subscribe()
  }

  $effect(() => {
    const id = list?.id
    if (id && !offline) subscribe(id)
    else unsubscribe()
  })
  onDestroy(unsubscribe)

  // ── Cochage (fonctionne aussi sans réseau) ──

  async function toggle(item: ShoppingListItemWithCategory) {
    const userId = auth.user?.id
    if (!userId) return
    const checked = !item.checked
    tap()
    items = items.map((i) => (i.id === item.id ? { ...i, checked } : i))
    persist()
    try {
      await toggleItem(item.id, checked, userId)
    } catch (e) {
      if (isNetworkError(e)) {
        queueToggle({ itemId: item.id, checked, userId })
        pendingCount = pendingToggles().length
        offline = true
      } else {
        items = items.map((i) => (i.id === item.id ? { ...i, checked: !checked } : i))
        persist()
        toast.error((e as any)?.message ?? 'Erreur')
      }
    }
  }

  // ── « Il en manque » : l'article du placard repasse dans son rayon (pour tout le foyer) ──

  async function markNeeded(item: ShoppingListItemWithCategory) {
    tap()
    items = items.map((i) => (i.id === item.id ? { ...i, needed: true } : i))
    persist()
    try {
      await setItemNeeded(item.id, true)
    } catch (e) {
      if (isNetworkError(e)) {
        queueNeeded({ itemId: item.id, needed: true })
        offline = true
      } else {
        items = items.map((i) => (i.id === item.id ? { ...i, needed: false } : i))
        persist()
        toast.error((e as any)?.message ?? 'Erreur')
      }
    }
  }

  // ── Habituels / placard ──

  async function reloadItems() {
    if (!list) return
    items = withPending(await fetchListItems(list.id))
    persist()
  }

  function openDialog(which: 'staples' | 'pantry') {
    if (needNetwork()) return
    dialog = which
  }

  function needNetwork(): boolean {
    if (offline) toast.error('Pas de réseau : cette action attendra le retour de la connexion.')
    return offline
  }

  async function remove(item: ShoppingListItemWithCategory) {
    if (needNetwork()) return
    const before = items
    items = items.filter((i) => i.id !== item.id)
    try {
      await removeItem(item.id)
      persist()
    } catch (e: any) {
      items = before
      toast.error(e.message)
    }
  }

  async function addItem() {
    if (!list || !newItemName.trim() || busy || needNetwork()) return
    busy = true
    try {
      await addExtraItem(list.id, newItemName, newItemQty || null, newItemCat || null)
      items = withPending(await fetchListItems(list.id))
      persist()
      newItemName = ''
      newItemQty = ''
      showAddForm = false
    } catch (e: any) {
      toast.error(e.message)
    } finally {
      busy = false
    }
  }

  // ── Générer / mettre à jour / terminer ──

  async function currentPlanWithSlots() {
    const plan = await fetchOrCreatePlan(familyId!, toISODate(getMonday(new Date())))
    const slots = await fetchSlots(plan.id)
    return { plan, empty: slots.length === 0 }
  }

  async function generate() {
    if (!familyId || busy || needNetwork()) return
    busy = true
    error = null
    try {
      const { plan, empty } = await currentPlanWithSlots()
      if (empty) {
        error = 'Le planning de cette semaine est vide. Ajoute des recettes dans l’onglet Semaine.'
        return
      }
      list = await generateListFromPlan(familyId, plan.id)
      items = await fetchListItems(list.id)
      persist()
      toast.success(`Liste prête : ${items.length} articles`)
    } catch (e: any) {
      error = e.message
    } finally {
      busy = false
    }
  }

  async function regenerate() {
    if (!list || !familyId || busy || needNetwork()) return
    busy = true
    try {
      const { plan, empty } = await currentPlanWithSlots()
      if (empty) {
        toast.error('Le planning de cette semaine est vide.')
        return
      }
      await regenerateList(list.id, plan.id)
      items = withPending(await fetchListItems(list.id))
      persist()
      toast.success('Liste mise à jour (cochés et ajouts conservés)')
    } catch (e: any) {
      toast.error(e.message)
    } finally {
      busy = false
      confirm = null
    }
  }

  async function complete() {
    if (!list || busy || needNetwork()) return
    busy = true
    try {
      await completeList(list.id)
      list = null
      items = []
      persist()
      toast.success('Courses terminées, liste rangée dans l’historique')
    } catch (e: any) {
      toast.error(e.message)
    } finally {
      busy = false
      confirm = null
    }
  }

  function timeLabel(iso: string): string {
    return new Date(iso).toLocaleString('fr-FR', { weekday: 'short', hour: '2-digit', minute: '2-digit' })
  }
</script>

<div class="page">
  <header class="head deco-boules">
    <h1>Courses</h1>
    <a class="past-link" href={href('historique')}><Icon name="archive" size={16} /> Listes passées</a>
    {#if list && total > 0}
      <p class="head-sub">
        {#if allDone}Tout est dans le chariot{:else}<strong class="count">{total - done}</strong> article{total - done > 1 ? 's' : ''} à prendre{/if}
      </p>
      <div class="progress" aria-hidden="true">
        <div class="progress-fill" class:done={allDone} style:transform="scaleX({done / total})"></div>
      </div>
    {/if}
  </header>

  {#if offline}
    <div class="offline-banner" role="status">
      <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="square" stroke-linejoin="miter" aria-hidden="true"><path d="M2 2l20 20M8.5 16.5a5 5 0 0 1 7 0M5 13a10 10 0 0 1 5.17-2.8M19 13a10 10 0 0 0-2.3-1.6M2 8.8a15 15 0 0 1 4.2-2.7M22 8.8A15 15 0 0 0 10.7 5M12 20h.01"/></svg>
      <span>
        Hors connexion{#if cachedAt}{' · '}liste du {timeLabel(cachedAt)}{/if}.
        {#if pendingCount > 0}<strong>{pendingCount} cochage{pendingCount > 1 ? 's' : ''}</strong> en attente, envoyé{pendingCount > 1 ? 's' : ''} au retour du réseau.{:else}Tu peux cocher, ce sera envoyé au retour du réseau.{/if}
      </span>
    </div>
  {/if}

  {#if loading}
    <div class="center"><div class="spinner"></div></div>
  {:else if error && !list}
    <div class="card empty">
      <p class="error-text">{error}</p>
      {#if !offline}<button class="btn btn-outline" onclick={load}>Réessayer</button>{/if}
    </div>
  {:else if !list}
    <!-- Pas de liste : la générer depuis le planning -->
    <div class="card empty">
      <span class="empty-icon"><Icon name="cart" size={44} strokeWidth={1.5} /></span>
      <h2>Pas de liste en cours</h2>
      <p>Elle se remplit toute seule à partir des repas prévus cette semaine.</p>
      <button class="btn btn-primary empty-cta" onclick={generate} disabled={busy}>
        <Icon name="list" /> {busy ? 'Préparation…' : 'Créer la liste depuis le planning'}
      </button>
    </div>
  {:else}
    {#if groups.length === 0 && inCart.length === 0 && atHome.length === 0}
      <div class="card empty"><p>La liste est vide.</p></div>
    {/if}

    <!-- À prendre, par rayon -->
    {#each groups as group, gi (group.category?.id ?? 'none')}
      <section class="card rayon" style="--i: {Math.min(gi, 8)}">
        <h2 class="band rayon-title">
          <span class="rayon-icon" aria-hidden="true">{group.category?.icon || '🛒'}</span>
          {group.category?.name || 'Sans rayon'}
          <span class="rayon-count">{group.items.length}</span>
        </h2>
        <ul class="rows">
          {#each group.items as item, i (item.id)}
            {@const from = sourcesOf(item)}
            <li class="item" style="--i: {Math.min(i, 8)}" animate:flip={{ duration: d(220) }} out:fly={{ x: 60, duration: d(180) }}>
              <button class="row-main" onclick={() => toggle(item)} aria-label="Mettre {item.name} dans le chariot">
                <span class="box" aria-hidden="true"></span>
                <span class="row-text">
                  <span class="row-name">{item.name}</span>
                  {#if from.length > 0}<span class="row-from">pour {from.join(' · ')}</span>{/if}
                </span>
                {#if item.is_extra}<span class="tag tag-light">ajouté</span>{/if}
                {#if item.quantity}<span class="row-qty">{item.quantity}</span>{/if}
              </button>
              <button class="row-remove" onclick={() => remove(item)} aria-label="Retirer {item.name} de la liste">
                <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="square" stroke-linejoin="miter" aria-hidden="true"><path d="M18 6 6 18M6 6l12 12"/></svg>
              </button>
            </li>
          {/each}
        </ul>
      </section>
    {/each}

    {#if allDone}
      <div class="card all-done">
        <Icon name="check-circle" size={22} />
        <span>Tout est pris ! Tu peux terminer les courses.</span>
      </div>
    {/if}

    <!-- Ajouter un article -->
    {#if showAddForm}
      <section class="card add-form">
        <h2 class="band add-title">Ajouter un article</h2>
        <!-- svelte-ignore a11y_autofocus -->
        <input class="input" placeholder="Nom (ex : papier toilette)" bind:value={newItemName} autofocus
          maxlength={LIST_ITEM_NAME_MAX}
          onkeydown={(e) => { if (e.key === 'Enter') addItem() }} />
        <div class="add-row">
          <input class="input" placeholder="Quantité" bind:value={newItemQty} maxlength={LIST_ITEM_QTY_MAX} />
          <select class="input" bind:value={newItemCat} aria-label="Rayon">
            <option value="">Sans rayon</option>
            {#each categories as cat (cat.id)}
              <option value={cat.id}>{cat.icon} {cat.name}</option>
            {/each}
          </select>
        </div>
        <div class="add-actions">
          <button class="btn btn-outline" onclick={() => (showAddForm = false)}>Annuler</button>
          <button class="btn btn-primary" onclick={addItem} disabled={!newItemName.trim() || busy}>Ajouter</button>
        </div>
      </section>
    {:else}
      <div class="tools" class:single={!staples && !pantry}>
        <button class="add-btn deco-neige" onclick={() => (showAddForm = true)}>
          <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="square" stroke-linejoin="miter" aria-hidden="true"><path d="M12 5v14M5 12h14"/></svg>
          Ajouter un article
        </button>
        {#if staples}
          <button class="tool-btn" onclick={() => openDialog('staples')} disabled={offline}>
            <Icon name="star" size={18} />
            Habituels
            {#if staples.length > 0}<span class="tool-count">{staples.length}</span>{/if}
          </button>
        {/if}
        {#if pantry}
          <button class="tool-btn" onclick={() => openDialog('pantry')} disabled={offline}>
            <Icon name="archive" size={18} />
            Mon placard
            {#if pantry.length > 0}<span class="tool-count">{pantry.length}</span>{/if}
          </button>
        {/if}
      </div>
    {/if}

    <!-- Sûrement déjà à la maison (produits du placard) -->
    {#if atHome.length > 0}
      <section class="card cart home">
        <button class="band cart-head" onclick={() => (homeOpen = !homeOpen)} aria-expanded={homeOpen}>
          <Icon name="home" />
          <span>Sûrement déjà à la maison</span>
          <span class="rayon-count">{atHome.length}</span>
          <svg class="chevron" class:open={homeOpen} width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="square" stroke-linejoin="miter" aria-hidden="true"><path d="m6 9 6 6 6-6"/></svg>
        </button>
        {#if homeOpen}
          <p class="home-hint">
            Ils sont dans ton placard.
            <button class="inline-link" onclick={() => openDialog('pantry')} disabled={offline}>Gérer mon placard</button>
          </p>
          <ul class="rows">
            {#each atHome as item (item.id)}
              <li class="item is-home" animate:flip={{ duration: d(220) }} out:fly={{ y: -16, duration: d(180) }}>
                <button class="row-main" onclick={() => toggle(item)} aria-label="Mettre {item.name} dans le chariot">
                  <span class="box" aria-hidden="true"></span>
                  <span class="row-name">{item.name}</span>
                  {#if item.quantity}<span class="row-qty">{item.quantity}</span>{/if}
                </button>
                <button class="need-btn" onclick={() => markNeeded(item)} aria-label="Il manque {item.name} : le remettre dans la liste">
                  Il en manque
                </button>
              </li>
            {/each}
          </ul>
        {/if}
      </section>
    {/if}

    <!-- Dans le chariot -->
    {#if inCart.length > 0}
      <section class="card cart">
        <button class="band cart-head" onclick={() => (cartOpen = !cartOpen)} aria-expanded={cartOpen}>
          <Icon name="cart" />
          <span>Dans le chariot</span>
          <span class="rayon-count">{inCart.length}</span>
          <svg class="chevron" class:open={cartOpen} width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="square" stroke-linejoin="miter" aria-hidden="true"><path d="m6 9 6 6 6-6"/></svg>
        </button>
        {#if cartOpen}
          <ul class="rows">
            {#each inCart as item (item.id)}
              <li class="item is-done" animate:flip={{ duration: d(220) }} in:fly={{ x: -40, duration: d(200) }}>
                <button class="row-main" onclick={() => toggle(item)} aria-label="Remettre {item.name} dans la liste">
                  <span class="box checked" aria-hidden="true"><Icon name="check" size={14} strokeWidth={3} /></span>
                  <span class="row-name">{item.name}</span>
                  {#if item.quantity}<span class="row-qty">{item.quantity}</span>{/if}
                </button>
              </li>
            {/each}
          </ul>
        {/if}
      </section>
    {/if}

    <!-- Actions -->
    <div class="actions">
      <button class="btn btn-primary" onclick={() => (confirm = 'complete')} disabled={busy}>
        <Icon name="check" /> Terminer les courses
      </button>
      <button class="btn btn-outline" onclick={shareList} disabled={toBuy.length === 0}>
        <Icon name="share" /> Partager la liste
      </button>
      <button class="btn btn-outline" onclick={() => (confirm = 'regenerate')} disabled={busy}>
        <Icon name="refresh" /> Mettre à jour depuis le planning
      </button>
      <p class="frozen-hint">La liste ne change pas toute seule : modifier une recette ou le planning ne la touche pas tant que tu ne la mets pas à jour.</p>
    </div>
  {/if}
</div>

{#if dialog === 'staples' && staples && list && familyId}
  <StaplesDialog
    {familyId}
    listId={list.id}
    {staples}
    {categories}
    listItems={items}
    onchange={(next) => { staples = next; persistHousehold() }}
    onadded={reloadItems}
    onclose={() => (dialog = null)}
  />
{/if}

{#if dialog === 'pantry' && pantry && familyId}
  <PantryDialog
    {familyId}
    {pantry}
    {categories}
    listItems={items}
    onchange={(next) => { pantry = next; persistHousehold() }}
    onclose={() => (dialog = null)}
  />
{/if}

{#if confirm === 'complete'}
  <ConfirmDialog title="Terminer les courses ?" confirmLabel="Terminer" {busy}
    onconfirm={complete} oncancel={() => (confirm = null)}>
    {#if done < total}
      Il reste <strong>{total - done} article{total - done > 1 ? 's' : ''}</strong> non pris.
    {:else}
      Tout est pris.
    {/if}
    La liste sera rangée dans l’historique.
  </ConfirmDialog>
{/if}

{#if confirm === 'regenerate'}
  <ConfirmDialog title="Mettre à jour la liste ?" confirmLabel="Mettre à jour" {busy}
    onconfirm={regenerate} oncancel={() => (confirm = null)}>
    Les ingrédients sont recalculés à partir des repas prévus cette semaine.
    <strong>Les articles déjà cochés et ceux ajoutés à la main sont conservés.</strong>
  </ConfirmDialog>
{/if}

<style>
  .page {
    padding: var(--gutter);
    padding-top: calc(var(--gutter) + env(safe-area-inset-top, 0px));
    padding-bottom: calc(84px + env(safe-area-inset-bottom, 0px));
    max-width: 640px;
    margin: 0 auto;
    display: flex;
    flex-direction: column;
    gap: var(--sp-3);
  }

  /* ── En-tête ── */
  .head h1 { padding-right: 56px; }

  .past-link {
    display: inline-flex;
    align-items: center;
    gap: 6px;
    min-height: 44px;
    color: var(--text);
    font-weight: var(--fw-bold);
    font-size: 14px;
    text-decoration: underline;
    text-decoration-thickness: 2px;
    text-underline-offset: 3px;
    touch-action: manipulation;
  }

  .head-sub {
    margin-top: var(--sp-2);
    display: flex;
    align-items: center;
    gap: var(--sp-2);
    font-size: 15px;
    font-weight: var(--fw-medium);
    color: var(--text);
  }

  /* Compteur : petit carré blanc bordé avec ombre */
  .count {
    display: inline-grid;
    place-items: center;
    min-width: 34px;
    height: 34px;
    padding: 0 6px;
    border: var(--line-w) solid var(--line);
    background: var(--surface);
    box-shadow: var(--shadow-sm);
    font-size: var(--fs-lg);
    font-weight: var(--fw-bold);
    color: var(--text);
  }

  /* Progression : bloc carré bordé, remplissage orange (scaleX, pas width) */
  .progress {
    margin-top: var(--sp-3);
    height: 14px;
    border: var(--line-w) solid var(--line);
    background: var(--surface);
    overflow: hidden;
  }

  .progress-fill {
    height: 100%;
    background: var(--accent);
    transform-origin: left center;
    transition: transform var(--dur-sheet) var(--ease-out);
  }

  .progress-fill.done { background: var(--success); }

  /* ── Bandeau hors connexion ── */
  .offline-banner {
    display: flex;
    gap: 10px;
    align-items: flex-start;
    padding: 12px 14px;
    border: var(--line-w) solid var(--line);
    background: var(--highlight);
    box-shadow: var(--shadow-sm);
    color: var(--text);
    font-size: var(--fs-sm);
    line-height: 1.4;
  }

  .offline-banner svg { flex-shrink: 0; margin-top: 1px; }

  /* ── Cartes (.card global : blanc, bordure 2 px, ombre) ── */
  .empty {
    text-align: center;
    padding: var(--sp-6) var(--sp-5);
    color: var(--text-secondary);
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: var(--sp-2);
  }

  .empty h2 { font-size: var(--fs-xl); color: var(--text); text-transform: uppercase; }
  .empty-icon { color: var(--text); }
  .empty-cta { margin-top: var(--sp-3); width: auto; padding: 0 20px; }
  .error-text { color: var(--error); font-weight: var(--fw-medium); }

  /* ── Rayons : carte + bandeau noir ── */
  .rayon { animation: fade-up var(--dur-sheet) var(--ease-out) calc(var(--i, 0) * 45ms) backwards; }

  .rayon-title { font-family: var(--font-body); letter-spacing: var(--tracking-caps); }

  /* L'émoji du rayon reste petit dans le bandeau */
  .rayon-icon { font-size: 14px; line-height: 1; }

  /* Compteur à droite du bandeau */
  .rayon-count {
    margin-left: auto;
    min-width: 22px;
    padding: 0 6px;
    background: var(--text-on-band);
    color: var(--band);
    font-size: var(--fs-xs);
    text-align: center;
  }

  .rows {
    list-style: none;
    margin: 0;
    padding: 0;
  }

  /* Ligne d'article : séparée par un trait 1 px */
  .item {
    display: flex;
    align-items: center;
    animation: fade-up var(--dur-sheet) var(--ease-out) calc(var(--i, 0) * 45ms) backwards;
  }

  .item + .item { border-top: var(--line-thin) solid var(--line); }

  /* Toute la ligne se touche pour cocher (pas seulement la case) */
  .row-main {
    flex: 1;
    min-width: 0;
    min-height: 52px;
    display: flex;
    align-items: center;
    gap: var(--sp-3);
    padding: 8px 4px 8px var(--sp-3);
    border: none;
    background: none;
    color: var(--text);
    font-family: var(--font-body);
    text-align: left;
    cursor: pointer;
    touch-action: manipulation;
  }

  .row-main:active { background: var(--surface-hover); }

  /* Case carrée (comme .check) */
  .box {
    width: 26px;
    height: 26px;
    flex-shrink: 0;
    border: var(--line-w) solid var(--line);
    background: var(--surface);
    display: flex;
    align-items: center;
    justify-content: center;
  }

  .box.checked {
    background: var(--accent);
    color: var(--on-accent);
    animation: check-pop var(--dur-base) var(--ease-snap);
  }

  @keyframes check-pop {
    0% { transform: scale(0.7); }
    100% { transform: scale(1); }
  }

  .row-text {
    flex: 1;
    min-width: 0;
    display: flex;
    flex-direction: column;
    align-items: flex-start;
    gap: 2px;
  }

  /* Note « pour … » : petite étiquette beurre */
  /* Recettes d'origine : simple texte gris, sans cadre ni fond (v1.99.2 : le jaune
     encadré sur chaque ligne alourdissait la liste) */
  .row-from {
    margin-top: 2px;
    color: var(--text-secondary);
    font-size: var(--fs-sm);
    font-weight: var(--fw-regular);
    line-height: 1.35;
    max-width: 100%;
    white-space: normal;
    display: -webkit-box;
    -webkit-box-orient: vertical;
    -webkit-line-clamp: 2;
    line-clamp: 2;
    overflow: hidden;
  }

  .tag-light { background: transparent; color: var(--text-secondary); border-color: var(--text-secondary); }

  .frozen-hint {
    margin: 2px 4px 0;
    font-size: 13px;
    line-height: 1.4;
    color: var(--text-secondary);
  }

  .row-name {
    flex: 1;
    min-width: 0;
    font-size: var(--fs-base);
    font-weight: var(--fw-bold);
    overflow-wrap: anywhere;
  }

  .row-text .row-name { flex: none; }

  .row-qty {
    flex-shrink: 0;
    max-width: 45%;
    font-size: var(--fs-sm);
    font-weight: var(--fw-bold);
    color: var(--text);
    text-align: right;
  }

  .row-remove {
    flex-shrink: 0;
    width: 44px;
    height: 44px;
    border: none;
    background: none;
    color: var(--text-secondary);
    display: flex;
    align-items: center;
    justify-content: center;
    cursor: pointer;
    touch-action: manipulation;
  }

  .row-remove:active { background: var(--error-bg); color: var(--error); }

  /* Coché : barré épais, texte secondaire */
  .is-done .row-name,
  .is-done .row-qty {
    text-decoration: line-through;
    text-decoration-thickness: 2px;
    color: var(--text-secondary);
  }

  .all-done {
    display: flex;
    align-items: center;
    gap: var(--sp-3);
    padding: var(--sp-3) var(--sp-4);
    background: var(--success-bg);
    color: var(--text);
    font-weight: var(--fw-bold);
  }

  /* ── Dans le chariot / à la maison : bandeau cliquable ── */
  .cart-head {
    width: 100%;
    min-height: 48px;
    padding: 0 var(--sp-3);
    border: none;
    justify-content: flex-start;
    font-family: var(--font-body);
    cursor: pointer;
    touch-action: manipulation;
  }

  .cart-head .rayon-count { margin-left: auto; }
  .chevron { transition: transform var(--dur-base) var(--ease-out); }
  .chevron.open { transform: rotate(180deg); }

  /* ── Ajout ── */
  .add-btn {
    min-height: var(--tap);
    display: flex;
    align-items: center;
    justify-content: center;
    gap: var(--sp-2);
    border: var(--line-w) solid var(--line);
    background: var(--accent);
    color: var(--on-accent);
    box-shadow: var(--shadow-sm);
    font-family: var(--font-body);
    font-size: var(--fs-base);
    font-weight: var(--fw-bold);
    text-transform: uppercase;
    letter-spacing: 0.02em;
    cursor: pointer;
    touch-action: manipulation;
    transition: transform var(--dur-fast) var(--ease-out);
  }

  .add-btn:active { transform: translate(var(--press), var(--press)); box-shadow: none; }

  /* Ajouter / Habituels / Mon placard */
  .tools {
    display: grid;
    grid-template-columns: 1fr 1fr;
    gap: var(--sp-3);
  }

  .tools .add-btn { grid-column: 1 / -1; }
  /* Un seul bouton secondaire disponible : il prend toute la largeur */
  .tools .tool-btn:last-child:nth-child(2) { grid-column: 1 / -1; }

  .tool-btn {
    min-height: var(--tap);
    min-width: 0;
    display: flex;
    align-items: center;
    justify-content: center;
    gap: var(--sp-2);
    padding: 0 var(--sp-3);
    border: var(--line-w) solid var(--line);
    background: var(--surface);
    color: var(--text);
    box-shadow: var(--shadow-sm);
    font-family: var(--font-body);
    font-size: var(--fs-base);
    font-weight: var(--fw-bold);
    white-space: nowrap;
    cursor: pointer;
    touch-action: manipulation;
    transition: transform var(--dur-fast) var(--ease-out);
  }

  .tool-btn :global(svg) { flex-shrink: 0; }
  .tool-btn:active:not(:disabled) { transform: translate(var(--press), var(--press)); box-shadow: none; }
  .tool-btn:disabled { opacity: 0.5; cursor: not-allowed; }

  .tool-count {
    min-width: 22px;
    padding: 0 6px;
    background: var(--band);
    color: var(--text-on-band);
    font-size: var(--fs-xs);
    font-weight: var(--fw-bold);
    text-align: center;
  }

  /* ── Sûrement déjà à la maison ── */
  .home-hint {
    padding: var(--sp-2) var(--sp-3) 0;
    font-size: var(--fs-sm);
    color: var(--text-secondary);
  }

  .inline-link {
    min-height: 44px;
    padding: 0 4px;
    border: none;
    background: none;
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

  .inline-link:disabled { opacity: 0.5; }

  .is-home .row-name, .is-home .row-qty { color: var(--text-secondary); }
  .is-home .box { border-style: dashed; }

  .need-btn {
    flex-shrink: 0;
    min-height: 44px;
    margin-right: var(--sp-2);
    padding: 0 var(--sp-3);
    border: var(--line-w) solid var(--line);
    background: var(--accent);
    color: var(--on-accent);
    box-shadow: var(--shadow-sm);
    font-family: var(--font-body);
    font-size: 13px;
    font-weight: var(--fw-bold);
    white-space: nowrap;
    cursor: pointer;
    touch-action: manipulation;
    transition: transform var(--dur-fast) var(--ease-out);
  }

  .need-btn:active { transform: translate(var(--press), var(--press)); box-shadow: none; }

  .add-form {
    display: flex;
    flex-direction: column;
    gap: var(--sp-3);
    padding-bottom: var(--sp-4);
  }

  .add-form > :not(.add-title) { margin-inline: var(--sp-3); }
  .add-title { font-size: 13px; font-family: var(--font-body); letter-spacing: var(--tracking-caps); justify-content: flex-start; }

  .add-row {
    display: grid;
    grid-template-columns: 1fr 1.3fr;
    gap: var(--sp-2);
  }

  .add-actions {
    display: flex;
    gap: var(--sp-3);
  }

  .add-actions .btn { flex: 1; }

  /* ── Actions ── */
  .actions {
    display: flex;
    flex-direction: column;
    gap: var(--sp-3);
    margin-top: var(--sp-2);
  }

  /* ── Divers ── */
  .center { display: flex; justify-content: center; padding: 48px 0; }

  /* Rond d'une icône dessinée (indicateur de chargement) */
  .spinner {
    width: 28px;
    height: 28px;
    border: 3px solid var(--line);
    border-top-color: var(--accent);
    animation: spin 0.7s linear infinite;
  }

  @keyframes spin { to { transform: rotate(360deg); } }

  @media (hover: hover) and (pointer: fine) {
    .row-main:hover { background: var(--surface-hover); }
    .row-remove:hover { background: var(--error-bg); color: var(--error); }
    .add-btn:hover { filter: brightness(1.05); }
    .tool-btn:not(:disabled):hover { background: var(--surface-hover); }
    .need-btn:hover { filter: brightness(1.05); }
    .inline-link:hover { text-decoration-thickness: 3px; }
  }
</style>
