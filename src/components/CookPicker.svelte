<script lang="ts">
  // « Qui cuisine ? » : petite fenêtre centrée pour choisir le cuisinier d'un repas
  // parmi les membres du foyer (ou personne).
  import Icon from './Icon.svelte'
  import { onMount, onDestroy } from 'svelte'
  import type { FamilyMember } from '../lib/types'

  interface Props {
    /** Membres du foyer (déjà triés) */
    members: FamilyMember[]
    /** Cuisinier actuel (null = personne) */
    currentId: string | null
    /** Mon identifiant, pour afficher « moi » */
    meId?: string | null
    /** Sous-titre : jour, repas, recette */
    subtitle: string
    /** Membres en cours de chargement */
    loading?: boolean
    onselect: (cookId: string | null) => void
    onclose: () => void
  }
  let { members, currentId, meId = null, subtitle, loading = false, onselect, onclose }: Props = $props()

  let dialogEl: HTMLDivElement | undefined = $state()
  // Élément qui avait le focus avant l'ouverture (la pastille) : on le lui rend à la fermeture
  let opener: HTMLElement | null = null

  onMount(() => {
    opener = document.activeElement instanceof HTMLElement ? document.activeElement : null
    document.body.style.overflow = 'hidden'
    // Focus sur le choix actuel, sinon sur la fenêtre
    const current = dialogEl?.querySelector<HTMLElement>('[aria-pressed="true"]')
    ;(current ?? dialogEl)?.focus()
  })
  onDestroy(() => {
    document.body.style.overflow = ''
    if (opener?.isConnected) opener.focus()
  })

  function initial(name: string): string {
    return name.trim().charAt(0).toUpperCase() || '?'
  }

  function onKey(e: KeyboardEvent) {
    if (e.key === 'Escape') {
      e.preventDefault()
      onclose()
      return
    }
    // Garde le focus dans la fenêtre (Tab / Maj+Tab)
    if (e.key === 'Tab' && dialogEl) {
      const items = [...dialogEl.querySelectorAll<HTMLElement>('button:not([disabled])')]
      if (items.length === 0) return
      const first = items[0]
      const last = items[items.length - 1]
      const active = document.activeElement
      if (e.shiftKey && (active === first || active === dialogEl)) {
        e.preventDefault()
        last.focus()
      } else if (!e.shiftKey && active === last) {
        e.preventDefault()
        first.focus()
      }
    }
  }
</script>

<svelte:window onkeydown={onKey} />

