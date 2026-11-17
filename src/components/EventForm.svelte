<script lang="ts">
  // Formulaire d'un événement (création et modification), v1.999.0.
  // En création : choix du modèle (Noël, anniversaire…) qui préremplit le titre,
  // la date et les pôles « qui fait quoi » (on peut en retirer et en ajouter).
  import { untrack } from 'svelte'
  import Icon from './Icon.svelte'
  import {
    EVENT_TEMPLATES, LIMITS, cleanPlaylistUrl, defaultDate, templateOf,
    type EventKind, type EventScope,
  } from '../lib/evenements'
  import type { EventInput, FamilyEvent } from '../lib/api/events'

  interface Props {
    /** Événement à modifier ; absent = création */
    initial?: FamilyEvent | null
    saving?: boolean
    onsubmit: (input: EventInput, poles: string[]) => void
    oncancel: () => void
  }
  let { initial = null, saving = false, onsubmit, oncancel }: Props = $props()

  // Valeurs de départ lues une seule fois (le formulaire ne suit pas les changements de `initial`)
  const init = untrack(() => initial)
  const editing = !!init
  const start = templateOf(init?.kind ?? 'noel')

  let kind = $state<EventKind>(start.kind)
  let scope = $state<EventScope>(init?.scope ?? 'famille')
  let title = $state(init?.title ?? start.title)
  let startsOn = $state(init?.starts_on ?? defaultDate(start.kind))
  let startTime = $state(init?.start_time?.slice(0, 5) ?? '')
  let location = $state(init?.location ?? '')
  let theme = $state(init?.theme ?? '')
  let playlist = $state(init?.playlist_url ?? '')
  let notes = $state(init?.notes ?? '')
  let poles = $state<string[]>(editing ? [] : [...start.poles])
  let newPole = $state('')
  let error = $state<string | null>(null)

  function pickTemplate(k: EventKind) {
    const prev = templateOf(kind)
    const t = templateOf(k)
    // Titre et date suivent le modèle tant qu'on ne les a pas changés à la main
    if (!title.trim() || title === prev.title) title = t.title
    if (startsOn === defaultDate(prev.kind)) startsOn = defaultDate(t.kind)
    poles = [...t.poles]
    kind = k
  }

  function addPole() {
    const v = newPole.trim().slice(0, LIMITS.task)
    if (!v || poles.length >= LIMITS.tasks) return
    if (!poles.some((p) => p.toLowerCase() === v.toLowerCase())) poles = [...poles, v]
    newPole = ''
  }

  function submit(e: SubmitEvent) {
    e.preventDefault()
    error = null
    if (!title.trim()) { error = 'Donne un nom à l’événement.'; return }
    if (!startsOn) { error = 'Choisis une date.'; return }
    const url = cleanPlaylistUrl(playlist)
    if (url === '') { error = 'Le lien de playlist doit commencer par https://'; return }
    onsubmit(
      {
        kind,
        scope,
        title: title.trim(),
        starts_on: startsOn,
        start_time: startTime || null,
        location: location.trim() || null,
        theme: theme.trim() || null,
        playlist_url: url,
        notes: notes.trim() || null,
      },
      poles,
    )
  }
</script>

