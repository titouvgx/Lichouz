<script lang="ts">
  // #/confirmer-email : arrivée depuis l'e-mail « Confirme ton adresse » (v1.3.0).
  // L'adresse est …/?token_hash=…&type=signup#/confirmer-email : on valide le
  // jeton (ce qui confirme l'adresse ET ouvre une session), puis on le retire
  // aussitôt de l'adresse (ni historique, ni partage).
  import { onDestroy, onMount } from 'svelte'
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
      <div class="logo-circle" aria-hidden="true">
        <svg width="32" height="32" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
          <circle cx="9" cy="21" r="1"/><circle cx="20" cy="21" r="1"/>
          <path d="M1 1h4l2.68 13.39a2 2 0 0 0 2 1.61h9.72a2 2 0 0 0 2-1.61L23 6H6"/>
        </svg>
      </div>
      <h1>Lichouz</h1>
    </header>

    <section class="auth-card" aria-labelledby="confirm-title">
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
      calc(24px + env(safe-area-inset-top, 0px))
      calc(var(--gutter) + env(safe-area-inset-right, 0px))
      calc(24px + env(safe-area-inset-bottom, 0px))
      calc(var(--gutter) + env(safe-area-inset-left, 0px));
    animation: page-in 0.3s ease-out;
  }

  .auth-inner {
    width: 100%;
    max-width: 400px;
    display: flex;
    flex-direction: column;
    gap: 24px;
  }

  /* ── En-tête (posé directement sur la photo), comme la connexion ── */
  .brand {
    text-align: center;
    display: flex;
    flex-direction: column;
    align-items: center;
  }

  .logo-circle {
    width: 72px;
    height: 72px;
    border-radius: 22px;
    background: linear-gradient(135deg, var(--primary), color-mix(in srgb, var(--primary) 70%, var(--accent)));
    display: inline-flex;
    align-items: center;
    justify-content: center;
    box-shadow: 0 8px 28px rgba(0, 0, 0, 0.35);
    color: var(--on-primary);
    margin-bottom: 18px;
  }

  h1 {
    font-family: var(--font-display);
    font-size: 30px;
    line-height: 1.1;
    color: var(--text);
    letter-spacing: -0.01em;
    text-shadow: 0 2px 14px rgba(0, 0, 0, 0.45);
  }

  /* ── Carte (pas de backdrop-filter : la photo derrière bouge) ── */
  .auth-card {
    background: rgba(9, 24, 50, 0.86);
    border: 1px solid var(--border-strong);
    border-radius: var(--radius-xl);
    padding: 24px 20px 20px;
    box-shadow: 0 16px 48px rgba(0, 0, 0, 0.38);
  }

  h2 {
    font-family: var(--font-display);
    font-size: 20px;
    line-height: 1.25;
    color: var(--text);
    margin-bottom: 18px;
  }


  /* ── Solidité du mot de passe (comme Mon compte) ── */
  .btn-main {
    margin-top: 4px;
    min-height: 52px;
    font-size: 16px;
    touch-action: manipulation;
  }

  .btn-main:disabled { opacity: 0.85; cursor: progress; }


  .text-link {
    display: inline-flex;
    align-items: center;
    justify-content: center;
    gap: 6px;
    min-height: 44px;
    padding: 0 12px;
    border-radius: var(--radius-sm);
    color: var(--primary);
    font-size: 15px;
    font-weight: 600;
    touch-action: manipulation;
  }

  .text-link:focus-visible {
    outline: 2px solid var(--primary);
    outline-offset: 2px;
  }

  /* ── États (vérification, lien invalide, succès) ── */
  .status {
    display: flex;
    flex-direction: column;
    align-items: center;
    text-align: center;
    padding: 8px 0 4px;
  }

  .status h2 { margin-bottom: 8px; }

  .status-icon {
    width: 56px;
    height: 56px;
    border-radius: 50%;
    display: inline-flex;
    align-items: center;
    justify-content: center;
    margin-bottom: 14px;
  }

  .status-icon[data-tone='error'] { background: var(--error-bg); color: #FF9A9D; }
  .status-icon[data-tone='success'] { background: var(--success-bg); color: var(--success); }

  .status-text {
    font-size: 15px;
    line-height: 1.5;
    color: var(--text-secondary);
  }

  .actions {
    margin-top: 20px;
    width: 100%;
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 8px;
  }

  .big-spinner {
    width: 36px;
    height: 36px;
    border: 3px solid var(--border-strong);
    border-top-color: var(--primary);
    border-radius: 50%;
    animation: spin 0.8s linear infinite;
    margin: 8px 0 18px;
  }

  @keyframes spin {
    to { transform: rotate(360deg); }
  }

  .app-version {
    margin: 0;
    text-align: center;
    font-size: 12px;
    color: var(--text-secondary);
    opacity: 0.8;
    font-variant-numeric: tabular-nums;
  }

  @media (hover: hover) and (pointer: fine) {
    .text-link:hover { background: var(--surface); }
  }

  @media (max-height: 640px) {
    .auth-inner { gap: 16px; }
    .logo-circle { width: 56px; height: 56px; border-radius: 18px; margin-bottom: 12px; }
    h1 { font-size: 26px; }
  }
</style>
