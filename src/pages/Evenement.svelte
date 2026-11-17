<script lang="ts">
  // Page d'un événement (#/evenement/<id>), v1.999.0 : infos, « je viens ? »,
  // « qui fait quoi », playlist. Page « éphémère » : l'événement reste dans
  // « À venir » jusqu'à 3 jours après, puis passe dans « Passés ».
  import Icon from '../components/Icon.svelte'
  import EventForm from '../components/EventForm.svelte'
  import { href, navigate, router } from '../lib/router.svelte'
  import { toast } from '../lib/toast.svelte'
  import { auth } from '../lib/auth.svelte'
  import { profileState } from '../lib/profile.svelte'
  import {
    addTask, deleteEvent, deleteTask, fetchEvent, setRsvp, setVolunteer, updateEvent,
    type EventDetail, type EventInput,
  } from '../lib/api/events'
  import { LIMITS, RSVP_LABELS, countRsvps, countdownLabel, formatEventDate, type RsvpAnswer } from '../lib/evenements'

  let detail = $state<EventDetail | null>(null)
  let loading = $state(true)
  let error = $state<string | null>(null)
  let editing = $state(false)
  let saving = $state(false)
  let busy = $state<string | null>(null) // id de l'élément en cours d'envoi
  let newTask = $state('')
  let confirmDelete = $state(false)

  const me = $derived(auth.user?.id ?? null)
  const ev = $derived(detail?.event ?? null)
  const canEdit = $derived(
    !!ev && !!me && ev.family_id === profileState.profile?.family_id
      && (ev.created_by === me || profileState.profile?.role === 'admin'),
  )
  const myAnswer = $derived(detail?.rsvps.find((r) => r.profile_id === me)?.answer ?? null)
  const counts = $derived(countRsvps(detail?.rsvps ?? []))
  const nameOf = (id: string) => detail?.names.get(id) ?? (id === me ? 'Moi' : 'Quelqu’un')
  const byAnswer = (a: RsvpAnswer) => (detail?.rsvps ?? []).filter((r) => r.answer === a).map((r) => nameOf(r.profile_id))

  async function load(id: string) {
    loading = true
    error = null
    try {
      detail = await fetchEvent(id)
      if (!detail) error = 'Événement introuvable (supprimé, ou réservé à un autre foyer).'
    } catch (e: any) {
      error = e?.message ?? 'Chargement impossible'
    } finally {
      loading = false
    }
  }

  $effect(() => {
    const id = router.recipeId
    if (id) void load(id)
  })

  async function answer(a: RsvpAnswer) {
    if (!ev || !me || busy) return
    busy = 'rsvp'
    try {
      await setRsvp(ev.id, me, a)
      await load(ev.id)
    } catch (e: any) {
      toast.error(e?.message ?? 'Réponse impossible')
    } finally {
      busy = null
    }
  }

  async function toggle(taskId: string, on: boolean) {
    if (!ev || busy) return
    busy = taskId
    try {
      await setVolunteer(taskId, on)
      await load(ev.id)
    } catch (e: any) {
      toast.error(e?.message ?? 'Action impossible')
    } finally {
      busy = null
    }
  }

  async function add() {
    const label = newTask.trim().slice(0, LIMITS.task)
    if (!ev || !label || busy) return
    busy = 'add'
    try {
      await addTask(ev.id, label, (detail?.tasks.length ?? 0) + 1)
      newTask = ''
      await load(ev.id)
    } catch (e: any) {
      toast.error(e?.message ?? 'Ajout impossible')
    } finally {
      busy = null
    }
  }

  async function removeTask(id: string) {
    if (!ev || busy) return
    busy = id
    try {
      await deleteTask(id)
      await load(ev.id)
    } catch (e: any) {
      toast.error(e?.message ?? 'Suppression impossible')
    } finally {
      busy = null
    }
  }

  async function save(input: EventInput) {
    if (!ev) return
    saving = true
    try {
      await updateEvent(ev.id, input)
      editing = false
      toast.success('Événement mis à jour')
      await load(ev.id)
    } catch (e: any) {
      toast.error(e?.message ?? 'Enregistrement impossible')
    } finally {
      saving = false
    }
  }

  async function remove() {
    if (!ev) return
    try {
      await deleteEvent(ev.id)
      toast.success('Événement supprimé')
      navigate('evenements')
    } catch (e: any) {
      toast.error(e?.message ?? 'Suppression impossible')
    }
  }
