<script lang="ts">
  // « Événements » (#/evenements), v1.999.0 : fêtes à venir (Noël, anniversaires…)
  // de mon foyer et de la famille élargie, et création d'un nouvel événement.
  import { onMount } from 'svelte'
  import ErrorState from '../components/ErrorState.svelte'
  import Icon from '../components/Icon.svelte'
  import EventForm from '../components/EventForm.svelte'
  import { href, navigate } from '../lib/router.svelte'
  import { toast } from '../lib/toast.svelte'
  import { profileState } from '../lib/profile.svelte'
  import { createEvent, fetchEvents, type EventInput, type FamilyEvent } from '../lib/api/events'
  import { countdownLabel, formatEventDate, isUpcoming, templateOf } from '../lib/evenements'

  let events = $state<FamilyEvent[]>([])
  let loading = $state(true)
  let error = $state<string | null>(null)
  let creating = $state(false)
  let saving = $state(false)
  let showPast = $state(false)

  const upcoming = $derived(events.filter((e) => isUpcoming(e.starts_on)))
  const past = $derived(events.filter((e) => !isUpcoming(e.starts_on)).reverse())

  onMount(async () => {
    try {
      events = await fetchEvents()
      // Arrivée par #/evenements/nouveau : formulaire ouvert directement
      if (window.location.hash.endsWith('/nouveau')) creating = true
    } catch (e: any) {
      error = e?.message ?? 'Chargement impossible'
    } finally {
      loading = false
    }
  })

  async function create(input: EventInput, poles: string[]) {
    const fid = profileState.profile?.family_id
    if (!fid) return
    saving = true
    try {
      const id = await createEvent(fid, input, poles)
      toast.success('Événement créé')
      navigate('evenement', id)
    } catch (e: any) {
      toast.error(e?.message ?? 'Création impossible')
    } finally {
      saving = false
    }
  }
</script>

{#snippet card(ev: FamilyEvent)}
  {@const t = templateOf(ev.kind)}
  <a class="ev card" href={href('evenement', ev.id)}>
    <span class="ev-icon" aria-hidden="true"><Icon name={t.icon} size={22} /></span>
    <span class="ev-text">
      <span class="ev-title">{ev.title}</span>
      <span class="ev-meta">
        {formatEventDate(ev.starts_on)}{ev.location ? ` · ${ev.location}` : ''}
      </span>
      <span class="ev-when">{countdownLabel(ev.starts_on)}{ev.scope === 'famille' ? ' · toute la famille' : ''}</span>
    </span>
    <Icon name="chevron-right" size={18} />
  </a>
{/snippet}

<div class="page">
  <a href={href('accueil')} class="back-link"><Icon name="arrow-left" size={18} /> Accueil</a>
  <header class="head">
    <h1>Événements</h1>
    <p class="head-sub">Noël, anniversaires, fêtes : qui vient, qui fait quoi.</p>
  </header>

  {#if creating}
    <section class="card form-card" aria-label="Nouvel événement">
      <h2 class="band-title">Nouvel événement</h2>
      <EventForm {saving} onsubmit={create} oncancel={() => (creating = false)} />
    </section>
  {:else}
    <button class="btn btn-primary new-btn" onclick={() => (creating = true)}>
      <Icon name="plus" size={18} /> Créer un événement
    </button>
  {/if}

  {#if loading}
    <p class="state" aria-busy="true">Chargement…</p>
  {:else if error}
    <ErrorState {error} message={error} />
  {:else}
    {#if upcoming.length === 0 && !creating}
      <div class="card empty">
        <p><strong>Aucun événement à venir.</strong></p>
        <p class="hint">Crée la fête de Noël : chacun dira s’il vient et ce qu’il apporte.</p>
      </div>
    {/if}
    {#if upcoming.length}
      <section aria-label="À venir" class="list">
        {#each upcoming as ev (ev.id)}{@render card(ev)}{/each}
      </section>
    {/if}
    {#if past.length}
      <button class="past-toggle" aria-expanded={showPast} onclick={() => (showPast = !showPast)}>
        Passés ({past.length}) <Icon name="chevron-down" size={16} />
      </button>
      {#if showPast}
        <section aria-label="Passés" class="list past">
          {#each past as ev (ev.id)}{@render card(ev)}{/each}
        </section>
      {/if}
    {/if}
  {/if}
</div>

<style>
  .page {
    padding: var(--gutter);
    padding-top: 0;
    max-width: 560px;
    margin: 0 auto;
    padding-bottom: calc(84px + env(safe-area-inset-bottom, 0px));
    display: flex;
    flex-direction: column;
    gap: var(--sp-4);
  }
  .back-link {
    display: inline-flex;
    align-items: center;
    align-self: flex-start;
    gap: 6px;
    min-height: 44px;
    margin-top: calc(8px + env(safe-area-inset-top, 0px));
    color: var(--text);
    font-weight: var(--fw-bold);
    text-decoration: underline;
    text-decoration-thickness: 2px;
    text-underline-offset: 3px;
  }
  .head h1 { padding-right: 56px; }
  .head-sub { margin-top: var(--sp-1); font-size: 15px; font-weight: var(--fw-medium); color: var(--text-secondary); }
  .new-btn { min-height: 52px; gap: 8px; }
  .form-card { padding: var(--sp-4); }
  .band-title {
    margin: calc(var(--sp-4) * -1) calc(var(--sp-4) * -1) var(--sp-2);
    padding: 6px var(--sp-3);
    background: var(--band);
    color: var(--text-on-band);
    font-size: 13px;
    text-transform: uppercase;
    letter-spacing: var(--tracking-caps);
  }
  .list { display: flex; flex-direction: column; gap: var(--sp-3); }
  .ev {
    display: flex;
    align-items: center;
    gap: var(--sp-3);
    padding: var(--sp-3) var(--sp-4);
    color: var(--text);
    touch-action: manipulation;
    transition: transform var(--dur-fast) var(--ease-out);
  }
  .ev:active { transform: translate(2px, 2px); }
  .ev-icon { flex: none; width: 44px; height: 44px; display: grid; place-items: center; background: var(--band); color: var(--text-on-band); }
  .ev-text { flex: 1; min-width: 0; display: flex; flex-direction: column; gap: 2px; }
  .ev-title { font-size: var(--fs-lg); font-weight: var(--fw-bold); }
  .ev-meta { font-size: var(--fs-sm); color: var(--text-secondary); }
  .ev-when { font-size: var(--fs-xs); font-weight: var(--fw-bold); text-transform: uppercase; letter-spacing: var(--tracking-caps); }
  .past .ev { opacity: 0.75; }
  .past-toggle {
    align-self: flex-start;
    display: inline-flex;
    align-items: center;
    gap: 4px;
    min-height: 44px;
    border: 0;
    background: transparent;
    color: var(--text);
    font: var(--fw-bold) 15px var(--font-body);
    cursor: pointer;
  }
  .empty { padding: var(--sp-5) var(--sp-4); text-align: center; display: flex; flex-direction: column; gap: 6px; }
  .hint { font-size: var(--fs-sm); color: var(--text-secondary); }
  .state { color: var(--text-secondary); }
</style>
