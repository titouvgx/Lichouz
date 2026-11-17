<script lang="ts">
  // #/confirmer-email : arrivée depuis l'e-mail « Confirme ton adresse » (v1.3.0).
  // L'adresse est …/?token_hash=…&type=signup#/confirmer-email : on valide le
  // jeton (ce qui confirme l'adresse ET ouvre une session), puis on le retire
  // aussitôt de l'adresse (ni historique, ni partage).
  import { onDestroy, onMount } from 'svelte'
  import CatLogo from '../components/CatLogo.svelte'
  import Icon from '../components/Icon.svelte'
  import { auth } from '../lib/auth.svelte'
  import { navigate, href } from '../lib/router.svelte'
  import { VERSION_LABEL } from '../lib/version'
  import { verifySignupLink } from '../lib/api/famille'

  const OFFLINE_MSG = 'Pas de connexion internet. Vérifie ton réseau, puis réessaie.'

  const initialHash = new URLSearchParams(window.location.search).get('token_hash')
  /** Jeton gardé en mémoire seulement (pour « Réessayer » sans réseau), jamais affiché. */
  let pendingHash: string | null = initialHash
  let verifying = $state(initialHash != null)
  let verified = $state(false)
  let linkError = $state<{ message: string; canRetry: boolean } | null>(null)
  let redirectTimer: ReturnType<typeof setTimeout> | undefined

  onDestroy(() => clearTimeout(redirectTimer))

  function cleanUrl() {
    history.replaceState(history.state, '', `${window.location.pathname}${href('confirmer-email')}`)
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
    const pending = verifySignupLink(pendingHash)
    if (clean) cleanUrl()
    try {
      await pending
      pendingHash = null
      verified = true
      redirectTimer = setTimeout(() => navigate('accueil'), 2200)
    } catch (err) {
      if (!navigator.onLine) {
        linkError = { message: OFFLINE_MSG, canRetry: true }
      } else {
        pendingHash = null
        linkError = {
          message: err instanceof Error && err.message
            ? err.message
            : 'Ce lien a expiré ou a déjà servi.',
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

  const view = $derived.by(() => {
    if (verifying || (verified && !auth.user)) return 'loading' as const
    if (verified) return 'done' as const
    if (linkError) return 'link-error' as const
    return 'invalid' as const
  })
</script>

<main class="auth-page">
  <div class="auth-inner">
    <header class="brand">
      <div class="logo-box" aria-hidden="true">
        <CatLogo size={46} />
      </div>
      <h1>Lichouz</h1>
    </header>

    <section class="auth-card card" aria-labelledby="confirm-title">
      {#if view === 'done'}
        <div class="status" role="status">
          <span class="status-icon" data-tone="success"><Icon name="check-circle" size={28} /></span>
          <h2 id="confirm-title">Adresse confirmée !</h2>
          <p class="status-text">Ton compte est prêt et tu es connecté. On t’emmène à l’accueil…</p>
          <div class="actions">
            <a class="text-link" href={href('accueil')}>Aller à l’accueil maintenant</a>
          </div>
        </div>
      {:else if view === 'loading'}
        <div class="status" role="status">
          <span class="big-spinner" aria-hidden="true"></span>
          <h2 id="confirm-title">Confirmation de ton adresse…</h2>
        </div>
      {:else if view === 'link-error' && linkError}
        <div class="status">
          <span class="status-icon" data-tone="error"><Icon name="alert-circle" size={28} /></span>
          <h2 id="confirm-title">{linkError.canRetry ? 'Impossible de vérifier le lien' : 'Lien expiré'}</h2>
          <p class="status-text" role="alert">{linkError.message}</p>
          <div class="actions">
            {#if linkError.canRetry}
              <button type="button" class="btn btn-primary btn-main" onclick={() => runVerify()}>
                <Icon name="refresh" size={18} /> Réessayer
              </button>
            {:else}
              <a class="btn btn-primary btn-main" href={href('login')}>Aller à la connexion</a>
            {/if}
          </div>
        </div>
      {:else}
        <div class="status">
          <span class="status-icon" data-tone="error"><Icon name="alert-circle" size={28} /></span>
          <h2 id="confirm-title">Lien invalide</h2>
          <p class="status-text">
            Ce lien est incomplet. Ouvre directement le lien reçu par e-mail, ou connecte-toi :
            l’appli te proposera de renvoyer l’e-mail de confirmation.
          </p>
          <div class="actions">
            <a class="btn btn-primary btn-main" href={href('login')}>Aller à la connexion</a>
          </div>
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

  .btn-main {
    width: 100%;
    margin-top: var(--sp-1);
    min-height: 52px;
    font-size: var(--fs-base);
  }
  .btn-main:disabled { opacity: 0.7; cursor: progress; }

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
    .text-link:not(:disabled):hover { background: var(--highlight); }
  }
</style>