<!-- svelte-ignore a11y_click_events_have_key_events -->
<!-- svelte-ignore a11y_no_static_element_interactions -->
<div class="ui-overlay center" onclick={onclose}>
  <!-- svelte-ignore a11y_click_events_have_key_events -->
  <!-- svelte-ignore a11y_no_static_element_interactions -->
  <div
    class="ui-dialog cp"
    bind:this={dialogEl}
    tabindex="-1"
    role="dialog"
    aria-modal="true"
    aria-labelledby="cp-title"
    aria-describedby="cp-sub"
    onclick={(e) => e.stopPropagation()}
  >
    <div class="cp-head">
      <span class="cp-head-icon" aria-hidden="true"><Icon name="chef" size={20} /></span>
      <div class="cp-head-text">
        <h2 id="cp-title">Qui cuisine ?</h2>
        <p id="cp-sub" class="cp-sub">{subtitle}</p>
      </div>
      <button class="btn btn-icon cp-close" onclick={onclose} aria-label="Fermer">
        <Icon name="x" size={18} strokeWidth={2.5} />
      </button>
    </div>

    <div class="cp-list">
      {#if loading && members.length === 0}
        <div class="cp-loading"><div class="cp-spinner"></div></div>
      {:else}
        {#each members as m, idx (m.id)}
          {@const selected = m.id === currentId}
          <button class="cp-item" class:selected aria-pressed={selected} style="--i: {Math.min(idx, 8)}" onclick={() => onselect(m.id)}>
            <span class="cp-avatar" aria-hidden="true">{initial(m.display_name)}</span>
            <span class="cp-name">
              {m.display_name}
              {#if m.id === meId}<span class="cp-me">(moi)</span>{/if}
            </span>
            {#if selected}<span class="cp-check" aria-hidden="true"><Icon name="check" size={18} strokeWidth={2.5} /></span>{/if}
          </button>
        {/each}
        {#if members.length === 0}
          <p class="cp-empty">Aucun membre trouvé dans le foyer.</p>
        {/if}
      {/if}

      <button class="cp-item cp-nobody" class:selected={currentId === null} aria-pressed={currentId === null} onclick={() => onselect(null)}>
        <span class="cp-avatar cp-avatar-empty" aria-hidden="true"><Icon name="chef" size={16} /></span>
        <span class="cp-name">Personne</span>
        {#if currentId === null}<span class="cp-check" aria-hidden="true"><Icon name="check" size={18} strokeWidth={2.5} /></span>{/if}
      </button>
    </div>
  </div>
</div>

<style>
  /* Voile, cadre et animation : classes communes (.ui-overlay.center, .ui-dialog) */
  .cp { width: min(360px, 100%); padding: var(--sp-4) var(--sp-4) var(--sp-4); }

  .cp-head {
    display: flex;
    align-items: center;
    gap: var(--sp-3);
    padding-bottom: var(--sp-3);
  }

  .cp-head-icon {
    display: flex;
    align-items: center;
    justify-content: center;
    width: 40px;
    height: 40px;
    border: var(--line-w) solid var(--line);
    background: var(--band);
    color: var(--text-on-band);
    flex-shrink: 0;
  }

  .cp-head-text {
    flex: 1;
    min-width: 0;
  }

  h2 {
    font-size: var(--fs-lg);
    text-transform: uppercase;
    color: var(--text);
    line-height: 1.2;
  }

  .cp-sub {
    margin-top: 2px;
    font-size: 13px;
    color: var(--text-secondary);
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }

  .cp-close { align-self: flex-start; }

  .cp-list {
    display: flex;
    flex-direction: column;
    gap: var(--sp-2);
  }

  .cp-item {
    display: flex;
    align-items: center;
    gap: var(--sp-3);
    width: 100%;
    min-height: 54px;
    padding: var(--sp-2) var(--sp-3);
    border: var(--line-w) solid var(--line);
    background: var(--surface);
    color: var(--text);
    font-family: var(--font-body);
    font-size: var(--fs-base);
    font-weight: var(--fw-bold);
    text-align: left;
    cursor: pointer;
    touch-action: manipulation;
    animation: fade-up var(--dur-sheet) var(--ease-out) calc(var(--i, 0) * 45ms) backwards;
    transition: transform var(--dur-fast) var(--ease-out);
  }

  .cp-item:active {
    transform: translate(var(--press), var(--press));
    box-shadow: none;
  }

  /* Choisi : orange + ombre franche */
  .cp-item.selected {
    background: var(--accent);
    color: var(--on-accent);
    box-shadow: var(--shadow-sm);
  }

  .cp-nobody { margin-top: var(--sp-1); }

  .cp-avatar {
    display: flex;
    align-items: center;
    justify-content: center;
    width: 36px;
    height: 36px;
    border: var(--line-w) solid var(--ink);
    background: var(--highlight);
    color: var(--text);
    font-size: 16px;
    font-weight: var(--fw-bold);
    flex-shrink: 0;
  }

  .cp-item.selected .cp-avatar { background: var(--ink); color: var(--butter); border-color: var(--ink); }

  .cp-avatar-empty {
    background: transparent;
    border: var(--line-w) dashed var(--line);
    color: var(--text);
  }
  .cp-item.selected .cp-avatar-empty { background: transparent; color: var(--on-accent); border-color: var(--ink); }

  .cp-name {
    flex: 1;
    min-width: 0;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  .cp-me {
    margin-left: var(--sp-1);
    font-size: 13px;
    font-weight: var(--fw-medium);
  }
  .cp-item:not(.selected) .cp-me { color: var(--text-secondary); }

  .cp-check {
    display: flex;
    flex-shrink: 0;
  }

  .cp-empty {
    padding: var(--sp-2) var(--sp-1);
    font-size: var(--fs-sm);
    color: var(--text-secondary);
  }

  .cp-loading {
    display: flex;
    justify-content: center;
    padding: var(--sp-4);
  }

  .cp-spinner {
    width: 24px;
    height: 24px;
    border: var(--line-w) solid var(--line);
    border-top-color: var(--accent);
    animation: cp-spin 0.8s steps(4) infinite;
  }

  @keyframes cp-spin { to { transform: rotate(360deg); } }

  .cp-item:focus-visible { outline-offset: 2px; }

  @media (hover: hover) and (pointer: fine) {
    .cp-item:not(.selected):hover { background: var(--surface-hover); }
  }
</style>