<form class="ev-form" onsubmit={submit}>
  {#if !editing}
    <fieldset class="group">
      <legend>Modèle</legend>
      <div class="opts">
        {#each EVENT_TEMPLATES as t (t.kind)}
          <button type="button" class="opt" aria-pressed={kind === t.kind} onclick={() => pickTemplate(t.kind)}>
            <Icon name={t.icon} size={16} /> {t.label}
          </button>
        {/each}
      </div>
    </fieldset>
  {/if}

  <label class="lbl" for="ev-title">Nom</label>
  <input id="ev-title" class="input" maxlength={LIMITS.title} bind:value={title} required />

  <div class="two-col">
    <div>
      <label class="lbl" for="ev-date">Date</label>
      <input id="ev-date" class="input" type="date" bind:value={startsOn} required />
    </div>
    <div>
      <label class="lbl" for="ev-time">Heure <span class="opt-txt">facultatif</span></label>
      <input id="ev-time" class="input" type="time" bind:value={startTime} />
    </div>
  </div>

  <label class="lbl" for="ev-where">Chez qui ?</label>
  <input id="ev-where" class="input" maxlength={LIMITS.location} placeholder="Chez Mamie, à Quimper" bind:value={location} />

  <label class="lbl" for="ev-theme">Thème <span class="opt-txt">facultatif</span></label>
  <input id="ev-theme" class="input" maxlength={LIMITS.theme} placeholder="Pull moche, tout en rouge…" bind:value={theme} />

  <label class="lbl" for="ev-playlist">Playlist <span class="opt-txt">lien Spotify, Deezer…</span></label>
  <input id="ev-playlist" class="input" type="url" inputmode="url" maxlength={LIMITS.playlist} placeholder="https://" bind:value={playlist} />

  <fieldset class="group">
    <legend>Qui le voit ?</legend>
    <div class="opts">
      <button type="button" class="opt" aria-pressed={scope === 'famille'} onclick={() => (scope = 'famille')}>Toute la famille</button>
      <button type="button" class="opt" aria-pressed={scope === 'foyer'} onclick={() => (scope = 'foyer')}>Mon foyer</button>
    </div>
    <p class="hint">
      {scope === 'famille'
        ? 'Tous les foyers de ta famille élargie le voient, répondent et s’inscrivent.'
        : 'Seulement les personnes de ton foyer.'}
    </p>
  </fieldset>

  {#if !editing}
    <fieldset class="group">
      <legend>Qui fait quoi ?</legend>
      <ul class="poles">
        {#each poles as p, i (p)}
          <li class="pole">
            {p}
            <button type="button" class="pole-x" aria-label="Retirer {p}" onclick={() => (poles = poles.filter((_, j) => j !== i))}>
              <Icon name="x" size={14} />
            </button>
          </li>
        {/each}
      </ul>
      <div class="add-row">
        <input
          class="input"
          maxlength={LIMITS.task}
          placeholder="Autre chose (ex. bûche, sapin)"
          aria-label="Ajouter un pôle"
          bind:value={newPole}
          onkeydown={(e) => { if (e.key === 'Enter') { e.preventDefault(); addPole() } }}
        />
        <button type="button" class="btn btn-outline btn-icon" aria-label="Ajouter" onclick={addPole} disabled={!newPole.trim()}>
          <Icon name="plus" size={18} />
        </button>
      </div>
      <p class="hint">Chacun s’inscrit ensuite sur la page de l’événement.</p>
    </fieldset>
  {/if}

  <label class="lbl" for="ev-notes">Infos <span class="opt-txt">facultatif</span></label>
  <textarea id="ev-notes" class="input" rows="3" maxlength={LIMITS.notes} placeholder="Code de la porte, parking, allergies…" bind:value={notes}></textarea>

  {#if error}<p class="field-error" role="alert">{error}</p>{/if}

  <div class="actions">
    <button type="button" class="btn btn-outline" onclick={oncancel}>Annuler</button>
    <button type="submit" class="btn btn-primary" disabled={saving}>
      {saving ? 'Enregistrement…' : editing ? 'Enregistrer' : 'Créer l’événement'}
    </button>
  </div>
</form>

<style>
  .ev-form { display: flex; flex-direction: column; gap: 6px; }
  .lbl, legend {
    margin-top: var(--sp-2);
    font-size: var(--fs-sm);
    font-weight: var(--fw-bold);
    text-transform: uppercase;
    letter-spacing: var(--tracking-caps);
  }
  legend { padding: 0; margin-bottom: var(--sp-2); }
  .opt-txt { text-transform: none; letter-spacing: 0; font-weight: var(--fw-regular); color: var(--text-secondary); }
  .group { border: 0; margin: 0; padding: 0; }
  .two-col { display: grid; grid-template-columns: 1fr 1fr; gap: var(--sp-3); }
  .two-col > div { min-width: 0; display: flex; flex-direction: column; gap: 6px; }
  .two-col .input { width: 100%; min-width: 0; }
  .opts { display: flex; flex-wrap: wrap; gap: var(--sp-2); }
  .opt {
    display: inline-flex;
    align-items: center;
    gap: 6px;
    min-height: 44px;
    padding: 0 14px;
    border: var(--line-w) solid var(--line);
    background: var(--surface);
    color: var(--text);
    font: var(--fw-medium) 15px var(--font-body);
    cursor: pointer;
    touch-action: manipulation;
    transition: transform var(--dur-fast) var(--ease-out);
  }
  .opt:active { transform: translate(2px, 2px); }
  .opt[aria-pressed='true'] { background: var(--accent); color: var(--on-accent); font-weight: var(--fw-bold); box-shadow: var(--shadow-sm); }
  .hint { margin: 6px 0 0; font-size: 13px; color: var(--text-secondary); }
  .poles { list-style: none; margin: 0; padding: 0; display: flex; flex-wrap: wrap; gap: 6px; }
  .pole {
    display: inline-flex;
    align-items: center;
    gap: 2px;
    padding-left: 10px;
    border: var(--line-thin) solid var(--line);
    background: var(--surface);
    font-weight: var(--fw-medium);
  }
  .pole-x {
    width: 40px;
    height: 40px;
    display: grid;
    place-items: center;
    border: 0;
    background: transparent;
    color: var(--text);
    cursor: pointer;
    touch-action: manipulation;
  }
  .add-row { display: flex; gap: var(--sp-2); margin-top: var(--sp-2); }
  .add-row .input { flex: 1; min-width: 0; }
  textarea { resize: vertical; font: inherit; }
  .field-error { color: var(--error); font-weight: var(--fw-bold); }
  .actions { display: flex; gap: var(--sp-3); margin-top: var(--sp-3); }
  .actions .btn { flex: 1; min-height: 48px; }
</style>
