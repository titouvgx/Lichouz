<script lang="ts">
  // Outils de la semaine (v1.99.0, lot V1-4) : recopier la semaine d'avant,
  // enregistrer la semaine comme semaine type, appliquer une semaine type.
  // Tout se fait côté base en une transaction (migration 26), avec les droits
  // de la personne : impossible de toucher au planning d'un autre foyer.
  import { onMount } from 'svelte'
  import Icon from './Icon.svelte'
  import ConfirmDialog from './ConfirmDialog.svelte'
  import {
    applyWeekTemplate, copyWeek, countSlots, deleteWeekTemplate, fetchWeekTemplates,
    findPlan, saveWeekTemplate, shiftWeek, toISODate,
  } from '../lib/api/meals'
  import { toast } from '../lib/toast.svelte'
  import type { WeekTemplate } from '../lib/types'

  interface Props {
    familyId: string
    planId: string
    weekMonday: Date
    /** La semaine affichée a déjà des repas (on propose alors « remplacer ») */
    weekHasMeals: boolean
    onchanged: () => Promise<void> | void
    onclose: () => void
  }
  let { familyId, planId, weekMonday, weekHasMeals, onchanged, onclose }: Props = $props()

  let dialogEl: HTMLDivElement | undefined = $state()
  let templates: WeekTemplate[] = $state([])
  let loading = $state(true)
  let busy = $state(false)
  let replace = $state(false)
  let name = $state('')
  let prevPlanId: string | null = $state(null)
  let prevCount = $state(0)
  let toDelete: WeekTemplate | null = $state(null)

  const NAME_MAX = 40

  onMount(() => {
    dialogEl?.focus()
    void load()
  })

  async function load() {
    loading = true
    try {
      const prev = await findPlan(familyId, toISODate(shiftWeek(weekMonday, -1)))
      prevPlanId = prev?.id ?? null
      prevCount = prev ? await countSlots(prev.id) : 0
      templates = await fetchWeekTemplates(familyId)
    } catch (e: any) {
      toast.error(friendly(e))
    } finally {
      loading = false
    }
  }

  function friendly(e: any): string {
    const msg = `${e?.message ?? ''}`
    if (/week_templates|copy_week_slots|save_week_template|apply_week_template|schema cache|does not exist/i.test(msg)) {
      return 'Cette fonction n’est pas encore activée sur la base.'
    }
    return msg || 'Une erreur est survenue. Réessaie.'
  }

  const plats = (n: number) => `${n} plat${n > 1 ? 's' : ''}`

  async function copyPrevious() {
    if (!prevPlanId || busy) return
    busy = true
    try {
      const n = await copyWeek(prevPlanId, planId, replace)
      await onchanged()
      toast.success(n === 0 ? 'Rien à ajouter : les cases étaient déjà prises.' : `Semaine d’avant recopiée : ${plats(n)}`)
      onclose()
    } catch (e: any) {
      toast.error(friendly(e))
    } finally {
      busy = false
    }
  }

  async function apply(t: WeekTemplate) {
    if (busy) return
    busy = true
    try {
      const n = await applyWeekTemplate(t.id, planId, replace)
      await onchanged()
      toast.success(n === 0 ? 'Rien à ajouter : les cases étaient déjà prises.' : `« ${t.name} » appliquée : ${plats(n)}`)
      onclose()
    } catch (e: any) {
      toast.error(friendly(e))
    } finally {
      busy = false
    }
  }

  async function save() {
    const n = name.trim()
    if (!n || busy) return
    busy = true
    try {
      await saveWeekTemplate(planId, n)
      toast.success(`Semaine type « ${n} » enregistrée`)
      name = ''
      templates = await fetchWeekTemplates(familyId)
    } catch (e: any) {
      toast.error(/54000|20 semaines/.test(`${e?.code} ${e?.message}`) ? 'Pas plus de 20 semaines types : supprimes-en une.' : friendly(e))
    } finally {
      busy = false
    }
  }

  async function confirmDelete() {
    const t = toDelete
    if (!t) return
    busy = true
    try {
      await deleteWeekTemplate(t.id)
      templates = templates.filter((x) => x.id !== t.id)
      toast.success(`« ${t.name} » supprimée`)
    } catch (e: any) {
      toast.error(friendly(e))
    } finally {
      busy = false
      toDelete = null
    }
  }

  function onKey(e: KeyboardEvent) {
    if (e.key === 'Escape' && !toDelete && !busy) onclose()
  }
</script>

<svelte:window onkeydown={onKey} />

