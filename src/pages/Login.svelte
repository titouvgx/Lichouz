<script lang="ts">
  import { onMount, tick } from 'svelte'
  import CatLogo from '../components/CatLogo.svelte'
  import Icon from '../components/Icon.svelte'
  import { auth, signIn } from '../lib/auth.svelte'
  import { href } from '../lib/router.svelte'
  import { VERSION_LABEL } from '../lib/version'
  import { resendConfirmation } from '../lib/api/famille'

  let email = $state('')
  let password = $state('')
  let showPassword = $state(false)
  let submitting = $state(false)

  /** Erreur de saisie détectée avant l'envoi (champ vide, adresse mal écrite). */
  let formError = $state<{ field: 'email' | 'password' | null; message: string } | null>(null)
  /** Erreur réseau détectée ici (sans appeler Supabase). */
  let offlineError = $state(false)

  let emailInput: HTMLInputElement | undefined = $state()
  let passwordInput: HTMLInputElement | undefined = $state()

  /** Traduit les messages renvoyés par Supabase Auth en français clair. */
  function translate(raw: string | null): string | null {
    if (!raw) return null
    const m = raw.toLowerCase()
    // Déjà traduit dans auth.svelte.ts
    if (raw === 'Email ou mot de passe incorrect.' || m.includes('invalid login credentials'))
      return 'E-mail ou mot de passe incorrect.'
    if (m.includes('email not confirmed'))
      return "Ton adresse e-mail n'est pas encore confirmée. Ouvre le lien reçu par e-mail (regarde aussi les spams), puis réessaie."
    if (m.includes('rate limit') || m.includes('too many') || m.includes('429'))
      return 'Trop de tentatives. Patiente quelques minutes avant de réessayer.'
    if (m.includes('failed to fetch') || m.includes('network') || m.includes('load failed') || m.includes('fetch'))
      return 'Pas de connexion internet. Vérifie ton réseau, puis réessaie.'
    if (m.includes('non configuré'))
      return "L'appli n'est pas reliée à son serveur (configuration manquante)."
    if (m.includes('user banned') || m.includes('banned'))
      return 'Ce compte est suspendu. Contacte l’administrateur.'
    return "La connexion n'a pas abouti. Réessaie dans un instant."
  }

  const errorMessage = $derived(
    formError?.message
      ?? (offlineError ? 'Pas de connexion internet. Vérifie ton réseau, puis réessaie.' : null)
      ?? translate(auth.error),
  )
  // Sur quel(s) champ(s) mettre le contour rouge
  const emailInvalid = $derived(formError ? formError.field === 'email' : auth.error != null)
  const passwordInvalid = $derived(formError ? formError.field === 'password' : auth.error != null)

  // Adresse pas encore confirmée (Supabase ne le dit qu'avec le BON mot de passe)
  const notConfirmed = $derived(!formError && !offlineError && !!auth.error && /not confirmed/i.test(auth.error))
  let resending = $state(false)
  let resendMsg = $state<{ tone: 'ok' | 'error'; text: string } | null>(null)

  async function handleResend() {
    if (resending) return
    resending = true
    resendMsg = null
    try {
      await resendConfirmation(email)
      resendMsg = { tone: 'ok', text: 'E-mail renvoyé. Regarde aussi dans les spams.' }
    } catch (err) {
      resendMsg = { tone: 'error', text: err instanceof Error ? err.message : 'L’e-mail n’a pas pu être envoyé.' }
    }
    resending = false
  }

  onMount(() => {
    // Premier champ au clavier/souris. Sur téléphone on évite d'ouvrir le
    // clavier d'office : il masquerait l'écran d'accueil.
    if (window.matchMedia('(hover: hover) and (pointer: fine)').matches) emailInput?.focus()
  })

  function clearErrors() {
    resendMsg = null
    formError = null
    offlineError = false
    if (auth.error) auth.error = null
  }

  async function handleSubmit(e: SubmitEvent) {
    e.preventDefault()
    if (submitting) return

    const mail = email.trim()
    if (!mail) {
      formError = { field: 'email', message: 'Indique ton adresse e-mail.' }
      emailInput?.focus()
      return
    }
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(mail)) {
      formError = { field: 'email', message: 'Cette adresse e-mail ne semble pas complète (ex. prenom@exemple.fr).' }
      emailInput?.focus()
      return
    }
    if (!password) {
      formError = { field: 'password', message: 'Indique ton mot de passe.' }
      passwordInput?.focus()
      return
    }
    if (!navigator.onLine) {
      offlineError = true
      return
    }

    formError = null
    offlineError = false
    submitting = true
    try {
      await signIn(mail, password)
    } catch {
      auth.error = 'Failed to fetch'
    }
    submitting = false
    if (auth.error) {
      await tick()
      passwordInput?.focus()
      passwordInput?.select()
    }
  }
</script>

