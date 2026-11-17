<script lang="ts">
  // #/nouveau-mot-de-passe : arrivée depuis l'e-mail « mot de passe oublié ».
  // L'adresse est …/?token_hash=…&type=recovery#/nouveau-mot-de-passe : on valide
  // le jeton (ce qui ouvre une session), puis on le retire aussitôt de l'adresse
  // pour qu'il ne reste ni dans l'historique ni dans un partage.
  import { onDestroy, onMount, tick } from 'svelte'
  import Icon from '../components/Icon.svelte'
  import { auth, signOut } from '../lib/auth.svelte'
  import { navigate, href } from '../lib/router.svelte'
  import { VERSION_LABEL } from '../lib/version'
  import { setNewPassword, setRecoveryPending, verifyRecoveryLink } from '../lib/api/famille'

  const PW_MIN = 10
  const PW_MAX_BYTES = 72 // limite de Supabase Auth (bcrypt)
  const OFFLINE_MSG = 'Pas de connexion internet. Vérifie ton réseau, puis réessaie.'

  // ── Lien reçu par e-mail ──
  const initialHash = new URLSearchParams(window.location.search).get('token_hash')
  /** Jeton gardé en mémoire seulement (pour « Réessayer » sans réseau), jamais affiché. */
  let pendingHash: string | null = initialHash
  let verifying = $state(initialHash != null) // dès le 1er affichage : pas d'éclair « Lien invalide »
  let verified = $state(false)
  let linkError = $state<{ message: string; canRetry: boolean } | null>(null)

  function cleanUrl() {
    history.replaceState(history.state, '', `${window.location.pathname}${href('nouveau-mot-de-passe')}`)
  }

  async function runVerify(clean = false) {
    if (!pendingHash) return
    linkError = null
    if (!navigator.onLine) {
      if (clean) cleanUrl()
      verifying = false
      linkError = { message: OFFLINE_MSG, canRetry: true }
      return
    }
    verifying = true
    const pending = verifyRecoveryLink(pendingHash)
    if (clean) cleanUrl() // tout de suite, sans attendre la réponse
    try {
      await pending
      pendingHash = null
      verified = true
    } catch (err) {
      if (!navigator.onLine) {
        linkError = { message: OFFLINE_MSG, canRetry: true }
      } else {
        pendingHash = null
        linkError = {
          message: err instanceof Error && err.message
            ? err.message
            : 'Ce lien a expiré ou a déjà servi. Demande un nouvel e-mail.',
          canRetry: false,
        }
      }
    }
    verifying = false
  }

  onMount(() => {
    if (pendingHash) void runVerify(true)
    else if (new URLSearchParams(window.location.search).has('type')) cleanUrl()
  })

  // ── Nouveau mot de passe ──
  let password = $state('')
  let confirm = $state('')
  let showPassword = $state(false)
  let saving = $state(false)
  let done = $state(false)
  let pwError = $state<string | null>(null)
  let confirmError = $state<string | null>(null)
  let apiError = $state<string | null>(null)
  let redirectTimer: ReturnType<typeof setTimeout> | undefined

  let passwordInput: HTMLInputElement | undefined = $state()
  let confirmInput: HTMLInputElement | undefined = $state()

  onDestroy(() => clearTimeout(redirectTimer))

  // Solidité du mot de passe : même logique que Mon compte (longueur + variété)
  const strength = $derived.by(() => {
    const p = password
    if (!p) return null
    if (p.length < PW_MIN) return { level: 0, label: `Trop court (${PW_MIN} caractères min.)` }
    let score = 0
    if (p.length >= 10) score++
    if (p.length >= 14) score++
    if (/[a-z]/i.test(p) && /\d/.test(p)) score++
    if (/[^a-z0-9]/i.test(p) || (/[a-z]/.test(p) && /[A-Z]/.test(p))) score++
    if (score <= 1) return { level: 1, label: 'Faible' }
    if (score === 2) return { level: 2, label: 'Correct' }
    return { level: 3, label: 'Solide' }
  })

  const passwordsMatch = $derived(confirm.length > 0 && confirm === password)
  const passwordsDiffer = $derived(confirm.length > 0 && confirm !== password)

  /** Ce que la page montre (le lien d'abord, puis la session). */
  const view = $derived.by(() => {
    if (done) return 'done' as const
    if (verifying || (verified && !auth.user) || (auth.loading && !linkError)) return 'loading' as const
    if (linkError) return 'link-error' as const
    if (!auth.user) return 'invalid' as const
    return 'form' as const
  })

  async function handleSubmit(e: SubmitEvent) {
    e.preventDefault()
    if (saving) return
    apiError = null
    pwError = null
    confirmError = null

    if (!password) pwError = 'Choisis un nouveau mot de passe.'
    else if (password.length < PW_MIN) pwError = `Le mot de passe doit faire au moins ${PW_MIN} caractères.`
    else if (new TextEncoder().encode(password).length > PW_MAX_BYTES) pwError = 'Ce mot de passe est trop long (72 caractères maximum).'

    if (!confirm) confirmError = 'Retape le mot de passe pour le confirmer.'
    else if (confirm !== password) confirmError = 'Les deux mots de passe ne correspondent pas.'

    if (pwError) { passwordInput?.focus(); return }
    if (confirmError) { confirmInput?.focus(); return }
    if (!navigator.onLine) {
      apiError = OFFLINE_MSG
      return
    }

    saving = true
    try {
      await setNewPassword(password)
      // Mot de passe changé : on ferme la session ouverte par le lien, sur tous les
      // appareils, et on demande de se reconnecter avec le nouveau mot de passe.
      setRecoveryPending(false)
      done = true
      password = ''
      confirm = ''
      await signOut('global')
      redirectTimer = setTimeout(() => navigate('login'), 2500)
    } catch (err) {
      apiError = err instanceof Error && err.message
        ? err.message
        : 'Le mot de passe n’a pas pu être changé.'
      await tick()
      passwordInput?.focus()
    }
    saving = false
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

    <section class="auth-card card" aria-labelledby="newpw-title">
      {#if view === 'done'}
        <div class="status" role="status">
          <span class="status-icon" data-tone="success"><Icon name="check-circle" size={28} /></span>
          <h2 id="newpw-title">Mot de passe changé !</h2>
          <p class="status-text">Reconnecte-toi avec ton nouveau mot de passe. Par sécurité, tu as été déconnecté de tous tes appareils.</p>
          <div class="actions">
            <a class="text-link" href={href('login')}>Se connecter maintenant</a>
          </div>
        </div>
      {:else if view === 'loading'}
        <div class="status" role="status">
          <span class="big-spinner" aria-hidden="true"></span>
          <h2 id="newpw-title">Vérification du lien…</h2>
        </div>
      {:else if view === 'link-error' && linkError}
        <div class="status">
          <span class="status-icon" data-tone="error"><Icon name="alert-circle" size={28} /></span>
          <h2 id="newpw-title">{linkError.canRetry ? 'Impossible de vérifier le lien' : 'Lien expiré'}</h2>
          <p class="status-text" role="alert">{linkError.message}</p>
          <div class="actions">
            {#if linkError.canRetry}
              <button type="button" class="btn btn-primary btn-main" onclick={() => runVerify()}>
                <Icon name="refresh" size={18} /> Réessayer
              </button>
            {:else}
              <a class="btn btn-primary btn-main" href={href('mot-de-passe-oublie')}>Recevoir un nouvel e-mail</a>
            {/if}
            <a class="text-link" href={href('login')}>Retour à la connexion</a>
          </div>
        </div>
      {:else if view === 'invalid'}
        <div class="status">
          <span class="status-icon" data-tone="error"><Icon name="alert-circle" size={28} /></span>
          <h2 id="newpw-title">Lien invalide</h2>
          <p class="status-text">
            Ce lien est incomplet ou n’est plus valable. Pour choisir un nouveau mot de passe,
            demande un nouvel e-mail.
          </p>
          <div class="actions">
            <a class="btn btn-primary btn-main" href={href('mot-de-passe-oublie')}>Mot de passe oublié</a>
            <a class="text-link" href={href('login')}>Retour à la connexion</a>
          </div>
        </div>
      {:else}
        <h2 id="newpw-title">Nouveau mot de passe</h2>
        <p class="lead">
          Choisis un nouveau mot de passe{#if auth.user?.email}{' '}pour <strong class="account">{auth.user.email}</strong>{/if}.
        </p>

        <form onsubmit={handleSubmit} novalidate>
          <!-- Pour le gestionnaire de mots de passe : à quel compte associer le nouveau -->
          {#if auth.user?.email}
            <input
              class="sr-only"
              type="email"
              name="username"
              autocomplete="username"
              value={auth.user.email}
              readonly
              tabindex="-1"
              aria-hidden="true"
            />
          {/if}

          <div class="field">
            <label for="newpw-password" class="label">Nouveau mot de passe</label>
            <div class="input-wrap">
              <span class="input-icon"><Icon name="lock" size={18} /></span>
              <input
                bind:this={passwordInput}
                id="newpw-password"
                name="new-password"
                type={showPassword ? 'text' : 'password'}
                autocomplete="new-password"
                autocapitalize="off"
                spellcheck="false"
                class="input input-has-icon input-has-toggle"
                class:error={pwError != null}
                aria-invalid={pwError != null}
                aria-describedby="newpw-strength newpw-password-msg"
                placeholder="{PW_MIN} caractères minimum"
                bind:value={password}
                oninput={() => { pwError = null; apiError = null }}
              />
              <button
                type="button"
                class="eye-btn"
                aria-label={showPassword ? 'Masquer les mots de passe' : 'Afficher les mots de passe'}
                aria-pressed={showPassword}
                aria-controls="newpw-password newpw-confirm"
                onclick={() => (showPassword = !showPassword)}
              >
                <Icon name={showPassword ? 'eye-off' : 'eye'} size={20} />
              </button>
            </div>
            <div id="newpw-strength" class="strength" aria-live="polite">
              {#if strength}
                <div class="strength-bar" data-level={strength.level} aria-hidden="true">
                  <span></span><span></span><span></span>
                </div>
                <span class="strength-label" data-level={strength.level}>{strength.label}</span>
              {:else}
                <span class="strength-hint">Astuce : une phrase courte est plus facile à retenir et plus solide.</span>
              {/if}
            </div>
            <p id="newpw-password-msg" class="field-msg" aria-live="polite">{pwError ?? ''}</p>
          </div>

          <div class="field">
            <label for="newpw-confirm" class="label">Confirmer le mot de passe</label>
            <div class="input-wrap">
              <span class="input-icon"><Icon name="lock" size={18} /></span>
              <input
                bind:this={confirmInput}
                id="newpw-confirm"
                name="confirm-password"
                type={showPassword ? 'text' : 'password'}
                autocomplete="new-password"
                autocapitalize="off"
                spellcheck="false"
                class="input input-has-icon"
                class:error={confirmError != null}
                aria-invalid={confirmError != null}
                aria-describedby="newpw-match newpw-confirm-msg"
                placeholder="Retape le mot de passe"
                bind:value={confirm}
                oninput={() => { confirmError = null; apiError = null }}
              />
            </div>
            <p id="newpw-match" class="match" aria-live="polite">
              {#if passwordsMatch}
                <span class="match-ok"><Icon name="check" size={14} /> Les mots de passe correspondent</span>
              {:else if passwordsDiffer && !confirmError}
                <span class="match-ko">Pas encore identiques</span>
              {/if}
            </p>
            <p id="newpw-confirm-msg" class="field-msg" aria-live="polite">{confirmError ?? ''}</p>
          </div>

          {#if apiError}
            <p class="error-msg" role="alert">{apiError}</p>
          {/if}

          <button type="submit" class="btn btn-primary long btn-main" disabled={saving} aria-busy={saving}>
            {#if saving}
              <span class="btn-spinner" aria-hidden="true"></span>
              Enregistrement…
            {:else}
              <Icon name="key" size={18} /> Enregistrer le mot de passe
            {/if}
          </button>
        </form>
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

  .account { color: var(--text); font-weight: var(--fw-bold); }

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

  .strength {
    display: flex;
    align-items: center;
    gap: var(--sp-3);
    min-height: 20px;
    margin-top: var(--sp-2);
    font-size: var(--fs-sm);
  }

  .strength-bar {
    display: flex;
    gap: 3px;
    flex: 0 0 96px;
  }

  .strength-bar span {
    flex: 1;
    height: 10px;
    border: var(--line-thin) solid var(--line);
    background: var(--surface-sunken);
  }

  .strength-bar[data-level='0'] span:nth-child(1) { background: var(--error); }
  .strength-bar[data-level='1'] span:nth-child(1) { background: var(--accent); }
  .strength-bar[data-level='2'] span:nth-child(-n + 2) { background: var(--accent); }
  .strength-bar[data-level='3'] span { background: var(--success); }

  .strength-label { font-weight: var(--fw-bold); color: var(--text); }
  .strength-label[data-level='0'] { color: var(--error); }
  .strength-label[data-level='3'] { color: var(--success); }

  .strength-hint { color: var(--text-secondary); line-height: 1.4; }

  .match {
    font-size: var(--fs-sm);
    line-height: 1.4;
  }
  .match:not(:empty) { margin-top: var(--sp-2); }

  .match-ok {
    display: inline-flex;
    align-items: center;
    gap: var(--sp-1);
    color: var(--success);
    font-weight: var(--fw-bold);
  }

  .match-ko { color: var(--text-secondary); }

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

  .big-spinner {
    width: 36px;
    height: 36px;
    border: 4px solid var(--line);
    border-top-color: transparent;
    animation: spin 0.8s linear infinite;
    margin: var(--sp-2) 0 var(--sp-4);
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
  .status-icon[data-tone='error'] { background: var(--error-bg); color: var(--error); }
  .status-icon[data-tone='success'] { background: var(--success-bg); color: var(--success); }

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
    .eye-btn:hover { color: var(--text); background: var(--surface-hover); }
    .text-link:not(:disabled):hover { background: var(--highlight); }
  }
</style>
