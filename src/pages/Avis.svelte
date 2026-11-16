<script lang="ts">
  // « Idées et retours » (#/avis), depuis Mon compte : envoyer une idée, un bug
  // ou une remarque. Lu par Titouan dans Administration. 10 envois par jour max.
  import Icon from '../components/Icon.svelte'
  import { href } from '../lib/router.svelte'
  import { toast } from '../lib/toast.svelte'
  import { sendFeedback, FEEDBACK_MAX, type FeedbackKind } from '../lib/api/feedback'

  const KINDS: { value: FeedbackKind; label: string; hint: string }[] = [
    { value: 'idee', label: 'Une idée', hint: 'Ce qui rendrait Lichouz plus pratique ou plus sympa.' },
    { value: 'bug', label: 'Un bug', hint: 'Ce que tu faisais, ce qui s’est passé, sur quel écran.' },
    { value: 'autre', label: 'Autre chose', hint: 'Une remarque, une question.' },
  ]

  let kind = $state<FeedbackKind>('idee')
  let message = $state('')
  let sending = $state(false)
  let sent = $state(false)

  const hint = $derived(KINDS.find((k) => k.value === kind)?.hint ?? '')
  const canSend = $derived(message.trim().length > 0 && !sending)

  async function submit(e: SubmitEvent) {
    e.preventDefault()
    if (!canSend) return
    sending = true
    try {
      await sendFeedback(kind, message)
      sent = true
      message = ''
    } catch (err: any) {
      toast.error(err?.message ?? 'Envoi impossible')
    } finally {
      sending = false
    }
  }
</script>

<div class="page">
  <a href={href('compte')} class="back-link"><Icon name="arrow-left" size={18} /> Mon compte</a>

  <header class="head">
    <h1>Idées et retours</h1>
    <p class="head-sub">Une idée, un bug, une remarque : Titouan lit tout.</p>
  </header>

  {#if sent}
    <div class="card done" role="status">
      <p><strong>Merci, c’est envoyé.</strong></p>
      <button class="btn btn-outline" onclick={() => (sent = false)}>Envoyer autre chose</button>
    </div>
  {:else}
    <form class="card" onsubmit={submit}>
      <fieldset class="kinds">
        <legend>C’est…</legend>
        {#each KINDS as k (k.value)}
          <label class="kind" class:active={kind === k.value}>
            <input type="radio" name="kind" value={k.value} bind:group={kind} />
            {k.label}
          </label>
        {/each}
      </fieldset>

      <label class="field-label" for="avis-message">Ton message</label>
      <p class="hint" id="avis-hint">{hint}</p>
      <textarea
        id="avis-message"
        class="input"
        rows="6"
        maxlength={FEEDBACK_MAX}
        aria-describedby="avis-hint"
        bind:value={message}
      ></textarea>
      {#if message.length > FEEDBACK_MAX - 200}
        <p class="hint" aria-live="polite">{message.length} / {FEEDBACK_MAX} caractères</p>
      {/if}

      <button class="btn btn-primary" type="submit" disabled={!canSend}>
        {sending ? 'Envoi…' : 'Envoyer'}
      </button>
      <p class="hint">Ton prénom et ta famille sont joints au message.</p>
    </form>
  {/if}
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

  form, .done { display: flex; flex-direction: column; gap: 10px; }
  .kinds { border: 0; margin: 0; padding: 0; display: flex; flex-wrap: wrap; gap: 8px; }
  .kinds legend { font-weight: 600; margin-bottom: 8px; padding: 0; }
  .kind {
    position: relative;
    display: inline-flex;
    align-items: center;
    min-height: 44px;
    padding: 0 14px;
    border: 1px solid var(--border);
    border-radius: var(--radius-md);
    cursor: pointer;
    font-weight: 600;
    touch-action: manipulation;
  }
  .kind.active { border-color: var(--primary); color: var(--primary); }
  .kind input { position: absolute; opacity: 0; pointer-events: none; }
  .kind:has(input:focus-visible) { outline: 2px solid var(--primary); outline-offset: 2px; }
  .field-label { font-weight: 600; margin-top: 4px; }
  .hint { margin: 0; font-size: 13px; color: var(--text-secondary); }
  textarea { resize: vertical; min-height: 140px; font: inherit; }
</style>