<main class="auth-page">
  <div class="auth-inner">
    <header class="brand">
      <div class="logo-box" aria-hidden="true">
        <CatLogo size={46} />
      </div>
      <h1>Lichouz</h1>
      <p class="tagline">Les recettes, la semaine et la liste de courses, partagées à la maison.</p>
    </header>

    <section class="auth-card card" aria-labelledby="login-title">
      <h2 id="login-title">Connexion</h2>

      <form onsubmit={handleSubmit} novalidate>
        <div class="field">
          <label for="login-email" class="label">Adresse e-mail</label>
          <div class="input-wrap">
            <span class="input-icon"><Icon name="mail" size={18} /></span>
            <input
              bind:this={emailInput}
              id="login-email"
              name="email"
              type="email"
              inputmode="email"
              autocomplete="email"
              autocapitalize="off"
              spellcheck="false"
              class="input input-has-icon"
              class:error={emailInvalid}
              aria-invalid={emailInvalid}
              aria-describedby={errorMessage ? 'login-error' : undefined}
              placeholder="prenom@exemple.fr"
              bind:value={email}
              oninput={clearErrors}
            />
          </div>
        </div>

        <div class="field">
          <label for="login-password" class="label">Mot de passe</label>
          <div class="input-wrap">
            <span class="input-icon"><Icon name="lock" size={18} /></span>
            <input
              bind:this={passwordInput}
              id="login-password"
              name="password"
              type={showPassword ? 'text' : 'password'}
              autocomplete="current-password"
              autocapitalize="off"
              spellcheck="false"
              class="input input-has-icon input-has-toggle"
              class:error={passwordInvalid}
              aria-invalid={passwordInvalid}
              aria-describedby={errorMessage ? 'login-error' : undefined}
              placeholder="Ton mot de passe"
              bind:value={password}
              oninput={clearErrors}
            />
            <button
              type="button"
              class="eye-btn"
              aria-label={showPassword ? 'Masquer le mot de passe' : 'Afficher le mot de passe'}
              aria-pressed={showPassword}
              aria-controls="login-password"
              onclick={() => (showPassword = !showPassword)}
            >
              <Icon name={showPassword ? 'eye-off' : 'eye'} size={20} />
            </button>
          </div>
        </div>

        {#if errorMessage}
          <p id="login-error" class="error-msg" role="alert">{errorMessage}</p>
        {/if}
        {#if notConfirmed}
          <button type="button" class="btn btn-outline resend-btn" disabled={resending} aria-busy={resending} onclick={handleResend}>
            <Icon name="mail" size={16} /> {resending ? 'Envoi…' : 'Renvoyer l’e-mail de confirmation'}
          </button>
          {#if resendMsg}
            <p class="resend-msg" data-tone={resendMsg.tone} role={resendMsg.tone === 'error' ? 'alert' : 'status'}>{resendMsg.text}</p>
          {/if}
        {/if}

        <button type="submit" class="btn btn-primary btn-login" aria-busy={submitting}>
          {#if submitting}
            <span class="btn-spinner" aria-hidden="true"></span>
            Connexion…
          {:else}
            Se connecter
          {/if}
        </button>
      </form>

      <div class="forgot">
        <a class="forgot-link" href={href('mot-de-passe-oublie')}>Mot de passe oublié ?</a>
      </div>

      <p class="hint">
        Pas encore de compte ? Demande un lien d’invitation à l’admin de ton foyer.
      </p>
    </section>

    <p class="legal-links">
      <a href={href('cgu')}>Conditions</a> · <a href={href('confidentialite')}>Confidentialité</a> · <a href={href('stockage')}>Stockage</a>
    </p>
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
    background: var(--butter);
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
    .logo-box :global(svg) { width: 34px; height: 34px; }
    h1 { font-size: 40px; }
  }

  .tagline {
    max-width: 300px;
    color: var(--text);
    font-size: var(--fs-base);
    line-height: 1.4;
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

  .input-has-toggle { padding-right: 52px; }

  .eye-btn {
    position: absolute;
    right: 4px;
    top: 50%;
    transform: translateY(-50%);
    width: 44px;
    height: 44px;
    display: flex;
    align-items: center;
    justify-content: center;
    border: none;
    background: transparent;
    color: var(--text-secondary);
    cursor: pointer;
    touch-action: manipulation;
  }
  .eye-btn[aria-pressed='true'] { color: var(--text); background: var(--highlight); }
  .eye-btn:focus-visible { outline-offset: -3px; }

  .error-msg {
    font-size: var(--fs-sm);
    font-weight: var(--fw-medium);
    line-height: 1.4;
    color: var(--error);
    background: var(--error-bg);
    border: var(--line-w) solid var(--error);
    padding: var(--sp-3);
  }

  .btn-login { margin-top: var(--sp-1); min-height: 52px; }
  .btn-login[aria-busy='true'] { cursor: progress; opacity: 0.85; }

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

  .hint {
    margin-top: var(--sp-3);
    font-size: var(--fs-sm);
    line-height: 1.45;
    color: var(--text-secondary);
    text-align: center;
  }

  .resend-msg {
    margin-top: var(--sp-3);
    font-size: var(--fs-sm);
    font-weight: var(--fw-medium);
    line-height: 1.4;
    padding: var(--sp-3);
    border: var(--line-w) solid var(--line);
  }
  .resend-msg[data-tone='ok'] { background: var(--success-bg); color: var(--success); border-color: var(--success); }
  .resend-msg[data-tone='error'] { background: var(--error-bg); color: var(--error); border-color: var(--error); }

  .resend-btn {
    width: 100%;
    margin-top: -4px;
    font-size: var(--fs-sm);
  }

  .legal-links { text-align: center; font-size: var(--fs-sm); }
  .legal-links a { display: inline-block; padding: 12px 4px; color: var(--text); font-weight: var(--fw-bold); text-decoration-thickness: 2px; text-underline-offset: 3px; }
  .forgot {
    margin-top: var(--sp-2);
    display: flex;
    justify-content: center;
  }
  .forgot-link {
    display: inline-flex;
    align-items: center;
    min-height: 44px;
    padding: 0 var(--sp-3);
    font-size: var(--fs-sm);
    font-weight: var(--fw-bold);
    color: var(--text);
    text-decoration: underline;
    text-decoration-thickness: 2px;
    text-underline-offset: 3px;
    touch-action: manipulation;
  }

  @media (hover: hover) and (pointer: fine) {
    .eye-btn:hover { color: var(--text); background: var(--surface-hover); }
    .forgot-link:hover { background: var(--highlight); }
  }
</style>
