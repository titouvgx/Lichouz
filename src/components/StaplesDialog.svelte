<script module lang="ts">
  import type { KnownIngredient } from '../lib/api/recipes'
  // Ingrédients connus (autocomplétion), gardés entre deux ouvertures de la fenêtre
  let knownCache: KnownIngredient[] | null = null
</script>

<script lang="ts">
  // Fenêtre « Achats habituels » du foyer :
  //   - mode liste : habituels tous cochés → « Ajouter N articles » à la liste en cours
  //   - mode modifier : ajouter (autocomplétion + rayon) / retirer
  //   - état vide : suggestions en un appui
  import { onMount, onDestroy, untrack } from 'svelte'
  import Icon from './Icon.svelte'
  import { toast } from '../lib/toast.svelte'
  import { fetchKnownIngredients } from '../lib/api/recipes'
  import { addStaple, removeStaple, addStaplesToList } from '../lib/api/household'
  import { ingredientKey, normalizeText } from '../lib/quantities'
  import type { Staple, ShoppingCategory, ShoppingListItem } from '../lib/types'

  interface Props {
    familyId: string
    listId: string
    staples: Staple[]
    categories: ShoppingCategory[]
    listItems: ShoppingListItem[]
    /** La liste des habituels a changé (ajout / retrait) */
    onchange: (staples: Staple[]) => void
    /** Des articles ont été ajoutés à la liste : la recharger */
    onadded: () => void | Promise<void>
    onclose: () => void
  }
  let { familyId, listId, staples, categories, listItems, onchange, onadded, onclose }: Props = $props()

  const SUGGESTIONS: { name: string; quantity: string | null; rayon: string }[] = [
    { name: 'Lait', quantity: '1 L', rayon: 'Produits laitiers & œufs' },
    { name: 'Pain', quantity: null, rayon: 'Épicerie salée' },
    { name: 'Œufs', quantity: '6', rayon: 'Produits laitiers & œufs' },
    { name: 'Beurre', quantity: null, rayon: 'Produits laitiers & œufs' },
    { name: 'Café', quantity: null, rayon: 'Boissons' },
    { name: 'Papier toilette', quantity: null, rayon: 'Hygiène & maison' },
    { name: 'Yaourts', quantity: null, rayon: 'Produits laitiers & œufs' },
    { name: 'Bananes', quantity: null, rayon: 'Fruits & légumes' },
    { name: 'Pommes', quantity: null, rayon: 'Fruits & légumes' },
    { name: 'Jus d’orange', quantity: null, rayon: 'Boissons' },
  ]

  // ── État ──
  // Fenêtre recréée à chaque ouverture : valeurs de départ lues une fois.
  let list = $state<Staple[]>(untrack(() => [...staples]))
  let editing = $state(untrack(() => staples.length === 0))
  let selected = $state<Record<string, boolean>>(
    untrack(() => Object.fromEntries(staples.map((s) => [s.id, true]))),
  )
  let saving = $state(false)
  let dialogEl: HTMLDivElement | undefined = $state()

  // Formulaire d'ajout
  let newName = $state('')
  let newQty = $state('')
  let newCat = $state('')
  let nameEl: HTMLInputElement | undefined = $state()

  // Autocomplétion (même logique que le formulaire de recette)
  let known = $state<KnownIngredient[]>(knownCache ?? [])
  let acResults = $state<KnownIngredient[]>([])
  let acIndex = $state(-1)

  onMount(() => {
    document.body.style.overflow = 'hidden'
    dialogEl?.focus()
    if (!knownCache) {
      fetchKnownIngredients(familyId)
        .then((data) => { knownCache = data; known = data })
        .catch(() => { /* silencieux : pas d'autocomplétion */ })
    }
  })
  onDestroy(() => { document.body.style.overflow = '' })

  // ── Dérivés ──
  const inList = $derived(new Set(listItems.filter((i) => !i.checked).map((i) => ingredientKey(i.name))))
  const chosen = $derived(list.filter((s) => selected[s.id]))
  const staplesKeys = $derived(new Set(list.map((s) => ingredientKey(s.name))))
  const ideas = $derived(SUGGESTIONS.filter((s) => !staplesKeys.has(ingredientKey(s.name))))
  const allSelected = $derived(list.length > 0 && chosen.length === list.length)

  function cat(id: string | null): ShoppingCategory | undefined {
    return id ? categories.find((c) => c.id === id) : undefined
  }

  function update(next: Staple[]) {
    list = next
    onchange(next)
  }

  // ── Autocomplétion ──
  function findKnown(name: string): KnownIngredient | undefined {
    const n = normalizeText(name)
    return n ? known.find((ki) => normalizeText(ki.name) === n) : undefined
  }

  function onNameInput() {
    const query = normalizeText(newName)
    acIndex = -1
    if (!query) { acResults = []; return }
    const starts: KnownIngredient[] = []
    const contains: KnownIngredient[] = []
    for (const ki of known) {
      const n = normalizeText(ki.name)
      if (n === query) continue // déjà tapé en entier : rien à proposer
      if (n.startsWith(query)) starts.push(ki)
      else if (n.includes(query)) contains.push(ki)
    }
    acResults = [...starts, ...contains].slice(0, 5)
    const exact = findKnown(newName)
    if (exact?.shopping_category_id && !newCat) newCat = exact.shopping_category_id
  }

  function pick(ki: KnownIngredient) {
    newName = ki.name
    if (ki.shopping_category_id) newCat = ki.shopping_category_id
    acResults = []
    acIndex = -1
    nameEl?.focus()
  }

  function onNameKey(e: KeyboardEvent) {
    if (acResults.length > 0 && (e.key === 'ArrowDown' || e.key === 'ArrowUp')) {
      e.preventDefault()
      const n = acResults.length
      acIndex = e.key === 'ArrowDown' ? (acIndex + 1) % n : (acIndex - 1 + n) % n
    } else if (e.key === 'Enter') {
      e.preventDefault()
      if (acIndex >= 0 && acResults[acIndex]) pick(acResults[acIndex])
      else create()
    } else if (e.key === 'Escape' && acResults.length > 0) {
      e.stopPropagation()
      acResults = []
    }
  }

  // ── Actions ──
  async function createStaple(name: string, quantity: string | null, categoryId: string | null): Promise<boolean> {
    if (staplesKeys.has(ingredientKey(name))) {
      toast.info(`${name} est déjà dans tes habituels`)
      return false
    }
    const position = list.reduce((m, s) => Math.max(m, s.position), -1) + 1
    const staple = await addStaple(familyId, name, quantity, categoryId, position)
    selected[staple.id] = true
    update([...list, staple])
    return true
  }

  async function create() {
    const name = newName.trim()
    if (!name || saving) return
    saving = true
    try {
      const ok = await createStaple(name, newQty || null, newCat || findKnown(name)?.shopping_category_id || null)
      if (ok) {
        newName = ''
        newQty = ''
        newCat = ''
        acResults = []
        nameEl?.focus()
      }
    } catch (e: any) {
      toast.error(e.message)
    } finally {
      saving = false
    }
  }

  async function addIdea(idea: (typeof SUGGESTIONS)[number]) {
    if (saving) return
    saving = true
    try {
      const catId = findKnown(idea.name)?.shopping_category_id
        ?? categories.find((c) => c.name === idea.rayon)?.id
        ?? null
      await createStaple(idea.name, idea.quantity, catId)
    } catch (e: any) {
      toast.error(e.message)
    } finally {
      saving = false
    }
  }

  async function remove(s: Staple) {
    const before = list
    update(list.filter((x) => x.id !== s.id))
    try {
      await removeStaple(s.id)
    } catch (e: any) {
      update(before)
      toast.error(e.message)
    }
  }

  function toggleAll() {
    const v = !allSelected
    for (const s of list) selected[s.id] = v
  }

  async function addToList() {
    if (saving || chosen.length === 0) return
    saving = true
    try {
      const n = chosen.length
      const added = await addStaplesToList(listId, chosen)
      const skipped = n - added
      await onadded()
      if (added === 0) {
        toast.info(skipped > 1 ? 'Ils sont déjà tous dans la liste' : 'Déjà dans la liste')
      } else {
        toast.success(
          `${added} article${added > 1 ? 's' : ''} ajouté${added > 1 ? 's' : ''}`
            + (skipped > 0 ? ` · ${skipped} déjà dans la liste` : ''),
        )
      }
      onclose()
    } catch (e: any) {
      toast.error(e.message)
    } finally {
      saving = false
    }
  }

  function onKey(e: KeyboardEvent) {
    if (e.key === 'Escape' && !saving) onclose()
  }
