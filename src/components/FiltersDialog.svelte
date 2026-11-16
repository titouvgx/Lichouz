<script lang="ts">
  // Filtres de l'écran Recettes (v1.8.0) : régime, budget, origine, thèmes.
  // Les filtres s'appliquent tout de suite (la liste derrière se met à jour) ;
  // « Voir N recettes » ferme simplement la fenêtre.
  import { onMount } from 'svelte'
  import Icon from './Icon.svelte'
  import {
    BUDGETS, NO_FILTERS, ORIGINES, REGIMES, THEMES, cleanKeys, countFilters, type TagFilters,
  } from '../lib/etiquettes'

  interface Props {
    filters: TagFilters
    /** Nombre de recettes avec ces filtres (recherche et catégorie comprises) */
    resultCount: number
    /** Origines présentes dans les recettes (on ne propose pas les autres) */
    usedOrigins: Set<string>
    onclose: () => void
  }
  let { filters = $bindable(), resultCount, usedOrigins, onclose }: Props = $props()

  let dialogEl: HTMLDivElement | undefined = $state()
  onMount(() => dialogEl?.focus())

  function onKey(e: KeyboardEvent) {
    if (e.key === 'Escape') onclose()
  }

  const toggle = (list: string[], key: string) =>
    list.includes(key) ? list.filter((k) => k !== key) : [...list, key]

  const origins = $derived(ORIGINES.filter((o) => usedOrigins.has(o.key) || filters.origins.includes(o.key)))
  const active = $derived(countFilters(filters))
</script>

<svelte:window onkeydown={onKey} />