<!-- svelte-ignore a11y_click_events_have_key_events -->
<!-- svelte-ignore a11y_no_static_element_interactions -->
<div class="ui-overlay" onclick={() => { if (!busy) onclose() }}>
  <!-- svelte-ignore a11y_click_events_have_key_events -->
  <!-- svelte-ignore a11y_no_static_element_interactions -->
  <div
    class="ui-sheet tools"
    bind:this={dialogEl}
    tabindex="-1"
    role="dialog"
    aria-modal="true"
    aria-labelledby="wt-title"
    onclick={(e) => e.stopPropagation()}
  >
    <div class="ui-head">
      <h2 id="wt-title">Remplir la semaine</h2>
      <button class="btn btn-icon" onclick={onclose} aria-label="Fermer"><Icon name="x" size={20} /></button>
    </div>

    {#if loading}
      <p class="muted" aria-busy="true">Chargement…</p>
    {:else}
      {#if weekHasMeals}
        <label class="replace">
          <input type="checkbox" class="check" bind:checked={replace} />
          <span>
            <strong>Remplacer ce qui est déjà prévu</strong>
            <small>Sinon, les repas déjà prévus sont gardés et seules les cases vides sont remplies.</small>
          </span>
        </label>
      {/if}

      <section class="block" aria-labelledby="wt-copy">
        <h3 id="wt-copy" class="band">Recopier</h3>
        <div class="block-body">
          {#if prevCount > 0}
            <p>La semaine d’avant compte {plats(prevCount)}. Les restes prévus suivent leur repas.</p>
            <button class="btn btn-primary long" onclick={copyPrevious} disabled={busy}>
              <Icon name="copy" size={18} /> Recopier la semaine d’avant
            </button>
          {:else}
            <p class="muted">La semaine d’avant est vide : rien à recopier.</p>
          {/if}
        </div>
      </section>

      <section class="block" aria-labelledby="wt-tpl">
        <h3 id="wt-tpl" class="band">Semaines types <span>{templates.length}/20</span></h3>
        <div class="block-body">
          {#if templates.length === 0}
            <p class="muted">Aucune semaine type. Prépare une semaine qui revient souvent, puis enregistre-la ci-dessous.</p>
          {:else}
            <ul class="tpl-list">
              {#each templates as t (t.id)}
                <li class="tpl">
                  <span class="tpl-info">
                    <strong>{t.name}</strong>
                    <small>{plats(t.slot_count ?? 0)}</small>
                  </span>
                  <button class="btn btn-sm" onclick={() => apply(t)} disabled={busy}>Appliquer</button>
                  <button class="btn btn-icon btn-sm tpl-del" onclick={() => (toDelete = t)} disabled={busy} aria-label="Supprimer la semaine type {t.name}">
                    <Icon name="trash" size={16} />
                  </button>
                </li>
              {/each}
            </ul>
          {/if}

          <form class="save" onsubmit={(e) => { e.preventDefault(); void save() }}>
            <label class="label" for="wt-name">Enregistrer cette semaine comme semaine type</label>
            <div class="save-row">
              <input
                id="wt-name"
                class="input"
                placeholder="Ex : Semaine d’école"
                maxlength={NAME_MAX}
                bind:value={name}
                disabled={!weekHasMeals || busy}
              />
              <button class="btn btn-outline" type="submit" disabled={!weekHasMeals || busy || !name.trim()}>Enregistrer</button>
            </div>
            {#if !weekHasMeals}<small class="muted">Ajoute d’abord des repas à cette semaine.</small>{/if}
            {#if templates.some((t) => t.name === name.trim())}<small class="muted">Une semaine type porte déjà ce nom : elle sera remplacée.</small>{/if}
          </form>
        </div>
      </section>
    {/if}
  </div>
</div>

{#if toDelete}
  <ConfirmDialog
    title="Supprimer « {toDelete.name} » ?"
    confirmLabel="Supprimer"
    danger
    busy={busy}
    onconfirm={confirmDelete}
    oncancel={() => (toDelete = null)}
  >
    La semaine type est supprimée pour tout le foyer. Les semaines déjà remplies ne changent pas.
  </ConfirmDialog>
{/if}

<style>
  .tools { display: flex; flex-direction: column; gap: var(--sp-4); }
  .ui-head { margin-bottom: 0; }

  .muted { color: var(--text-secondary); font-size: var(--fs-sm); }

  .replace {
    display: flex;
    align-items: flex-start;
    gap: var(--sp-3);
    padding: var(--sp-3);
    border: var(--line-w) solid var(--line);
    background: var(--highlight);
    cursor: pointer;
  }
  .replace span { display: flex; flex-direction: column; gap: 2px; }
  .replace small { font-size: 13px; color: var(--text-secondary); }

  .block { border: var(--line-w) solid var(--line); background: var(--surface); box-shadow: var(--shadow-sm); }
  .block .band { margin: 0; }
  .block-body { display: flex; flex-direction: column; gap: var(--sp-3); padding: var(--sp-3); }
  .block-body p { font-size: 15px; }

  .tpl-list { list-style: none; margin: 0; padding: 0; border: var(--line-w) solid var(--line); }
  .tpl {
    display: flex;
    align-items: center;
    gap: var(--sp-2);
    min-height: 56px;
    padding: 6px 6px 6px var(--sp-3);
  }
  .tpl + .tpl { border-top: var(--line-thin) solid var(--line); }
  .tpl-info { flex: 1; min-width: 0; display: flex; flex-direction: column; }
  .tpl-info strong { overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
  .tpl-info small { font-size: 13px; color: var(--text-secondary); }
  .tpl-del { color: var(--error); }

  .save { display: flex; flex-direction: column; gap: var(--sp-1); }
  .save-row { display: flex; gap: var(--sp-2); }
  .save-row .input { flex: 1; min-width: 0; }
  .save-row .btn { flex: none; }
</style>
