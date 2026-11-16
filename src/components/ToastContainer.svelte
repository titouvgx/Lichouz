<script lang="ts">
  import { toast } from '../lib/toast.svelte'
</script>

{#if toast.items.length > 0}
  <div class="toast-container" aria-live="polite">
    {#each toast.items as t (t.id)}
      <div class="toast toast-{t.type}" role="status">
        <span class="toast-icon">
          {#if t.type === 'success'}✓{:else if t.type === 'error'}!{:else}i{/if}
        </span>
        <span class="toast-msg">{t.message}</span>
      </div>
    {/each}
  </div>
{/if}

<style>
  .toast-container {
    position: fixed;
    top: calc(12px + env(safe-area-inset-top, 0px));
    left: 50%;
    transform: translateX(-50%);
    z-index: 220; /* au-dessus des fenêtres (200) et de la confirmation (210) */
    display: flex;
    flex-direction: column;
    gap: 8px;
    width: calc(100% - 32px);
    max-width: 400px;
    pointer-events: none;
  }

  /* Notification : bloc carré, bordure noire, ombre franche.
     Elle « tombe » d'en haut avec un petit claquement. */
  .toast {
    display: flex;
    align-items: stretch;
    min-height: 48px;
    background: var(--surface);
    border: var(--line-w) solid var(--line);
    box-shadow: var(--shadow-md);
    font-size: var(--fs-sm);
    font-weight: var(--fw-medium);
    font-family: var(--font-body);
    animation: snap-in var(--dur-sheet) var(--ease-out);
    pointer-events: auto;
  }

  .toast-icon {
    flex: none;
    width: 40px;
    display: flex;
    align-items: center;
    justify-content: center;
    border-right: var(--line-w) solid var(--line);
    font-size: var(--fs-base);
    font-weight: var(--fw-bold);
  }

  .toast-success .toast-icon { background: var(--success-bg); color: var(--success); }
  .toast-error .toast-icon { background: var(--error); color: var(--on-error); }
  .toast-info .toast-icon { background: var(--accent); color: var(--on-accent); }
  .toast-error { box-shadow: 4px 4px 0 var(--error); }

  .toast-msg {
    color: var(--text);
    flex: 1;
    min-width: 0;
    padding: 12px 14px;
    align-self: center;
  }
</style>
