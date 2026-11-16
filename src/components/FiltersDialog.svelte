<script lang="ts">
  // Filtres de l'écran Recettes (v1.8.0) : régime, budget, origine, thèmes ; temps (v1.99.0).
  // Les filtres s'appliquent tout de suite (la liste derrière se met à jour) ;
  // « Voir N recettes » ferme simplement la fenêtre.
  import { onMount } from 'svelte'
  import Icon from './Icon.svelte'
  import {
    BUDGETS, NO_FILTERS, ORIGINES, REGIMES, TEMPS, THEMES, cleanKeys, countFilters, type TagFilters,
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
<div class="ui-overlay dlg-overlay" onclick={onclose}>
  <!-- svelte-ignore a11y_click_events_have_key_events -->
  <!-- svelte-ignore a11y_no_static_element_interactions -->
  <div
    class="ui-sheet dlg"
    bind:this={dialogEl}
    tabindex="-1"
    role="dialog"
    aria-modal="true"
    aria-labelledby="flt-title"
    onclick={(e) => e.stopPropagation()}
  >
    <header class="dlg-header">
      <h2 id="flt-title">Filtres</h2>
      <button class="btn btn-icon dlg-close" onclick={onclose} aria-label="Fermer"><Icon name="x" size={20} /></button>
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

      <section role="group" aria-labelledby="flt-time">
        <h3 id="flt-time">Temps de préparation <span class="hint">au plus</span></h3>
        <div class="opts">
          {#each TEMPS as t (t.value)}
            <button
              type="button"
              class="opt"
              class:on={filters.timeMax === t.value}
              aria-pressed={filters.timeMax === t.value}
              onclick={() => (filters = { ...filters, timeMax: filters.timeMax === t.value ? null : t.value })}
            >{t.label}</button>
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
  /* Fenêtre qui monte du bas : voile, cadre et animation communs dans app.css
     (.ui-overlay, .ui-sheet). Ici : en-tête fixe, contenu qui défile, pied fixe. */
  .dlg-overlay { padding-top: max(16px, env(safe-area-inset-top, 0px)); }

  .dlg {
    display: flex;
    flex-direction: column;
    overflow: hidden;
    padding: 0;
  }

  @media (min-width: 640px) {
    .dlg-overlay { align-items: center; padding: var(--sp-4); }
    .dlg { border-bottom: var(--line-w) solid var(--line); box-shadow: var(--shadow-lg); }
  }

  .dlg-header {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: var(--sp-3);
    padding: 14px var(--gutter) 10px;
  }
  .dlg-header h2 { font-size: var(--fs-2xl); text-transform: uppercase; color: var(--text); }

  .dlg-body {
    overflow-y: auto;
    overscroll-behavior: contain;
    padding: 4px var(--gutter) var(--sp-4);
  }

  section + section { margin-top: 20px; }

  /* Titre de rubrique : bandeau noir, comme les rayons de la liste de courses */
  h3 {
    display: flex;
    align-items: baseline;
    gap: 6px;
    margin: 0 0 10px;
    padding: 4px 8px;
    background: var(--band);
    color: var(--text-on-band);
    font-size: 13px;
    font-weight: var(--fw-bold);
    letter-spacing: var(--tracking-caps);
    text-transform: uppercase;
  }
  .hint { text-transform: none; letter-spacing: 0; font-weight: var(--fw-regular); }
  .group {
    font-size: 13px;
    font-weight: var(--fw-bold);
    color: var(--text-secondary);
    margin: 12px 0 6px;
  }

  .opts { display: flex; flex-wrap: wrap; gap: var(--sp-2); }

  .opt {
    min-height: 44px;
    padding: 0 12px;
    border: var(--line-w) solid var(--line);
    background: var(--surface);
    color: var(--text);
    font: 600 14px/1.2 var(--font-body);
    cursor: pointer;
    touch-action: manipulation;
    transition: transform var(--dur-fast) var(--ease-out);
  }
  .opt:active { transform: translate(2px, 2px); }
  /* Choisi : orange, ombre franche (il « ressort ») */
  .opt.on {
    background: var(--accent);
    color: var(--on-accent);
    font-weight: var(--fw-bold);
    box-shadow: var(--shadow-sm);
  }
  .opt-sub { font-weight: var(--fw-regular); margin-left: 2px; }

  @media (hover: hover) and (pointer: fine) {
    .opt:not(.on):hover { background: var(--surface-hover); }
  }

  .dlg-foot {
    display: flex;
    gap: var(--sp-3);
    padding: 12px var(--gutter) 14px;
    padding-bottom: max(14px, env(safe-area-inset-bottom, 0px));
    border-top: var(--line-w) solid var(--line);
  }
  .dlg-foot .btn-outline { flex: none; }
  .dlg-foot .btn-primary { flex: 1; width: auto; }
</style>
