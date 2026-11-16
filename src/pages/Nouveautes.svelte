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

  {#each RELEASE_NOTES as note (note.version)}
    <section class="card" aria-labelledby="v-{note.version}">
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
  .card {
    background: var(--surface);
    border: 1px solid var(--border);
    border-radius: var(--radius-xl);
    padding: 18px;
  }
  .page {
    padding: var(--gutter);
    padding-top: 0;
    max-width: 560px;
    margin: 0 auto;
    padding-bottom: 32px;
    display: flex;
    flex-direction: column;
    gap: 12px;
  }
  .back-link {
    display: inline-flex;
    align-items: center;
    align-self: flex-start;
    gap: 6px;
    min-height: 44px;
    margin-top: calc(8px + env(safe-area-inset-top, 0px));
    color: var(--primary);
    font-weight: 600;
    touch-action: manipulation;
  }
  .head h1 { font-family: var(--font-display); font-size: 28px; padding-right: 48px; }
  .head-sub { margin-top: 4px; font-size: 15px; color: var(--text-secondary); }
  h2 { font-size: 17px; display: flex; flex-wrap: wrap; align-items: baseline; gap: 8px; }
  .date { font-size: 13px; font-weight: 500; color: var(--text-secondary); }
  ul { margin: 8px 0 0; padding-left: 20px; display: flex; flex-direction: column; gap: 6px; line-height: 1.45; }
</style>