</script>

<svelte:window onkeydown={onKey} />

<!-- svelte-ignore a11y_click_events_have_key_events -->
<!-- svelte-ignore a11y_no_static_element_interactions -->
<div class="ui-overlay center" onclick={() => { if (!saving) onclose() }}>
  <!-- svelte-ignore a11y_click_events_have_key_events -->
  <!-- svelte-ignore a11y_no_static_element_interactions -->
  <div
    class="ui-dialog hd"
    bind:this={dialogEl}
    tabindex="-1"
    role="dialog"
    aria-modal="true"
    aria-labelledby="sd-title"
    onclick={(e) => e.stopPropagation()}
  >
    <header class="hd-header">
      <div class="hd-titles">
        {#if editing && list.length > 0}
          <button class="hd-back" onclick={() => (editing = false)}>
            <Icon name="arrow-left" size={16} /> Retour
          </button>
        {/if}
        <h2 id="sd-title">{editing ? 'Mes habituels' : 'Achats habituels'}</h2>
        <p class="hd-sub">
          {#if list.length === 0}Ce que vous achetez presque chaque semaine.
          {:else if editing}{list.length} produit{list.length > 1 ? 's' : ''} · partagés avec ton foyer
          {:else}Coche ce qu’il faut cette fois-ci.{/if}
        </p>
      </div>
      <button class="hd-close" onclick={onclose} aria-label="Fermer" disabled={saving}>
        <Icon name="x" size={18} strokeWidth={2.5} />
      </button>
    </header>

    {#if !editing}
      <!-- ── Mode liste : choisir puis ajouter ── -->
      <div class="hd-toolbar">
        <button class="link-btn" onclick={toggleAll}>{allSelected ? 'Tout décocher' : 'Tout cocher'}</button>
        <button class="link-btn" onclick={() => (editing = true)}>
          <Icon name="pencil" size={15} /> Modifier mes habituels
        </button>
      </div>

      <div class="hd-scroll">
        <ul class="st-list">
          {#each list as s, si (s.id)}
            {@const c = cat(s.shopping_category_id)}
            <li style="--i: {Math.min(si, 8)}">
              <label class="st-row" class:off={!selected[s.id]}>
                <input type="checkbox" bind:checked={selected[s.id]} />
                <span class="st-box" aria-hidden="true"><Icon name="check" size={14} strokeWidth={3} /></span>
                <span class="st-emoji" aria-hidden="true">{c?.icon ?? '🛒'}</span>
                <span class="st-name">
                  {s.name}
                  {#if inList.has(ingredientKey(s.name))}<span class="st-tag">déjà dans la liste</span>{/if}
                </span>
                {#if s.quantity}<span class="st-qty">{s.quantity}</span>{/if}
              </label>
            </li>
          {/each}
        </ul>
      </div>

      <div class="hd-actions">
        <button class="btn btn-primary" onclick={addToList} disabled={saving || chosen.length === 0}>
          <Icon name="cart" />
          {saving ? 'Ajout…' : `Ajouter ${chosen.length} article${chosen.length > 1 ? 's' : ''}`}
        </button>
      </div>
    {:else}
      <!-- ── Mode modifier ── -->
      <div class="hd-scroll">
        {#if list.length === 0}
          <div class="hd-empty">
            <span class="hd-empty-icon"><Icon name="star" size={30} strokeWidth={1.6} /></span>
            <p>Note-les une fois : ensuite, un appui suffit pour les remettre dans la liste chaque semaine.</p>
          </div>
        {/if}

        <div class="add-box">
          <label class="label" for="sd-name">Ajouter un habituel</label>
          <input
            id="sd-name"
            class="input"
            placeholder="Ex : lait, pain, café…"
            autocomplete="off"
            enterkeyhint="done"
            bind:this={nameEl}
            bind:value={newName}
            oninput={onNameInput}
            onkeydown={onNameKey}
            role="combobox"
            aria-expanded={acResults.length > 0}
            aria-controls="sd-ac"
            aria-activedescendant={acIndex >= 0 ? `sd-ac-${acIndex}` : undefined}
          />
          {#if acResults.length > 0}
            <ul class="ac" id="sd-ac" role="listbox" aria-label="Suggestions">
              {#each acResults as ki, k (ki.name)}
                {@const c = cat(ki.shopping_category_id)}
                <!-- Clavier géré par le champ (flèches + Entrée) -->
                <!-- svelte-ignore a11y_click_events_have_key_events -->
                <li
                  id="sd-ac-{k}"
                  role="option"
                  aria-selected={k === acIndex}
                  class="ac-item"
                  class:active={k === acIndex}
                  onpointerdown={(e) => e.preventDefault()}
                  onclick={() => pick(ki)}
                >
                  <span class="ac-emoji" aria-hidden="true">{c?.icon ?? '🛒'}</span>
                  <span class="ac-name">{ki.name}</span>
                  {#if c}<span class="ac-cat">{c.name}</span>{/if}
                </li>
              {/each}
            </ul>
          {/if}
          <div class="add-row">
            <input class="input" placeholder="Qté : 2 L…" bind:value={newQty} aria-label="Quantité"
              onkeydown={(e) => { if (e.key === 'Enter') create() }} />
            <select class="input" bind:value={newCat} aria-label="Rayon">
              <option value="">Sans rayon</option>
              {#each categories as c (c.id)}
                <option value={c.id}>{c.icon} {c.name}</option>
              {/each}
            </select>
          </div>
          <button class="btn btn-primary add-submit" onclick={create} disabled={!newName.trim() || saving}>
            <Icon name="plus" size={18} /> Ajouter
          </button>
        </div>

        {#if list.length > 0}
          <h3 class="hd-section">Mes habituels</h3>
          <ul class="ed-list">
            {#each list as s (s.id)}
              {@const c = cat(s.shopping_category_id)}
              <li class="ed-row">
                <span class="st-emoji" aria-hidden="true">{c?.icon ?? '🛒'}</span>
                <span class="st-name">{s.name}</span>
                {#if s.quantity}<span class="st-qty">{s.quantity}</span>{/if}
                <button class="ed-remove" onclick={() => remove(s)} aria-label="Retirer {s.name} des habituels">
                  <Icon name="trash" size={17} />
                </button>
              </li>
            {/each}
          </ul>
        {/if}
        {#if ideas.length > 0}
          <h3 class="hd-section">{list.length === 0 ? 'Idées pour commencer' : 'Idées'}</h3>
          <div class="ideas">
            {#each ideas as idea (idea.name)}
              <button class="idea" onclick={() => addIdea(idea)} disabled={saving}>
                <Icon name="plus" size={14} strokeWidth={2.5} /> {idea.name}
              </button>
            {/each}
          </div>
        {/if}

      </div>

      {#if list.length > 0}
        <div class="hd-actions">
          <button class="btn btn-outline done-btn" onclick={() => (editing = false)}>
            <Icon name="check" /> Terminé
          </button>
        </div>
      {/if}
    {/if}
  </div>
</div>

<style>
  /* Fenêtre centrée : voile et cadre globaux (.ui-overlay.center, .ui-dialog).
     Ici : en-tête fixe, zone qui défile, pied fixe. */
  .hd {
    width: min(460px, 100%);
    max-height: min(88svh, 760px);
    display: flex;
    flex-direction: column;
    padding: 0;
    overflow: hidden;
  }

  .hd-header {
    display: flex;
    align-items: flex-start;
    justify-content: space-between;
    gap: var(--sp-3);
    padding: var(--sp-4) var(--sp-4) var(--sp-3);
  }

  .hd-titles { min-width: 0; }
  .hd-header h2 { font-size: var(--fs-xl); text-transform: uppercase; color: var(--text); }
  .hd-sub { margin-top: 4px; font-size: var(--fs-sm); line-height: 1.4; color: var(--text-secondary); }

  .hd-close {
    flex-shrink: 0;
    width: 44px;
    height: 44px;
    border: var(--line-w) solid var(--line);
    background: var(--surface);
    color: var(--text);
    box-shadow: var(--shadow-sm);
    display: flex;
    align-items: center;
    justify-content: center;
    cursor: pointer;
    touch-action: manipulation;
    transition: transform var(--dur-fast) var(--ease-out);
  }
  .hd-close:active:not(:disabled) { transform: translate(var(--press), var(--press)); box-shadow: none; }

  .hd-scroll {
    flex: 1;
    min-height: 0;
    overflow-y: auto;
    overscroll-behavior: contain;
    -webkit-overflow-scrolling: touch;
    padding: 0 var(--sp-4) var(--sp-4);
  }

  /* Titre de rubrique : bandeau noir */
  .hd-section {
    display: flex;
    align-items: center;
    gap: var(--sp-2);
    margin: var(--sp-4) 0 var(--sp-2);
    padding: 4px 8px;
    background: var(--band);
    color: var(--text-on-band);
    font-family: var(--font-body);
    font-size: 13px;
    font-weight: var(--fw-bold);
    letter-spacing: var(--tracking-caps);
    text-transform: uppercase;
  }

  .ac {
    list-style: none;
    margin: 0;
    padding: 0;
    border: var(--line-w) solid var(--line);
    background: var(--bg);
    box-shadow: var(--shadow-sm);
  }

  .ac-item {
    display: flex;
    align-items: center;
    gap: 10px;
    min-height: 44px;
    padding: 0 10px;
    cursor: pointer;
    touch-action: manipulation;
    color: var(--text);
  }

  .ac-item + .ac-item { border-top: var(--line-thin) solid var(--line); }
  .ac-item.active, .ac-item:active { background: var(--highlight); }
  .ac-emoji { font-size: 17px; }
  .ac-name { flex: 1; min-width: 0; font-weight: var(--fw-bold); }
  .ac-cat { font-size: var(--fs-xs); color: var(--text-secondary); white-space: nowrap; }

  .hd-actions {
    padding: var(--sp-3) var(--sp-4) var(--sp-4);
    border-top: var(--line-w) solid var(--line);
  }

  .done-btn { width: 100%; }

  /* Puce « idée » : carrée, bord pointillé */
  .ideas { display: flex; flex-wrap: wrap; gap: var(--sp-2); }

  .idea {
    display: inline-flex;
    align-items: center;
    gap: 6px;
    min-height: 44px;
    padding: 0 14px;
    border: var(--line-w) dashed var(--line);
    background: var(--surface);
    color: var(--text);
    font-family: var(--font-body);
    font-size: var(--fs-sm);
    font-weight: var(--fw-bold);
    cursor: pointer;
    touch-action: manipulation;
    transition: transform var(--dur-fast) var(--ease-out);
  }

  .idea:active:not(:disabled) { transform: translate(2px, 2px); background: var(--highlight); }
  .idea:disabled { opacity: 0.5; cursor: not-allowed; }

  .hd-back {
    display: inline-flex;
    align-items: center;
    gap: 4px;
    margin: -8px 0 2px -6px;
    min-height: 44px;
    padding: 0 6px;
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

  .hd-toolbar {
    display: flex;
    justify-content: space-between;
    align-items: center;
    gap: var(--sp-2);
    padding: 0 var(--sp-3) var(--sp-1);
  }

  .link-btn {
    display: inline-flex;
    align-items: center;
    gap: 6px;
    min-height: 44px;
    padding: 0 6px;
    border: none;
    background: none;
    color: var(--text);
    font-family: var(--font-body);
    font-size: var(--fs-sm);
    font-weight: var(--fw-bold);
    white-space: nowrap;
    text-decoration: underline;
    text-decoration-thickness: 2px;
    text-underline-offset: 3px;
    cursor: pointer;
    touch-action: manipulation;
  }

  /* ── Liste à cocher : carte à lignes séparées d'un trait ── */
  .st-list, .ed-list {
    list-style: none;
    margin: 0;
    padding: 0;
    border: var(--line-w) solid var(--line);
    background: var(--surface);
  }

  .st-list li { animation: fade-up var(--dur-sheet) var(--ease-out) calc(var(--i, 0) * 45ms) backwards; }

  .st-row {
    position: relative;
    display: flex;
    align-items: center;
    gap: 10px;
    min-height: 52px;
    padding: 6px 10px;
    cursor: pointer;
    touch-action: manipulation;
  }

  .st-list li + li { border-top: var(--line-thin) solid var(--line); }
  .st-row:active { background: var(--surface-hover); }

  .st-row input {
    position: absolute;
    opacity: 0;
    width: 1px;
    height: 1px;
    pointer-events: none;
  }

  /* Case carrée : orange quand l'article est choisi */
  .st-box {
    width: 26px;
    height: 26px;
    flex-shrink: 0;
    border: var(--line-w) solid var(--line);
    background: var(--accent);
    color: var(--on-accent);
    display: flex;
    align-items: center;
    justify-content: center;
  }

  .st-row.off .st-box { background: var(--surface); color: transparent; }
  .st-row.off .st-name, .st-row.off .st-qty, .st-row.off .st-emoji { opacity: 0.55; }
  .st-row input:focus-visible + .st-box { outline: 3px solid var(--accent); outline-offset: 2px; }

  .st-emoji { font-size: 16px; flex-shrink: 0; }

  .st-name {
    flex: 1;
    min-width: 0;
    font-size: var(--fs-base);
    font-weight: var(--fw-bold);
    color: var(--text);
    overflow-wrap: anywhere;
  }

  .st-tag {
    display: block;
    width: fit-content;
    margin-top: 2px;
    padding: 1px 6px;
    border: var(--line-thin) solid var(--line);
    background: var(--butter);
    color: var(--ink);
    font-size: var(--fs-xs);
    font-weight: var(--fw-medium);
  }

  .st-qty {
    flex-shrink: 0;
    max-width: 40%;
    font-size: var(--fs-sm);
    font-weight: var(--fw-bold);
    color: var(--text);
    text-align: right;
  }

  /* ── Mode modifier ── */
  .hd-empty {
    display: flex;
    gap: var(--sp-3);
    align-items: flex-start;
    margin-bottom: var(--sp-4);
    padding: var(--sp-3);
    border: var(--line-w) dashed var(--line);
    background: var(--surface-sunken);
    color: var(--text);
    font-size: var(--fs-sm);
    line-height: 1.45;
  }

  .hd-empty-icon { flex-shrink: 0; }

  .add-box { display: flex; flex-direction: column; gap: var(--sp-2); }
  .add-box .label { margin-bottom: 0; }

  .add-row {
    display: grid;
    grid-template-columns: 1fr 1.2fr;
    gap: var(--sp-2);
  }

  .add-row .input { min-width: 0; padding-left: 12px; padding-right: 12px; }

  .ed-row {
    display: flex;
    align-items: center;
    gap: 10px;
    min-height: 52px;
    padding-left: 10px;
  }

  .ed-row + .ed-row { border-top: var(--line-thin) solid var(--line); }

  .ed-remove {
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

  .ed-remove:active { background: var(--error-bg); color: var(--error); }

  @media (hover: hover) and (pointer: fine) {
    .st-row:hover { background: var(--surface-hover); }
    .ac-item:hover { background: var(--highlight); }
    .idea:hover:not(:disabled) { background: var(--surface-hover); }
    .ed-remove:hover { background: var(--error-bg); color: var(--error); }
    .link-btn:hover, .hd-back:hover { text-decoration-thickness: 3px; }
  }
</style>
