<script module lang="ts">
  import type { KnownIngredient } from '../lib/api/recipes'
  // Ingrédients connus (autocomplétion), gardés entre deux ouvertures de la fenêtre
  let knownCache: KnownIngredient[] | null = null
</script>

<script lang="ts">
  // Fenêtre « Mon placard » : produits toujours à la maison (sel, huile…).
  // Les articles de la liste qui y correspondent sont rangés dans
  // « Sûrement déjà à la maison » au lieu des rayons.
  import { onMount, onDestroy, untrack } from 'svelte'
  import Icon from './Icon.svelte'
  import { toast } from '../lib/toast.svelte'
  import { fetchKnownIngredients } from '../lib/api/recipes'
  import { addPantryItem, removePantryItem, isInPantry } from '../lib/api/household'
  import { ingredientKey, normalizeText } from '../lib/quantities'
  import type { PantryItem, ShoppingCategory, ShoppingListItem } from '../lib/types'

  interface Props {
    familyId: string
    pantry: PantryItem[]
    categories: ShoppingCategory[]
    listItems: ShoppingListItem[]
    onchange: (pantry: PantryItem[]) => void
    onclose: () => void
  }
  let { familyId, pantry, categories, listItems, onchange, onclose }: Props = $props()

  const STARTERS = ['Sel', 'Poivre', 'Huile d’olive', 'Sucre', 'Farine', 'Pâtes', 'Riz', 'Vinaigre', 'Moutarde', 'Ail']

  // ── État ──
  let list = $state<PantryItem[]>(untrack(() => [...pantry]))
  let saving = $state(false)
  let dialogEl: HTMLDivElement | undefined = $state()
  let newName = $state('')
  let nameEl: HTMLInputElement | undefined = $state()

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
  const sorted = $derived([...list].sort((a, b) => a.name.localeCompare(b.name, 'fr')))

  /** Articles de la liste (issus du planning, pas encore pris) qu'on pourrait ranger au placard */
  const fromList = $derived.by(() => {
    const seen = new Set<string>()
    const out: string[] = []
    for (const i of [...listItems].sort((a, b) => a.position - b.position)) {
      if (i.is_extra || i.checked) continue
      const k = ingredientKey(i.name)
      if (seen.has(k) || isInPantry(i.name, list)) continue
      seen.add(k)
      out.push(i.name)
    }
    return out
  })

  const starters = $derived(list.length === 0 ? STARTERS.filter((s) => !isInPantry(s, list)) : [])

  function cat(id: string | null): ShoppingCategory | undefined {
    return id ? categories.find((c) => c.id === id) : undefined
  }

  // ── Autocomplétion (même logique que le formulaire de recette) ──
  function onNameInput() {
    const query = normalizeText(newName)
    acIndex = -1
    if (!query) { acResults = []; return }
    const starts: KnownIngredient[] = []
    const contains: KnownIngredient[] = []
    for (const ki of known) {
      const n = normalizeText(ki.name)
      if (n === query) continue
      if (n.startsWith(query)) starts.push(ki)
      else if (n.includes(query)) contains.push(ki)
    }
    acResults = [...starts, ...contains].slice(0, 5)
  }

  function onNameKey(e: KeyboardEvent) {
    if (acResults.length > 0 && (e.key === 'ArrowDown' || e.key === 'ArrowUp')) {
      e.preventDefault()
      const n = acResults.length
      acIndex = e.key === 'ArrowDown' ? (acIndex + 1) % n : (acIndex - 1 + n) % n
    } else if (e.key === 'Enter') {
      e.preventDefault()
      if (acIndex >= 0 && acResults[acIndex]) add(acResults[acIndex].name, true)
      else add(newName, true)
    } else if (e.key === 'Escape' && acResults.length > 0) {
      e.stopPropagation()
      acResults = []
    }
  }

  // ── Actions ──
  async function add(raw: string, fromInput = false) {
    const name = raw.trim()
    if (!name || saving) return
    if (list.some((p) => ingredientKey(p.name) === ingredientKey(name))) {
      toast.info(`${name} est déjà dans ton placard`)
      return
    }
    saving = true
    try {
      const item = await addPantryItem(familyId, name)
      if (item) {
        list = [...list, item]
        onchange(list)
      } else {
        toast.info(`${name} est déjà dans ton placard`)
      }
      if (fromInput) {
        newName = ''
        acResults = []
        acIndex = -1
        nameEl?.focus()
      }
    } catch (e: any) {
      toast.error(e.message)
    } finally {
      saving = false
    }
  }

  async function remove(p: PantryItem) {
    const before = list
    list = list.filter((x) => x.id !== p.id)
    onchange(list)
    try {
      await removePantryItem(p.id)
    } catch (e: any) {
      list = before
      onchange(list)
      toast.error(e.message)
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
    aria-labelledby="pd-title"
    onclick={(e) => e.stopPropagation()}
  >
    <header class="hd-header">
      <div class="hd-titles">
        <h2 id="pd-title">Mon placard</h2>
        <p class="hd-sub">Ce qu’on a presque toujours à la maison. Ces produits sont mis à part dans la liste.</p>
      </div>
      <button class="hd-close" onclick={onclose} aria-label="Fermer">
        <Icon name="x" size={18} strokeWidth={2.5} />
      </button>
    </header>

    <div class="hd-scroll">
      <div class="add-box">
        <div class="add-line">
          <input
            class="input"
            placeholder="Ajouter (ex : sel, huile…)"
            aria-label="Produit à ajouter au placard"
            autocomplete="off"
            enterkeyhint="done"
            bind:this={nameEl}
            bind:value={newName}
            oninput={onNameInput}
            onkeydown={onNameKey}
            role="combobox"
            aria-expanded={acResults.length > 0}
            aria-controls="pd-ac"
            aria-activedescendant={acIndex >= 0 ? `pd-ac-${acIndex}` : undefined}
          />
          <button class="btn btn-primary add-submit" onclick={() => add(newName, true)} disabled={!newName.trim() || saving} aria-label="Ajouter au placard">
            <Icon name="plus" size={20} strokeWidth={2.5} />
          </button>
        </div>
        {#if acResults.length > 0}
          <ul class="ac" id="pd-ac" role="listbox" aria-label="Suggestions">
            {#each acResults as ki, k (ki.name)}
              {@const c = cat(ki.shopping_category_id)}
              <!-- Clavier géré par le champ (flèches + Entrée) -->
              <!-- svelte-ignore a11y_click_events_have_key_events -->
              <li
                id="pd-ac-{k}"
                role="option"
                aria-selected={k === acIndex}
                class="ac-item"
                class:active={k === acIndex}
                onpointerdown={(e) => e.preventDefault()}
                onclick={() => add(ki.name, true)}
              >
                <span class="ac-emoji" aria-hidden="true">{c?.icon ?? '🛒'}</span>
                <span class="ac-name">{ki.name}</span>
                {#if isInPantry(ki.name, list)}<span class="ac-cat">déjà au placard</span>{/if}
              </li>
            {/each}
          </ul>
        {/if}
      </div>

      <h3 class="hd-section">
        Au placard
        {#if list.length > 0}<span class="count">{list.length}</span>{/if}
      </h3>
      {#if sorted.length === 0}
        <p class="hd-hint">Rien pour l’instant. Ajoute le sel, l’huile, les épices… : ils ne t’encombreront plus dans les rayons.</p>
      {:else}
        <ul class="pantry">
          {#each sorted as p (p.id)}
            <li class="p-chip">
              <span class="p-name">{p.name}</span>
              <button class="p-remove" onclick={() => remove(p)} aria-label="Retirer {p.name} du placard">
                <Icon name="x" size={15} strokeWidth={2.5} />
              </button>
            </li>
          {/each}
        </ul>
      {/if}

      {#if fromList.length > 0}
        <h3 class="hd-section">Dans ta liste actuelle</h3>
        <p class="hd-hint">Un appui pour dire « on en a toujours ».</p>
        <div class="ideas">
          {#each fromList as name (name)}
            <button class="idea" onclick={() => add(name)} disabled={saving}>
              <Icon name="plus" size={14} strokeWidth={2.5} /> {name}
            </button>
          {/each}
        </div>
      {/if}

      {#if starters.length > 0}
        <h3 class="hd-section">Pour commencer</h3>
        <div class="ideas">
          {#each starters as name (name)}
            <button class="idea" onclick={() => add(name)} disabled={saving}>
              <Icon name="plus" size={14} strokeWidth={2.5} /> {name}
            </button>
          {/each}
        </div>
      {/if}

    </div>

    <div class="hd-actions">
      <button class="btn btn-outline done-btn" onclick={onclose}><Icon name="check" /> Terminé</button>
    </div>
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

  .add-box { display: flex; flex-direction: column; gap: var(--sp-2); }
  .add-line { display: flex; gap: var(--sp-2); }
  .add-line .input { flex: 1; min-width: 0; }

  .add-submit {
    flex-shrink: 0;
    width: 52px;
    min-height: var(--tap);
    padding: 0;
  }

  .count {
    margin-left: auto;
    min-width: 22px;
    padding: 0 6px;
    background: var(--text-on-band);
    color: var(--band);
    font-size: var(--fs-xs);
    letter-spacing: 0;
    text-align: center;
  }

  .hd-hint {
    margin: 0 0 var(--sp-3);
    font-size: var(--fs-sm);
    line-height: 1.4;
    color: var(--text-secondary);
  }

  /* Placard : puces carrées avec une croix */
  .pantry {
    list-style: none;
    margin: 0;
    padding: 0;
    display: flex;
    flex-wrap: wrap;
    gap: var(--sp-2);
  }

  .p-chip {
    display: inline-flex;
    align-items: center;
    min-height: 44px;
    padding-left: 12px;
    border: var(--line-w) solid var(--line);
    background: var(--surface);
    box-shadow: var(--shadow-sm);
    animation: chip-in var(--dur-base) var(--ease-out);
  }

  @keyframes chip-in { from { opacity: 0; transform: translateY(6px); } }

  .p-name { font-size: var(--fs-sm); font-weight: var(--fw-bold); color: var(--text); }

  .p-remove {
    width: 44px;
    height: 44px;
    border: none;
    background: none;
    color: var(--text);
    display: flex;
    align-items: center;
    justify-content: center;
    cursor: pointer;
    touch-action: manipulation;
  }

  .p-remove:active { background: var(--error-bg); color: var(--error); }

  @media (hover: hover) and (pointer: fine) {
    .ac-item:hover { background: var(--highlight); }
    .idea:hover:not(:disabled) { background: var(--surface-hover); }
    .p-remove:hover { background: var(--error-bg); color: var(--error); }
  }
</style>
