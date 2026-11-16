<script lang="ts">
  // « Nouveautés » (#/nouveautes), depuis Mon compte : ce qui a changé, version par version.
  import Icon from '../components/Icon.svelte'
  import { href } from '../lib/router.svelte'
  import { RELEASE_NOTES } from '../lib/nouveautes'
  import { APP_VERSION } from '../lib/version'

  const fmt = (d: string) =>
    new Date(`${d}T12:00:00`).toLocaleDateString('fr-FR', { day: 'numeric', month: 'long', year: 'numeric' })
</script>

<div class="page">
  <a href={href('compte')} class="back-link"><Icon name="arrow-left" size={18} /> Mon compte</a>
  <header class="head">
    <h1>Nouveautés</h1>
    <p class="head-sub">Tu utilises la version {APP_VERSION}.</p>
  </header>

  {#each RELEASE_NOTES as note, ni (note.version)}
    <section class="card" style="--i: {Math.min(ni, 8)}" aria-labelledby="v-{note.version}">
      <h2 id="v-{note.version}">Version {note.version} <span class="date">{fmt(note.date)}</span></h2>
      <ul>
        {#each note.items as item, i (i)}
          <li>{item}</li>
        {/each}
      </ul>
    </section>
  {/each}
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
    touch-action: manipulation;
  }
  .head h1 { padding-right: 56px; }
  .head-sub { margin-top: var(--sp-1); font-size: 15px; font-weight: var(--fw-medium); color: var(--text-secondary); }
  .card {
    padding: var(--sp-4);
    animation: fade-up var(--dur-sheet) var(--ease-out) calc(var(--i, 0) * 45ms) backwards;
  }
  h2 { font-size: var(--fs-lg); display: flex; flex-wrap: wrap; align-items: baseline; gap: var(--sp-2); }
  .date { font-size: 13px; font-weight: var(--fw-medium); color: var(--text-secondary); }
  ul { margin: var(--sp-2) 0 0; padding-left: 20px; display: flex; flex-direction: column; gap: 6px; line-height: 1.45; }
  li::marker { color: var(--accent); }
</style>
