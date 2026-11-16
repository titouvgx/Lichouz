<script lang="ts">
  // #/mot-de-passe-oublie : demande d'e-mail de réinitialisation (sans être connecté).
  // Même message que le compte existe ou non (on ne révèle pas les adresses inscrites).
  import { onMount, tick } from 'svelte'
  import Icon from '../components/Icon.svelte'
  import { href } from '../lib/router.svelte'
  import { VERSION_LABEL } from '../lib/version'
  import { requestPasswordReset } from '../lib/api/famille'

  const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/
  const OFFLINE_MSG = 'Pas de connexion internet. Vérifie ton réseau, puis réessaie.'

  let email = $state('')
  let submitting = $state(false)
  let sent = $state(false)
  let fieldError = $state<string | null>(null)
  let apiError = $state<string | null>(null)

  let emailInput: HTMLInputElement | undefined = $state()
  let titleEl: HTMLHeadingElement | undefined = $state()

  onMount(() => {
    // Au clavier/souris seulement : sur téléphone, le clavier masquerait la page
    if (window.matchMedia('(hover: hover) and (pointer: fine)').matches) emailInput?.focus()
  })

  function clearErrors() {
    fieldError = null
    apiError = null
  }

  async function handleSubmit(e: SubmitEvent) {
    e.preventDefault()
    if (submitting) return
    apiError = null

    const mail = email.trim()
    if (!mail) {
      fieldError = 'Indique ton adresse e-mail.'
      emailInput?.focus()
      return
    }
    if (!EMAIL_RE.test(mail)) {
      fieldError = 'Cette adresse e-mail ne semble pas complète (ex. prenom@exemple.fr).'
      emailInput?.focus()
      return
    }
    if (!navigator.onLine) {
      apiError = OFFLINE_MSG
      return
    }

    fieldError = null
    submitting = true
    try {
      await requestPasswordReset(mail)
      sent = true
      await tick()
      titleEl?.focus()
    } catch (err) {
      const message = err instanceof Error ? err.message : ''
      apiError = message.startsWith('Trop de demandes')
        ? message
        : 'La demande n’a pas abouti. Réessaie dans un instant.'
    }
    submitting = false
  }

  async function sendAnother() {
    sent = false
    await tick()
    emailInput?.focus()
  }
</script>

