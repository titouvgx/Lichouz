<script lang="ts">
  // Fenêtre de confirmation centrée, commune à toute l'appli
  // (terminer les courses, mettre à jour la liste, supprimer…).
  import type { Snippet } from 'svelte'
  import { onMount, onDestroy } from 'svelte'

  interface Props {
    title: string
    confirmLabel: string
    cancelLabel?: string
    danger?: boolean
    busy?: boolean
    /** Bouton de confirmation grisé (ex. : saisie de confirmation incomplète). */
    confirmDisabled?: boolean
    onconfirm: () => void
    oncancel: () => void
    children?: Snippet
  }
  let {
    title, confirmLabel, cancelLabel = 'Annuler', danger = false, busy = false, confirmDisabled = false,
    onconfirm, oncancel, children,
  }: Props = $props()

  let el: HTMLDivElement | undefined = $state()
  onMount(() => {
    document.body.style.overflow = 'hidden'
    el?.focus()
  })
  onDestroy(() => {
    document.body.style.overflow = ''
  })
</script>

<svelte:window onkeydown={(e) => { if (e.key === 'Escape' && !busy) oncancel() }} />

<!-- svelte-ignore a11y_click_events_have_key_events -->
<!-- svelte-ignore a11y_no_static_element_interactions -->
<div class="ui-overlay center cd-overlay" onclick={() => { if (!busy) oncancel() }}>
  <!-- svelte-ignore a11y_click_events_have_key_events -->
  <!-- svelte-ignore a11y_no_static_element_interactions -->
  <div
    class="ui-dialog cd"
    bind:this={el}
    tabindex="-1"
    role="alertdialog"
    aria-modal="true"
    aria-labelledby="cd-title"
    onclick={(e) => e.stopPropagation()}
  >
    <h2 id="cd-title">{title}</h2>
    {#if children}<div class="cd-body">{@render children()}</div>{/if}
    <div class="cd-actions">
      <button class="btn btn-outline" onclick={oncancel} disabled={busy}>{cancelLabel}</button>
      <button class="btn cd-confirm" class:btn-primary={!danger} class:btn-danger={danger} onclick={onconfirm} disabled={busy || confirmDisabled}>
        {busy ? 'Un instant…' : confirmLabel}
      </button>
    </div>
  </div>
</div>

<style>
  /* Fenêtre de confirmation : les styles communs sont dans app.css
     (.ui-overlay, .ui-dialog, .btn…). Ici, seulement la mise en page. */
  .cd-overlay { z-index: 210; }

  h2 {
    font-size: var(--fs-xl);
    text-transform: uppercase;
    color: var(--text);
  }

  .cd-body {
    margin-top: var(--sp-2);
    font-size: 15px;
    line-height: 1.45;
    color: var(--text-secondary);
  }

  .cd-actions {
    display: flex;
    gap: var(--sp-3);
    margin-top: var(--sp-5);
  }

  .cd-actions .btn {
    flex: 1;
    width: auto;
    font-size: 15px;
    white-space: nowrap;
  }
</style>