<!-- svelte-ignore a11y_click_events_have_key_events -->
<!-- svelte-ignore a11y_no_static_element_interactions -->
<div class="dlg-overlay" onclick={onclose}>
  <!-- svelte-ignore a11y_click_events_have_key_events -->
  <!-- svelte-ignore a11y_no_static_element_interactions -->
  <div
    class="dlg"
    bind:this={dialogEl}
    tabindex="-1"
    role="dialog"
    aria-modal="true"
    aria-labelledby="flt-title"
    onclick={(e) => e.stopPropagation()}
  >
    <header class="dlg-header">
      <h2 id="flt-title">Filtres</h2>
      <button class="dlg-close" onclick={onclose} aria-label="Fermer"><Icon name="x" /></button>
    </header>

    <div class="dlg-body">
      <section role="group" aria-labelledby="flt-diet">
        <h3 id="flt-diet">Régime <span class="hint">tous ceux choisis</span></h3>
        <div class="opts">
          {#each REGIMES as r (r.key)}
            <button
              type="button"
              class="opt"
              class:on={filters.diets.includes(r.key)}
              aria-pressed={filters.diets.includes(r.key)}
              onclick={() => (filters = { ...filters, diets: cleanKeys(toggle(filters.diets, r.key), REGIMES) })}
            >{r.label}</button>
          {/each}
        </div>
      </section>

      <section role="group" aria-labelledby="flt-budget">
        <h3 id="flt-budget">Budget <span class="hint">au plus</span></h3>
        <div class="opts">
          {#each BUDGETS as b (b.value)}
            <button
              type="button"
              class="opt"
              class:on={filters.budgetMax === b.value}
              aria-pressed={filters.budgetMax === b.value}
              onclick={() => (filters = { ...filters, budgetMax: filters.budgetMax === b.value ? null : b.value })}
            >{b.label} <span class="opt-sub">{b.long}</span></button>
          {/each}
        </div>
      </section>

      <section role="group" aria-labelledby="flt-theme">
        <h3 id="flt-theme">Thèmes <span class="hint">au moins un</span></h3>
        <div class="opts">
          {#each THEMES as t (t.key)}
            <button
              type="button"
              class="opt"
              class:on={filters.themes.includes(t.key)}
              aria-pressed={filters.themes.includes(t.key)}
              onclick={() => (filters = { ...filters, themes: cleanKeys(toggle(filters.themes, t.key), THEMES) })}
            >{t.label}</button>
          {/each}
        </div>
      </section>

      {#if origins.length > 0}
        <section role="group" aria-labelledby="flt-origin">
          <h3 id="flt-origin">Origine <span class="hint">une parmi</span></h3>
          {#each ['France', 'Monde'] as groupe (groupe)}
            {@const list = origins.filter((o) => o.groupe === groupe)}
            {#if list.length > 0}
              <p class="group">{groupe}</p>
              <div class="opts">
                {#each list as o (o.key)}
                  <button
                    type="button"
                    class="opt"
                    class:on={filters.origins.includes(o.key)}
                    aria-pressed={filters.origins.includes(o.key)}
                    onclick={() => (filters = { ...filters, origins: cleanKeys(toggle(filters.origins, o.key), ORIGINES) })}
                  >{o.label}</button>
                {/each}
              </div>
            {/if}
          {/each}
        </section>
      {/if}
    </div>

    <footer class="dlg-foot">
      <button class="btn btn-outline" disabled={active === 0} onclick={() => (filters = { ...NO_FILTERS })}>Effacer</button>
      <button class="btn btn-primary" onclick={onclose} aria-live="polite">
        {resultCount === 0 ? 'Aucune recette' : `Voir ${resultCount} recette${resultCount > 1 ? 's' : ''}`}
      </button>
    </footer>
  </div>
</div>

<style>
  .dlg-overlay {
    position: fixed;
    inset: 0;
    z-index: 200; /* au-dessus de la barre d'onglets (100) */
    display: flex;
    align-items: flex-end;
    justify-content: center;
    padding-top: max(16px, env(safe-area-inset-top, 0px));
    background: rgba(2, 8, 22, 0.66);
    animation: fade 0.2s ease-out;
  }

  .dlg {
    width: min(520px, 100%);
    max-height: 88svh;
    display: flex;
    flex-direction: column;
    background: var(--bg);
    border: 1px solid var(--border-strong);
    border-bottom: none;
    border-radius: 18px 18px 0 0;
    box-shadow: 0 -12px 40px rgba(0, 0, 0, 0.4);
    overflow: hidden;
    animation: up 0.25s cubic-bezier(0.2, 0.9, 0.3, 1);
    outline: none;
  }

  @media (min-width: 640px) {
    .dlg-overlay { align-items: center; padding: 16px; }
    .dlg { border-radius: 18px; border-bottom: 1px solid var(--border-strong); }
  }

  @keyframes fade { from { opacity: 0; } }
  @keyframes up   { from { opacity: 0; transform: translateY(24px); } }

  @media (prefers-reduced-motion: reduce) {
    .dlg-overlay, .dlg { animation: none; }
  }

  .dlg-header {
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: 12px 10px 4px 18px;
  }
  .dlg-header h2 { font-size: 21px; color: var(--text); }

  .dlg-close {
    width: 44px;
    height: 44px;
    border-radius: 50%;
    border: none;
    background: transparent;
    color: var(--text);
    display: flex;
    align-items: center;
    justify-content: center;
    cursor: pointer;
    touch-action: manipulation;
  }

  .dlg-body {
    overflow-y: auto;
    overscroll-behavior: contain;
    padding: 4px 18px 12px;
  }

  section + section { margin-top: 18px; }

  h3 {
    font-size: 13px;
    font-weight: 700;
    letter-spacing: 0.04em;
    text-transform: uppercase;
    color: var(--text-secondary);
    margin: 0 0 8px;
  }
  .hint { text-transform: none; letter-spacing: 0; font-weight: 500; margin-left: 4px; }
  .group { font-size: 13px; color: var(--text-secondary); margin: 10px 0 6px; }

  .opts { display: flex; flex-wrap: wrap; gap: 6px; }

  .opt {
    min-height: 44px;
    padding: 0 14px;
    border-radius: 8px;
    border: 1px solid var(--border-strong);
    background: transparent;
    color: var(--text);
    font: 600 14px/1.2 var(--font-body);
    cursor: pointer;
    touch-action: manipulation;
  }
  .opt.on {
    background: var(--primary);
    border-color: var(--primary);
    color: var(--on-primary);
  }
  .opt:focus-visible { outline: 2px solid var(--primary); outline-offset: 2px; }
  .opt-sub { font-weight: 500; opacity: 0.8; margin-left: 2px; }

  .dlg-foot {
    display: flex;
    gap: 10px;
    padding: 12px 18px;
    padding-bottom: max(12px, env(safe-area-inset-bottom, 0px));
    border-top: 1px solid var(--border);
  }
  .dlg-foot .btn { min-height: 48px; }
  .dlg-foot .btn-primary { flex: 1; }
</style>