</script>

<div class="page">
  <a href={href('evenements')} class="back-link"><Icon name="arrow-left" size={18} /> Événements</a>

  {#if loading && !detail}
    <p class="state" aria-busy="true">Chargement…</p>
  {:else if error || !ev || !detail}
    <p class="state error" role="alert">{error ?? 'Événement introuvable.'}</p>
  {:else if editing}
    <section class="card pad" aria-label="Modifier l’événement">
      <h2 class="band-title">Modifier</h2>
      <EventForm initial={ev} {saving} onsubmit={save} oncancel={() => (editing = false)} />
    </section>
  {:else}
    <header class="head">
      <span class="date-chip">{formatEventDate(ev.starts_on)}{ev.start_time ? ` · ${ev.start_time.slice(0, 5).replace(':', ' h ')}` : ''}</span>
      <h1>{ev.title}</h1>
      <p class="countdown">{countdownLabel(ev.starts_on)}</p>
    </header>

    <section class="card infos" aria-label="Infos">
      {#if ev.location}<p><strong>Chez</strong> {ev.location}</p>{/if}
      {#if ev.theme}<p><strong>Thème</strong> {ev.theme}</p>{/if}
      <p><strong>Pour</strong> {ev.scope === 'famille' ? 'toute la famille' : 'notre foyer'}</p>
      {#if ev.notes}<p class="notes">{ev.notes}</p>{/if}
      {#if ev.playlist_url}
        <a class="btn btn-outline playlist" href={ev.playlist_url} target="_blank" rel="noopener noreferrer">
          Écouter la playlist <Icon name="arrow-right" size={16} />
        </a>
      {/if}
    </section>

    <section class="card pad" aria-labelledby="rsvp-title">
      <h2 class="band-title" id="rsvp-title">Tu viens ?</h2>
      <div class="rsvp" role="group" aria-labelledby="rsvp-title">
        {#each ['oui', 'peut_etre', 'non'] as const as a (a)}
          <button class="rsvp-btn" aria-pressed={myAnswer === a} disabled={busy === 'rsvp'} onclick={() => answer(a)}>
            {RSVP_LABELS[a]}
          </button>
        {/each}
      </div>
      <dl class="who">
        <dt>Viennent ({counts.oui})</dt>
        <dd>{byAnswer('oui').join(', ') || '—'}</dd>
        {#if counts.peut_etre}<dt>Peut-être ({counts.peut_etre})</dt><dd>{byAnswer('peut_etre').join(', ')}</dd>{/if}
        {#if counts.non}<dt>Ne viennent pas ({counts.non})</dt><dd>{byAnswer('non').join(', ')}</dd>{/if}
      </dl>
    </section>

    <section class="card pad" aria-labelledby="tasks-title">
      <h2 class="band-title" id="tasks-title">Qui fait quoi ?</h2>
      {#if detail.tasks.length === 0}
        <p class="hint">Rien pour l’instant : ajoute ce qu’il faut prévoir.</p>
      {/if}
      <ul class="tasks">
        {#each detail.tasks as t (t.id)}
          {@const mine = !!me && t.volunteers.includes(me)}
          <li class="task">
            <div class="task-text">
              <span class="task-label">{t.label}</span>
              <span class="task-who">
                {t.volunteers.length ? t.volunteers.map(nameOf).join(', ') : 'Personne pour l’instant'}
              </span>
            </div>
            <button class="btn btn-sm {mine ? 'btn-outline' : 'btn-primary'}" disabled={busy === t.id} onclick={() => toggle(t.id, !mine)}>
              {mine ? 'Me retirer' : 'Je prends'}
            </button>
            {#if canEdit || t.created_by === me}
              <button class="task-x" aria-label="Supprimer « {t.label} »" disabled={busy === t.id} onclick={() => removeTask(t.id)}>
                <Icon name="trash" size={16} />
              </button>
            {/if}
          </li>
        {/each}
      </ul>
      {#if detail.tasks.length < LIMITS.tasks}
        <div class="add-row">
          <input
            class="input"
            maxlength={LIMITS.task}
            placeholder="Ajouter (ex. pain, glaçons)"
            aria-label="Ajouter une chose à prévoir"
            bind:value={newTask}
            onkeydown={(e) => { if (e.key === 'Enter') add() }}
          />
          <button class="btn btn-outline btn-icon" aria-label="Ajouter" disabled={!newTask.trim() || busy === 'add'} onclick={add}>
            <Icon name="plus" size={18} />
          </button>
        </div>
      {/if}
    </section>

    {#if canEdit}
      <div class="owner">
        <button class="btn btn-outline" onclick={() => (editing = true)}><Icon name="pencil" size={16} /> Modifier</button>
        {#if confirmDelete}
          <button class="btn btn-danger" onclick={remove}>Supprimer vraiment</button>
          <button class="btn btn-ghost" onclick={() => (confirmDelete = false)}>Non</button>
        {:else}
          <button class="btn btn-ghost" onclick={() => (confirmDelete = true)}><Icon name="trash" size={16} /> Supprimer</button>
        {/if}
      </div>
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
  .head h1 { padding-right: 56px; font-size: clamp(28px, 8vw, 40px); }
  .date-chip {
    display: inline-block;
    margin-bottom: var(--sp-2);
    padding: 3px 8px;
    background: var(--band);
    color: var(--text-on-band);
    font-size: var(--fs-xs);
    font-weight: var(--fw-bold);
    text-transform: uppercase;
    letter-spacing: var(--tracking-caps);
  }
  .countdown { margin-top: var(--sp-1); font-weight: var(--fw-bold); color: var(--text-secondary); }
  .pad, .infos { padding: var(--sp-4); }
  .infos { display: flex; flex-direction: column; gap: 6px; }
  .notes { white-space: pre-line; color: var(--text-secondary); }
  .playlist { margin-top: var(--sp-2); align-self: flex-start; gap: 8px; }
  .band-title {
    margin: calc(var(--sp-4) * -1) calc(var(--sp-4) * -1) var(--sp-3);
    padding: 6px var(--sp-3);
    background: var(--band);
    color: var(--text-on-band);
    font-size: 13px;
    text-transform: uppercase;
    letter-spacing: var(--tracking-caps);
  }
  .rsvp { display: grid; grid-template-columns: repeat(3, 1fr); gap: var(--sp-2); }
  .rsvp-btn {
    min-height: 48px;
    padding: 0 6px;
    border: var(--line-w) solid var(--line);
    background: var(--surface);
    color: var(--text);
    font: var(--fw-bold) 14px var(--font-body);
    cursor: pointer;
    touch-action: manipulation;
    transition: transform var(--dur-fast) var(--ease-out);
  }
  .rsvp-btn:active { transform: translate(2px, 2px); }
  .rsvp-btn[aria-pressed='true'] { background: var(--accent); color: var(--on-accent); box-shadow: var(--shadow-sm); }
  .who { margin: var(--sp-3) 0 0; display: grid; gap: 2px; }
  .who dt { font-size: var(--fs-xs); font-weight: var(--fw-bold); text-transform: uppercase; letter-spacing: var(--tracking-caps); margin-top: 6px; }
  .who dd { margin: 0; color: var(--text-secondary); }
  .tasks { list-style: none; margin: 0; padding: 0; }
  .task {
    display: flex;
    align-items: center;
    gap: var(--sp-2);
    padding: 10px 0;
    border-bottom: var(--line-thin) solid var(--line);
  }
  .task:last-child { border-bottom: 0; }
  .task-text { flex: 1; min-width: 0; display: flex; flex-direction: column; }
  .task-label { font-weight: var(--fw-bold); }
  .task-who { font-size: var(--fs-sm); color: var(--text-secondary); }
  .task .btn {
    flex: none;
    width: auto;
    min-height: 44px;
    padding: 0 12px;
    font-size: 14px;
    text-transform: none;
    letter-spacing: 0;
    white-space: nowrap;
  }
  .task-x {
    width: 44px;
    height: 44px;
    display: grid;
    place-items: center;
    border: 0;
    background: transparent;
    color: var(--text);
    cursor: pointer;
  }
  .add-row { display: flex; gap: var(--sp-2); margin-top: var(--sp-3); }
  .add-row .input { flex: 1; min-width: 0; }
  .hint { font-size: var(--fs-sm); color: var(--text-secondary); }
  .owner { display: flex; flex-wrap: wrap; gap: var(--sp-2); }
  .owner .btn { gap: 6px; min-height: 48px; }
  .state { color: var(--text-secondary); }
  .state.error { color: var(--error); }
</style>