<main class="auth-page">
  <div class="auth-inner">
    <header class="brand">
      <div class="logo-box" aria-hidden="true">
        <svg width="40" height="40" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.25" stroke-linecap="square" stroke-linejoin="miter">
          <circle cx="9" cy="21" r="1"/><circle cx="20" cy="21" r="1"/>
          <path d="M1 1h4l2.68 13.39a2 2 0 0 0 2 1.61h9.72a2 2 0 0 0 2-1.61L23 6H6"/>
        </svg>
      </div>
      <h1>Lichouz</h1>
    </header>

    <section class="auth-card card" aria-labelledby="forgot-title">
      {#if sent}
        <div class="status" role="status">
          <span class="status-icon"><Icon name="mail" size={28} /></span>
          <h2 id="forgot-title" tabindex="-1" bind:this={titleEl}>Regarde tes e-mails</h2>
          <p class="status-text">
            Si un compte existe avec cette adresse, tu vas recevoir un e-mail avec un lien
            (pense à regarder les indésirables).
          </p>
          <div class="actions">
            <a class="btn btn-primary btn-main" href={href('login')}>Retour à la connexion</a>
            <button type="button" class="text-link" onclick={sendAnother}>Rien reçu ? Refaire une demande</button>
          </div>
        </div>
      {:else}
        <h2 id="forgot-title">Mot de passe oublié</h2>
        <p class="lead">
          Indique l’adresse e-mail de ton compte : on t’envoie un lien pour choisir un nouveau mot de passe.
        </p>

        <form onsubmit={handleSubmit} novalidate>
          <div class="field">
            <label for="forgot-email" class="label">Adresse e-mail</label>
            <div class="input-wrap">
              <span class="input-icon"><Icon name="mail" size={18} /></span>
              <input
                bind:this={emailInput}
                id="forgot-email"
                name="email"
                type="email"
                inputmode="email"
                autocomplete="email"
                autocapitalize="off"
                spellcheck="false"
                class="input input-has-icon"
                class:error={fieldError != null}
                aria-invalid={fieldError != null}
                aria-describedby="forgot-email-msg"
                placeholder="prenom@exemple.fr"
                bind:value={email}
                oninput={clearErrors}
              />
            </div>
            <p id="forgot-email-msg" class="field-msg" aria-live="polite">{fieldError ?? ''}</p>
          </div>

          {#if apiError}
            <p class="error-msg" role="alert">{apiError}</p>
          {/if}

          <button type="submit" class="btn btn-primary btn-main" disabled={submitting} aria-busy={submitting}>
            {#if submitting}
              <span class="btn-spinner" aria-hidden="true"></span>
              Envoi…
            {:else}
              Recevoir le lien
            {/if}
          </button>
        </form>

        <div class="back">
          <a class="text-link" href={href('login')}>
            <Icon name="arrow-left" size={18} /> Retour à la connexion
          </a>
        </div>
      {/if}
    </section>

    <p class="app-version">{VERSION_LABEL}</p>
  </div>
</main>




<style>
  .auth-page {
    min-height: 100svh;
    display: flex;
    align-items: center;
    justify-content: center;
    padding:
      calc(var(--sp-5) + env(safe-area-inset-top, 0px))
      calc(var(--gutter) + env(safe-area-inset-right, 0px))
      calc(var(--sp-5) + env(safe-area-inset-bottom, 0px))
      calc(var(--gutter) + env(safe-area-inset-left, 0px));
    animation: page-in var(--dur-page) var(--ease-out);
  }

  .auth-inner {
    width: 100%;
    max-width: 400px;
    display: flex;
    flex-direction: column;
    gap: var(--sp-5);
  }

  /* ── En-tête : carré orange + nom en très gros ── */
  .brand {
    text-align: center;
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: var(--sp-3);
  }

  .logo-box {
    width: 76px;
    height: 76px;
    display: grid;
    place-items: center;
    background: var(--accent);
    color: var(--on-accent);
    border: var(--line-w) solid var(--line);
    box-shadow: var(--shadow-md);
    animation: snap-in var(--dur-sheet) var(--ease-snap) backwards;
  }

  h1 {
    font-size: clamp(44px, 15vw, 60px);
    line-height: 0.95;
    letter-spacing: -0.03em;
    color: var(--text);
  }

  /* ── Carte ── */
  .auth-card {
    padding: var(--sp-5) var(--sp-4) var(--sp-4);
    animation: fade-up var(--dur-sheet) var(--ease-out) 60ms backwards;
  }

  h2 {
    font-size: var(--fs-xl);
    line-height: 1.15;
    text-transform: uppercase;
    margin-bottom: var(--sp-4);
    overflow-wrap: anywhere;
  }
  h2:focus { outline: none; }

  .app-version {
    margin: 0;
    text-align: center;
    font-size: var(--fs-xs);
    font-weight: var(--fw-medium);
    color: var(--text-secondary);
    font-variant-numeric: tabular-nums;
  }

  @media (max-height: 640px) {
    .auth-inner { gap: var(--sp-3); }
    .logo-box { width: 56px; height: 56px; }
    .logo-box svg { width: 30px; height: 30px; }
    h1 { font-size: 40px; }
  }

  .lead {
    margin: calc(var(--sp-2) * -1) 0 var(--sp-4);
    font-size: var(--fs-base);
    line-height: 1.45;
    color: var(--text-secondary);
  }

  form {
    display: flex;
    flex-direction: column;
    gap: var(--sp-4);
  }

  .field {
    display: flex;
    flex-direction: column;
  }

  .input-wrap { position: relative; }

  .input-icon {
    position: absolute;
    left: 14px;
    top: 50%;
    transform: translateY(-50%);
    display: flex;
    color: var(--text);
    pointer-events: none;
  }

  .input { min-height: 52px; }
  .input-has-icon { padding-left: 44px; }

  .field-msg {
    font-size: var(--fs-sm);
    font-weight: var(--fw-medium);
    line-height: 1.4;
    color: var(--error);
  }
  .field-msg:not(:empty) { margin-top: var(--sp-2); }

  .error-msg {
    font-size: var(--fs-sm);
    font-weight: var(--fw-medium);
    line-height: 1.4;
    color: var(--error);
    background: var(--error-bg);
    border: var(--line-w) solid var(--error);
    padding: var(--sp-3);
  }

  .btn-main {
    width: 100%;
    margin-top: var(--sp-1);
    min-height: 52px;
    font-size: var(--fs-base);
  }
  .btn-main:disabled { opacity: 0.7; cursor: progress; }

  .btn-spinner {
    width: 18px;
    height: 18px;
    border: 3px solid var(--on-accent);
    border-top-color: transparent;
    animation: spin 0.7s linear infinite;
  }

  @keyframes spin {
    to { transform: rotate(360deg); }
  }

  .text-link {
    display: inline-flex;
    align-items: center;
    justify-content: center;
    gap: 6px;
    min-height: 44px;
    padding: 0 var(--sp-3);
    border: none;
    background: transparent;
    color: var(--text);
    font-family: var(--font-body);
    font-size: var(--fs-base);
    font-weight: var(--fw-bold);
    text-decoration: underline;
    text-decoration-thickness: 2px;
    text-underline-offset: 3px;
    cursor: pointer;
    touch-action: manipulation;
    transition: transform var(--dur-fast) var(--ease-out);
  }
  .text-link:active:not(:disabled) { transform: translate(1px, 1px); }
  .text-link:disabled { opacity: 0.5; cursor: not-allowed; }

  .back {
    margin-top: var(--sp-3);
    display: flex;
    justify-content: center;
  }

  .status {
    display: flex;
    flex-direction: column;
    align-items: center;
    text-align: center;
    padding: var(--sp-2) 0 var(--sp-1);
  }
  .status h2 { margin-bottom: var(--sp-2); }

  .status-icon {
    width: 56px;
    height: 56px;
    display: grid;
    place-items: center;
    margin-bottom: var(--sp-3);
    border: var(--line-w) solid var(--line);
    box-shadow: var(--shadow-sm);
    background: var(--highlight);
    color: var(--text);
  }

  .status-text {
    font-size: var(--fs-base);
    line-height: 1.5;
    color: var(--text-secondary);
  }

  .actions {
    margin-top: var(--sp-5);
    width: 100%;
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: var(--sp-2);
  }

  @media (hover: hover) and (pointer: fine) {
    .text-link:not(:disabled):hover { background: var(--highlight); }
  }
</style>
