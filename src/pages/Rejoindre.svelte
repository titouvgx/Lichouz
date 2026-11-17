<script lang="ts">
  // #/rejoindre/<jeton> : création de compte par lien d'invitation (sans être connecté).
  // Le jeton (router.token) n'est jamais affiché ni journalisé.
  import { onDestroy, tick, untrack } from 'svelte'
  import Icon from '../components/Icon.svelte'
  import { auth } from '../lib/auth.svelte'
  import { router, navigate, href } from '../lib/router.svelte'
  import { toast } from '../lib/toast.svelte'
  import { VERSION_LABEL } from '../lib/version'
  import {
    acceptInvitation,
    resendConfirmation,
    invitationInfo,
    matchesEmailHint,
    INVITATION_DAYS,
    type InvitationInfo,
  } from '../lib/api/famille'

  const NAME_MAX = 40
  const FAMILY_MAX = 60
  const PW_MIN = 10
  const PW_MAX_BYTES = 72 // limite de Supabase Auth (bcrypt)
  const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/
  const OFFLINE_MSG = 'Pas de connexion internet. Vérifie ton réseau, puis réessaie.'

  type Field = 'name' | 'email' | 'password' | 'confirm' | 'family'
  type BadStatus = Exclude<InvitationInfo['status'], 'valide'>

  const STATUS_TEXT: Record<BadStatus, { title: string; text: string }> = {
    inconnue: {
      title: 'Lien d’invitation introuvable',
      text: 'Ce lien ne correspond à aucune invitation. Vérifie que tu l’as ouvert en entier, ou demande un nouveau lien à la personne qui t’a invité.',
    },
    expiree: {
      title: 'Ce lien a expiré',
      text: `Un lien d’invitation n’est valable que ${INVITATION_DAYS} jours. Demande un nouveau lien à la personne qui t’a invité.`,
    },
    utilisee: {
      title: 'Ce lien a déjà servi',
      text: 'Chaque lien ne sert qu’une fois. Si le compte créé est le tien, connecte-toi. Sinon, demande un nouveau lien à la personne qui t’a invité.',
    },
    annulee: {
      title: 'Ce lien a été annulé',
      text: 'La personne qui l’a créé l’a annulé. Demande-lui un nouveau lien.',
    },
  }

  // ── Lecture du lien ──
  let loadState = $state<'loading' | 'ready' | 'network'>('loading')
  let info = $state<InvitationInfo | null>(null)
  let loadSeq = 0

  async function load(token: string | null) {
    const seq = ++loadSeq
    if (!token) {
      info = { status: 'inconnue', kind: null, role: null, family_name: null, email_hint: null }
      loadState = 'ready'
      return
    }
    loadState = 'loading'
    try {
      const res = await invitationInfo(token)
      if (seq !== loadSeq) return
      info = res
      loadState = 'ready'
    } catch {
      if (seq !== loadSeq) return
      loadState = 'network'
    }
  }

  $effect(() => {
    const token = router.token
    untrack(() => load(token))
  })

  const isFounder = $derived(info?.kind === 'fondateur')
  const badStatus = $derived<BadStatus | null>(info && info.status !== 'valide' ? info.status : null)

  // ── Formulaire ──
  let step = $state<1 | 2>(1)
  let displayName = $state('')
  let email = $state('')
  let password = $state('')
  let confirm = $state('')
  let familyName = $state('')
  let showPassword = $state(false)

  let submitting = $state(false)
  let apiError = $state<string | null>(null)
  let errors = $state<Partial<Record<Field, string>>>({})
  /** Message de bienvenue après la création (le compte est alors connecté). */
  let welcome = $state<string | null>(null)
  /** Compte créé, adresse à confirmer : l'adresse à laquelle l'e-mail est parti. */
  let checkMail = $state<string | null>(null)
  let resending = $state(false)
  let resendMsg = $state<{ tone: 'ok' | 'error'; text: string } | null>(null)
  let resendCooldown = $state(0)
  let cooldownTimer: ReturnType<typeof setInterval> | undefined

  function startCooldown() {
    resendCooldown = 60
    clearInterval(cooldownTimer)
    cooldownTimer = setInterval(() => {
      resendCooldown -= 1
      if (resendCooldown <= 0) clearInterval(cooldownTimer)
    }, 1000)
  }

  async function handleResend() {
    if (!checkMail || resending || resendCooldown > 0) return
    if (!navigator.onLine) {
      resendMsg = { tone: 'error', text: OFFLINE_MSG }
      return
    }
    resending = true
    resendMsg = null
    try {
      await resendConfirmation(checkMail)
      resendMsg = { tone: 'ok', text: 'C’est renvoyé. Regarde aussi dans les spams.' }
      startCooldown()
    } catch (err) {
      resendMsg = { tone: 'error', text: err instanceof Error ? err.message : 'L’e-mail n’a pas pu être envoyé.' }
    }
    resending = false
  }
  let redirectTimer: ReturnType<typeof setTimeout> | undefined

  let titleEl: HTMLHeadingElement | undefined = $state()
  let nameInput: HTMLInputElement | undefined = $state()
  let emailInput: HTMLInputElement | undefined = $state()
  let passwordInput: HTMLInputElement | undefined = $state()
  let confirmInput: HTMLInputElement | undefined = $state()
  let familyInput: HTMLInputElement | undefined = $state()

  // Un compte déjà ouvert sur ce téléphone (pas celui qu'on vient de créer)
  const alreadyConnected = $derived(auth.user != null && !submitting && welcome == null && checkMail == null)

  onDestroy(() => {
    clearTimeout(redirectTimer)
    clearInterval(cooldownTimer)
  })

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

  function clearError(f: Field) {
    if (errors[f]) errors[f] = undefined
    apiError = null
  }

  function focusField(f: Field) {
    const el = { name: nameInput, email: emailInput, password: passwordInput, confirm: confirmInput, family: familyInput }[f]
    el?.focus()
  }

  /** Vérifie l'étape « Ton compte ». Renvoie le premier champ en erreur. */
  function validateAccount(): Field | null {
    const e: Partial<Record<Field, string>> = {}
    const n = displayName.trim()
    if (!n) e.name = 'Indique ton prénom.'
    else if (n.length > NAME_MAX) e.name = `${NAME_MAX} caractères maximum.`

    const m = email.trim()
    if (!m) e.email = 'Indique ton adresse e-mail.'
    else if (!EMAIL_RE.test(m)) e.email = 'Cette adresse e-mail ne semble pas complète (ex. prenom@exemple.fr).'
    else if (!matchesEmailHint(m, info?.email_hint ?? null)) {
      e.email = `Ce lien est réservé à l’adresse ${info?.email_hint}. Utilise celle-là, ou demande un nouveau lien.`
    }

    if (!password) e.password = 'Choisis un mot de passe.'
    else if (password.length < PW_MIN) e.password = `Le mot de passe doit faire au moins ${PW_MIN} caractères.`
    else if (new TextEncoder().encode(password).length > PW_MAX_BYTES) e.password = 'Ce mot de passe est trop long (72 caractères maximum).'

    if (!confirm) e.confirm = 'Retape le mot de passe pour le confirmer.'
    else if (confirm !== password) e.confirm = 'Les deux mots de passe ne correspondent pas.'

    errors = { ...e, family: errors.family }
    const order: Field[] = ['name', 'email', 'password', 'confirm']
    return order.find((f) => e[f]) ?? null
  }

  function validateFamily(): boolean {
    const f = familyName.trim()
    let msg: string | undefined
    if (!f) msg = 'Donne un nom à ta famille.'
    else if (f.length < 2) msg = 'Ce nom est un peu court (2 caractères minimum).'
    else if (f.length > FAMILY_MAX) msg = `${FAMILY_MAX} caractères maximum.`
    errors = { ...errors, family: msg }
    return !msg
  }

  async function goToStep(n: 1 | 2) {
    step = n
    await tick()
    if (n === 2) familyInput?.focus()
    else titleEl?.focus()
  }

  async function handleSubmit(e: SubmitEvent) {
    e.preventDefault()
    if (submitting) return
    apiError = null

    const bad = validateAccount()
    if (bad) {
      if (step !== 1) {
        step = 1
        await tick()
      }
      focusField(bad)
      return
    }

    // Fondateur : l'étape 1 ne fait que passer à l'étape 2 (rien n'est créé)
    if (isFounder && step === 1) {
      await goToStep(2)
      return
    }
    if (isFounder && !validateFamily()) {
      familyInput?.focus()
      return
    }

    const token = router.token
    if (!token) {
      info = { status: 'inconnue', kind: null, role: null, family_name: null, email_hint: null }
      return
    }
    if (!navigator.onLine) {
      apiError = OFFLINE_MSG
      return
    }

    const firstName = displayName.trim()
    submitting = true
    try {
      const result = await acceptInvitation({
        token,
        email: email.trim(),
        password,
        display_name: firstName,
        ...(isFounder ? { family_name: familyName.trim() } : {}),
      })
      if (result === 'a_confirmer') {
        checkMail = email.trim().toLowerCase()
        submitting = false
        password = ''
        confirm = ''
        startCooldown() // l'e-mail vient de partir : pas de renvoi avant une minute
        return
      }
      // welcome avant submitting = false : la session vient de s'ouvrir, il ne
      // faut pas afficher « un compte est déjà ouvert sur ce téléphone »
      welcome = isFounder
        ? `Bienvenue ${firstName} ! Ta famille « ${familyName.trim()} » est prête.`
        : `Bienvenue ${firstName} ! Ton compte est prêt.`
      submitting = false
      password = ''
      confirm = ''
      redirectTimer = setTimeout(() => navigate('accueil'), 1800)
    } catch (err) {
      submitting = false
      const message = err instanceof Error && err.message
        ? err.message
        : 'Le compte n’a pas pu être créé. Réessaie dans un instant.'
      // Compte créé mais connexion automatique ratée : on passe par la connexion
      if (message.startsWith('Compte créé')) {
        toast.success(message)
        navigate('login')
        return
      }
      apiError = message
      // Erreur qui porte sur l'étape 1 (adresse déjà prise, mot de passe refusé…)
      if (isFounder && step === 2 && /e-mail|adresse|mot de passe|prénom/i.test(message)) {
        step = 1
      }
    }
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

    <section class="auth-card card" aria-labelledby="join-title">
      {#if checkMail}
        <div class="status" role="status">
          <span class="status-icon" data-tone="info"><Icon name="mail" size={28} /></span>
          <h2 id="join-title">Vérifie ta boîte mail</h2>
          <p class="status-text">
            Ton compte est créé. On vient d’envoyer un lien à <strong class="mail-addr">{checkMail}</strong> :
            ouvre-le pour confirmer que l’adresse est bien à toi. Tu pourras ensuite te connecter.
          </p>
          <p class="status-text small">Rien reçu ? Regarde dans les spams. Le lien est valable 1 heure.</p>
          {#if resendMsg}
            <p class="resend-msg" data-tone={resendMsg.tone} role={resendMsg.tone === 'error' ? 'alert' : 'status'}>{resendMsg.text}</p>
          {/if}
          <div class="actions">
            <button
              type="button"
              class="btn btn-resend btn-main"
              disabled={resending || resendCooldown > 0}
              aria-busy={resending}
              onclick={handleResend}
            >
              <Icon name="refresh" size={18} />
              {resendCooldown > 0 ? `Renvoyer l’e-mail (${resendCooldown} s)` : 'Renvoyer l’e-mail'}
            </button>
            <a class="text-link" href={href('login')}>J’ai confirmé : me connecter</a>
          </div>
        </div>
      {:else if welcome}
        <div class="status" role="status">
          <span class="status-icon" data-tone="success"><Icon name="check-circle" size={28} /></span>
          <h2 id="join-title">{welcome}</h2>
          <p class="status-text">On t’emmène à l’accueil…</p>
          <div class="actions">
            <a class="text-link" href={href('accueil')}>Aller à l’accueil maintenant</a>
          </div>
        </div>
      {:else if alreadyConnected}
        <div class="status">
          <span class="status-icon" data-tone="info"><Icon name="user" size={28} /></span>
          <h2 id="join-title">Tu es déjà connecté</h2>
          <p class="status-text">
            Un compte est déjà ouvert sur ce téléphone, et une personne n’a qu’une famille.
            Ce lien sert à créer le compte de quelqu’un d’autre : transmets-le à la personne
            invitée pour qu’elle l’ouvre sur son propre téléphone.
          </p>
          <div class="actions">
            <a class="btn btn-primary btn-main" href={href('accueil')}>
              <Icon name="home" size={18} /> Aller à l’accueil
            </a>
          </div>
        </div>
      {:else if auth.loading || loadState === 'loading'}
        <div class="status" role="status">
          <span class="big-spinner" aria-hidden="true"></span>
          <h2 id="join-title">Vérification du lien…</h2>
        </div>
      {:else if loadState === 'network'}
        <div class="status">
          <span class="status-icon" data-tone="error"><Icon name="alert-circle" size={28} /></span>
          <h2 id="join-title">Impossible de vérifier ce lien</h2>
          <p class="status-text" role="alert">
            Vérifie ta connexion internet, puis réessaie.
          </p>
          <div class="actions">
            <button type="button" class="btn btn-primary btn-main" onclick={() => load(router.token)}>
              <Icon name="refresh" size={18} /> Réessayer
            </button>
            <a class="text-link" href={href('login')}>Aller à la connexion</a>
          </div>
        </div>
      {:else if badStatus}
        <div class="status">
          <span class="status-icon" data-tone="error"><Icon name="alert-circle" size={28} /></span>
          <h2 id="join-title">{STATUS_TEXT[badStatus].title}</h2>
          <p class="status-text">{STATUS_TEXT[badStatus].text}</p>
          <div class="actions">
            <a class="btn btn-primary btn-main" href={href('login')}>Aller à la connexion</a>
          </div>
        </div>
      {:else}
        {#if isFounder}
          <h2 id="join-title" tabindex="-1" bind:this={titleEl}>
            {step === 1 ? 'Crée ton compte' : 'Crée ta famille'}
          </h2>
          <p class="lead">
            {step === 1
              ? 'Tu es invité à fonder ta famille sur Lichouz. D’abord ton compte, puis ta famille.'
              : 'Dernière étape : le nom de ta famille.'}
          </p>
          <ol class="steps" aria-label="Étapes">
            <li class:active={step === 1} class:done={step === 2} aria-current={step === 1 ? 'step' : undefined}>
              <span class="step-num" aria-hidden="true">
                {#if step === 2}<Icon name="check" size={14} strokeWidth={3} />{:else}1{/if}
              </span>
              <span class="step-label">Ton compte{#if step === 2}<span class="sr-only"> (terminé)</span>{/if}</span>
            </li>
            <li class:active={step === 2} aria-current={step === 2 ? 'step' : undefined}>
              <span class="step-num" aria-hidden="true">2</span>
              <span class="step-label">Ta famille</span>
            </li>
          </ol>
        {:else}
          <h2 id="join-title" tabindex="-1" bind:this={titleEl}>
            {info?.family_name ? `Rejoins « ${info.family_name} »` : 'Rejoins ta famille'}
          </h2>
          <p class="lead">
            Tu es invité {info?.role === 'admin' ? 'en tant qu’admin' : 'en tant que membre'}.
            Crée ton compte pour commencer.
          </p>
        {/if}

        {#if info?.email_hint}
          <p class="lead reserved">Ce lien est réservé à l’adresse <strong>{info.email_hint}</strong>.</p>
        {/if}

        <form onsubmit={handleSubmit} novalidate>
          <!-- Étape 1 (gardée dans la page à l'étape 2 : saisie conservée, et le
               gestionnaire de mots de passe voit l'e-mail et le mot de passe à l'envoi) -->
          <div class="group" hidden={step !== 1}>
            <div class="field">
              <label for="join-name" class="label">Prénom</label>
              <div class="input-wrap">
                <span class="input-icon"><Icon name="user" size={18} /></span>
                <input
                  bind:this={nameInput}
                  id="join-name"
                  name="given-name"
                  type="text"
                  autocomplete="given-name"
                  autocapitalize="words"
                  maxlength={NAME_MAX}
                  class="input input-has-icon"
                  class:error={!!errors.name}
                  aria-invalid={!!errors.name}
                  aria-describedby="join-name-msg"
                  placeholder="Ton prénom"
                  bind:value={displayName}
                  oninput={() => clearError('name')}
                />
              </div>
              <p id="join-name-msg" class="field-msg" aria-live="polite">{errors.name ?? ''}</p>
            </div>

            <div class="field">
              <label for="join-email" class="label">Adresse e-mail</label>
              <div class="input-wrap">
                <span class="input-icon"><Icon name="mail" size={18} /></span>
                <input
                  bind:this={emailInput}
                  id="join-email"
                  name="email"
                  type="email"
                  inputmode="email"
                  autocomplete="email"
                  autocapitalize="off"
                  spellcheck="false"
                  class="input input-has-icon"
                  class:error={!!errors.email}
                  aria-invalid={!!errors.email}
                  aria-describedby="join-email-msg"
                  placeholder="prenom@exemple.fr"
                  bind:value={email}
                  oninput={() => clearError('email')}
                />
              </div>
              <p id="join-email-msg" class="field-msg" aria-live="polite">{errors.email ?? ''}</p>
            </div>

            <div class="field">
              <label for="join-password" class="label">Mot de passe</label>
              <div class="input-wrap">
                <span class="input-icon"><Icon name="lock" size={18} /></span>
                <input
                  bind:this={passwordInput}
                  id="join-password"
                  name="new-password"
                  type={showPassword ? 'text' : 'password'}
                  autocomplete="new-password"
                  autocapitalize="off"
                  spellcheck="false"
                  class="input input-has-icon input-has-toggle"
                  class:error={!!errors.password}
                  aria-invalid={!!errors.password}
                  aria-describedby="join-pw-strength join-password-msg"
                  placeholder="{PW_MIN} caractères minimum"
                  bind:value={password}
                  oninput={() => clearError('password')}
                />
                <button
                  type="button"
                  class="eye-btn"
                  aria-label={showPassword ? 'Masquer les mots de passe' : 'Afficher les mots de passe'}
                  aria-pressed={showPassword}
                  aria-controls="join-password join-confirm"
                  onclick={() => (showPassword = !showPassword)}
                >
                  <Icon name={showPassword ? 'eye-off' : 'eye'} size={20} />
                </button>
              </div>
              <div id="join-pw-strength" class="strength" aria-live="polite">
                {#if strength}
                  <div class="strength-bar" data-level={strength.level} aria-hidden="true">
                    <span></span><span></span><span></span>
                  </div>
                  <span class="strength-label" data-level={strength.level}>{strength.label}</span>
                {:else}
                  <span class="strength-hint">Astuce : une phrase courte est plus facile à retenir et plus solide.</span>
                {/if}
              </div>
              <p id="join-password-msg" class="field-msg" aria-live="polite">{errors.password ?? ''}</p>
            </div>

            <div class="field">
              <label for="join-confirm" class="label">Confirmer le mot de passe</label>
              <div class="input-wrap">
                <span class="input-icon"><Icon name="lock" size={18} /></span>
                <input
                  bind:this={confirmInput}
                  id="join-confirm"
                  name="confirm-password"
                  type={showPassword ? 'text' : 'password'}
                  autocomplete="new-password"
                  autocapitalize="off"
                  spellcheck="false"
                  class="input input-has-icon"
                  class:error={!!errors.confirm}
                  aria-invalid={!!errors.confirm}
                  aria-describedby="join-match join-confirm-msg"
                  placeholder="Retape le mot de passe"
                  bind:value={confirm}
                  oninput={() => clearError('confirm')}
                />
              </div>
              <p id="join-match" class="match" aria-live="polite">
                {#if passwordsMatch}
                  <span class="match-ok"><Icon name="check" size={14} /> Les mots de passe correspondent</span>
                {:else if passwordsDiffer && !errors.confirm}
                  <span class="match-ko">Pas encore identiques</span>
                {/if}
              </p>
              <p id="join-confirm-msg" class="field-msg" aria-live="polite">{errors.confirm ?? ''}</p>
            </div>
          </div>

          {#if isFounder && step === 2}
            <div class="group">
              <div class="field">
                <label for="join-family" class="label">Nom de ta famille</label>
                <div class="input-wrap">
                  <span class="input-icon"><Icon name="users" size={18} /></span>
                  <input
                    bind:this={familyInput}
                    id="join-family"
                    name="family-name"
                    type="text"
                    autocomplete="off"
                    autocapitalize="words"
                    maxlength={FAMILY_MAX}
                    class="input input-has-icon"
                    class:error={!!errors.family}
                    aria-invalid={!!errors.family}
                    aria-describedby="join-family-help join-family-msg"
                    placeholder="Famille Martin"
                    bind:value={familyName}
                    oninput={() => clearError('family')}
                  />
                </div>
                <p id="join-family-msg" class="field-msg" aria-live="polite">{errors.family ?? ''}</p>
              </div>
              <p id="join-family-help" class="explain">
                Tu en seras le fondateur : tu pourras inviter des gens à la rejoindre,
                et créer jusqu’à 3 familles.
              </p>
            </div>
          {/if}

          {#if apiError}
            <p class="error-msg" role="alert">{apiError}</p>
          {/if}

          <button type="submit" class="btn btn-primary btn-main" disabled={submitting} aria-busy={submitting}>
            {#if submitting}
              <span class="btn-spinner" aria-hidden="true"></span>
              {isFounder ? 'Création en cours…' : 'Création du compte…'}
            {:else if isFounder && step === 1}
              Continuer <Icon name="arrow-right" size={18} />
            {:else if isFounder}
              Créer mon compte et ma famille
            {:else}
              Créer mon compte
            {/if}
          </button>

          {#if isFounder && step === 2}
            <button type="button" class="text-link back-btn" disabled={submitting} onclick={() => goToStep(1)}>
              <Icon name="arrow-left" size={18} /> Retour à mon compte
            </button>
          {/if}
        </form>

        <p class="hint">
          À ta première connexion, on te demandera de choisir un pseudo et d’accepter les
          <a class="inline-link" href={href('cgu')}>conditions</a> et la
          <a class="inline-link" href={href('confidentialite')}>politique de confidentialité</a>.
          Avant 15 ans, un parent devra aussi donner son accord.
        </p>
        <p class="hint">
          Déjà un compte ? <a class="inline-link" href={href('login')}>Connecte-toi</a>
        </p>
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

  /* ── Étapes (fondateur) ── */
  .steps {
    list-style: none;
    margin: 0 0 var(--sp-5);
    padding: 0;
    display: flex;
    align-items: center;
    gap: var(--sp-3);
  }
  .steps li {
    display: flex;
    align-items: center;
    gap: var(--sp-2);
    font-size: var(--fs-sm);
    font-weight: var(--fw-bold);
    text-transform: uppercase;
    letter-spacing: var(--tracking-caps);
    color: var(--text-secondary);
  }
  .steps li + li::before {
    content: '';
    width: 28px;
    height: var(--line-w);
    background: var(--line);
    margin-right: 2px;
  }
  .step-num {
    width: 30px;
    height: 30px;
    display: grid;
    place-items: center;
    font-size: var(--fs-sm);
    font-weight: var(--fw-bold);
    border: var(--line-w) solid var(--line);
    background: var(--surface);
    color: var(--text);
    flex: none;
  }
  .steps li.active { color: var(--text); }
  .steps li.active .step-num { background: var(--accent); color: var(--on-accent); box-shadow: var(--shadow-sm); }
  .steps li.done .step-num { background: var(--success-bg); border-color: var(--success); color: var(--success); }

  form {
    display: flex;
    flex-direction: column;
    gap: var(--sp-4);
  }

  .group {
    display: flex;
    flex-direction: column;
    gap: var(--sp-4);
  }
  .group[hidden] { display: none; }

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

  .explain {
    font-size: var(--fs-sm);
    line-height: 1.5;
    color: var(--text);
    background: var(--highlight);
    border: var(--line-w) solid var(--line);
    padding: var(--sp-3);
  }

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

  .back-btn { align-self: center; margin-top: -6px; }

  .hint {
    margin-top: var(--sp-3);
    font-size: var(--fs-sm);
    line-height: 1.45;
    color: var(--text-secondary);
    text-align: center;
  }

  /* Lien dans une phrase : zone de tap agrandie sans décaler le texte */
  .inline-link {
    display: inline-block;
    padding: 12px 4px;
    margin: -12px -4px;
    color: var(--text);
    font-weight: var(--fw-bold);
    text-decoration: underline;
    text-decoration-thickness: 2px;
    text-underline-offset: 3px;
    touch-action: manipulation;
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
  .status-icon[data-tone='error'] { background: var(--error-bg); color: var(--error); }
  .status-icon[data-tone='success'] { background: var(--success-bg); color: var(--success); }

  .status-text {
    font-size: var(--fs-base);
    line-height: 1.5;
    color: var(--text-secondary);
  }

  .status-text.small { font-size: var(--fs-sm); margin-top: var(--sp-3); }
  .mail-addr { color: var(--text); font-weight: var(--fw-bold); word-break: break-all; }

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
    .inline-link:hover { background: var(--highlight); }
  }
</style>
