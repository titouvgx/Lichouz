<script lang="ts">
  // Fenêtre « Inviter » : crée un lien d'invitation à usage unique.
  //   Étape 1 : rôle (invitation « membre ») + « Pour qui ? » (facultatif)
  //   Étape 2 : le lien, à copier ou partager TOUT DE SUITE
  // Le jeton n'est renvoyé qu'à la création (la base ne garde que son empreinte) :
  // une fois la fenêtre fermée, le lien ne peut plus être réaffiché.
  import { onMount, onDestroy, tick } from 'svelte'
  import Icon from './Icon.svelte'
  import { toast } from '../lib/toast.svelte'
  import { createInvitation, INVITATION_DAYS, type NewInvitation } from '../lib/api/famille'

  interface Props {
    kind: 'fondateur' | 'membre'
    /** Famille où inviter (obligatoire pour kind = 'membre') */
    familyId?: string
    familyName?: string
    onclose: () => void
    /** Un lien vient d'être créé : recharger la liste des liens */
    oncreated?: () => void
  }
  let { kind, familyId, familyName, onclose, oncreated }: Props = $props()

  const LABEL_MAX = 60

  let step = $state<'choix' | 'lien'>('choix')
  let role = $state<'member' | 'admin'>('member')
  let label = $state('')
  // v1.7.0 : adresse facultative ; si remplie, seule elle pourra créer le compte
  let email = $state('')
  const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/
  const emailInvalid = $derived(email.trim() !== '' && (email.trim().length > 254 || !EMAIL_RE.test(email.trim())))
  let busy = $state(false)
  let error = $state<string | null>(null)
  let invitation = $state<NewInvitation | null>(null)
  /** Lien copié ou partagé au moins une fois */
  let sent = $state(false)
  let copied = $state(false)
  let copiedTimer: ReturnType<typeof setTimeout> | undefined

  let dialogEl: HTMLDivElement | undefined = $state()
  let linkEl: HTMLInputElement | undefined = $state()
  let copyBtn: HTMLButtonElement | undefined = $state()

  const canShare = typeof navigator !== 'undefined' && typeof navigator.share === 'function'

  onMount(() => {
    document.body.style.overflow = 'hidden'
    dialogEl?.focus()
  })
  onDestroy(() => {
    document.body.style.overflow = ''
    clearTimeout(copiedTimer)
  })

  const title = $derived(
    step === 'lien'
      ? 'Ton lien est prêt'
      : kind === 'fondateur'
        ? 'Inviter un fondateur'
        : familyName
          ? `Inviter dans ${familyName}`
          : 'Inviter quelqu’un',
  )

  const expiresLabel = $derived(
    invitation
      ? new Date(invitation.expires_at).toLocaleDateString('fr-FR', { weekday: 'long', day: 'numeric', month: 'long' })
      : '',
  )

  const shareText = $derived(invitation ? `Rejoins-moi sur Lichouz : ${invitation.url}` : '')

  function messageOf(e: unknown, fallback: string): string {
    const m = (e as { message?: unknown } | null)?.message
    if (typeof m !== 'string' || !m.trim()) return fallback
    if (/failed to fetch|network|load failed/i.test(m)) return 'Pas de réseau : réessaie quand tu seras connecté.'
    return m
  }

  async function create() {
    if (busy) return
    if (kind === 'membre' && !familyId) {
      error = 'Famille introuvable : ferme la fenêtre et réessaie.'
      return
    }
    if (emailInvalid) {
      error = 'Cette adresse e-mail ne semble pas complète (ex. prenom@exemple.fr), ou laisse le champ vide.'
      return
    }
    busy = true
    error = null
    try {
      invitation = await createInvitation(kind, {
        familyId: kind === 'membre' ? familyId : undefined,
        role: kind === 'membre' ? role : undefined,
        label: label.trim() || undefined,
        email: email.trim() || undefined,
      })
      step = 'lien'
      oncreated?.()
      await tick()
      copyBtn?.focus()
    } catch (e) {
      error = messageOf(e, 'Le lien n’a pas pu être créé. Réessaie dans un instant.')
    } finally {
      busy = false
    }
  }

  /** Copie avec repli (anciens navigateurs, contexte non sécurisé). */
  async function writeClipboard(text: string): Promise<boolean> {
    try {
      if (navigator.clipboard?.writeText) {
        await navigator.clipboard.writeText(text)
        return true
      }
    } catch {
      // refusé : on tente le repli
    }
    try {
      linkEl?.focus()
      linkEl?.select()
      linkEl?.setSelectionRange(0, linkEl.value.length)
      const doc = document as Document & { execCommand?: (cmd: string) => boolean }
      return !!doc.execCommand?.('copy')
    } catch {
      return false
    }
  }

  async function copy() {
    if (!invitation) return
    const ok = await writeClipboard(invitation.url)
    if (ok) {
      sent = true
      copied = true
      clearTimeout(copiedTimer)
      copiedTimer = setTimeout(() => (copied = false), 2500)
      toast.success('Lien copié')
    } else {
      // Le lien reste sélectionné dans le champ : copie à la main
      linkEl?.focus()
      linkEl?.select()
      toast.info('Copie impossible ici : sélectionne le lien et copie-le à la main.')
    }
  }

  async function share() {
    if (!invitation) return
    if (!canShare) {
      await copy()
      return
    }
    try {
      await navigator.share({ title: 'Lichouz', text: shareText })
      sent = true
    } catch (e) {
      // Partage annulé par la personne : rien à dire
      if ((e as { name?: string } | null)?.name === 'AbortError') return
      await copy()
    }
  }

  function close() {
    if (busy) return
    onclose()
  }

  // Clic à côté : à l'étape 2, seulement si le lien a déjà été copié ou partagé
  // (sinon un appui de travers ferait perdre le lien pour de bon).
  function onOverlay() {
    if (busy) return
    if (step === 'lien' && !sent) return
    onclose()
  }

  function onKey(e: KeyboardEvent) {
    if (e.key === 'Escape') close()
  }
</script>

<svelte:window onkeydown={onKey} />

<!-- svelte-ignore a11y_click_events_have_key_events -->
<!-- svelte-ignore a11y_no_static_element_interactions -->
<div class="ui-overlay" onclick={onOverlay}>
  <!-- svelte-ignore a11y_click_events_have_key_events -->
  <!-- svelte-ignore a11y_no_static_element_interactions -->
  <div
    class="ui-sheet iv"
    bind:this={dialogEl}
    tabindex="-1"
    role="dialog"
    aria-modal="true"
    aria-labelledby="iv-title"
    aria-describedby="iv-sub"
    onclick={(e) => e.stopPropagation()}
  >
    <header class="ui-head iv-header">
      <div class="iv-titles">
        <h2 id="iv-title">{title}</h2>
        <p id="iv-sub" class="iv-sub">
          {#if step === 'lien'}
            Envoie-le maintenant, par message ou par e-mail.
          {:else if kind === 'fondateur'}
            Un lien pour lancer une nouvelle famille.
          {:else}
            Un lien à envoyer, valable {INVITATION_DAYS} jours.
          {/if}
        </p>
      </div>
      <button class="iv-close" onclick={close} aria-label="Fermer" disabled={busy}>
        <Icon name="x" size={18} strokeWidth={2.5} />
      </button>
    </header>

    <div class="iv-scroll">
      {#if step === 'choix'}
        {#if kind === 'membre'}
          <fieldset class="roles">
            <legend class="field-label">Son rôle</legend>
            <label class="role" class:on={role === 'member'}>
              <input type="radio" name="iv-role" value="member" bind:group={role} disabled={busy} />
              <span class="role-icon" aria-hidden="true"><Icon name="user" size={20} /></span>
              <span class="role-text">
                <span class="role-name">Membre</span>
                <span class="role-desc">Planifie les repas, coche les courses, crée des recettes.</span>
              </span>
              <span class="role-dot" aria-hidden="true"></span>
            </label>
            <label class="role" class:on={role === 'admin'}>
              <input type="radio" name="iv-role" value="admin" bind:group={role} disabled={busy} />
              <span class="role-icon" aria-hidden="true"><Icon name="shield" size={20} /></span>
              <span class="role-text">
                <span class="role-name">Admin</span>
                <span class="role-desc">Peut en plus inviter et gérer les membres de la famille.</span>
              </span>
              <span class="role-dot" aria-hidden="true"></span>
            </label>
          </fieldset>
        {:else}
          <div class="explain">
            <span class="explain-icon" aria-hidden="true"><Icon name="star" size={22} /></span>
            <p>
              La personne crée son compte, puis sa famille. Elle en sera la <strong>fondatrice</strong> :
              elle pourra créer jusqu’à 3 familles et y inviter qui elle veut.
            </p>
          </div>
        {/if}

        <div class="field">
          <label class="field-label" for="iv-label">Pour qui ? <span class="optional">(facultatif)</span></label>
          <input
            id="iv-label"
            class="input"
            type="text"
            placeholder="Ex : Marie"
            maxlength={LABEL_MAX}
            autocomplete="off"
            enterkeyhint="go"
            aria-describedby="iv-label-hint"
            bind:value={label}
            disabled={busy}
            onkeydown={(e) => { if (e.key === 'Enter') { e.preventDefault(); create() } }}
          />
          <p id="iv-label-hint" class="hint">Juste pour toi : pour reconnaître ce lien dans la liste.</p>
        </div>

        <div class="field">
          <label class="field-label" for="iv-email">Son adresse e-mail <span class="optional">(facultatif)</span></label>
          <input
            id="iv-email"
            class="input"
            type="email"
            inputmode="email"
            placeholder="prenom@exemple.fr"
            maxlength="254"
            autocomplete="off"
            autocapitalize="off"
            spellcheck="false"
            enterkeyhint="go"
            aria-describedby="iv-email-hint"
            aria-invalid={emailInvalid}
            bind:value={email}
            disabled={busy}
            onkeydown={(e) => { if (e.key === 'Enter') { e.preventDefault(); create() } }}
          />
          <p id="iv-email-hint" class="hint">
            Si tu la remplis, seule cette adresse pourra créer le compte : un lien transféré ou volé ne servira à rien.
            L’adresse n’est pas gardée, seulement de quoi la reconnaître.
          </p>
        </div>

        {#if error}<p class="iv-error" role="alert">{error}</p>{/if}
      {:else if invitation}
        <div class="field">
          <label class="field-label" for="iv-link">Lien d’invitation</label>
          <div class="link-box">
            <span class="link-icon" aria-hidden="true"><Icon name="link" size={18} /></span>
            <input
              id="iv-link"
              class="input link-input"
              type="text"
              readonly
              value={invitation.url}
              bind:this={linkEl}
              onfocus={(e) => e.currentTarget.select()}
            />
          </div>
          {#if email.trim()}
            <p class="hint">Réservé à {email.trim().toLowerCase()} : envoie-le à cette adresse.</p>
          {/if}
        </div>

        <div class="link-actions">
          <button class="btn act act-copy" class:done={copied} bind:this={copyBtn} onclick={copy}>
            <Icon name={copied ? 'check' : 'copy'} size={18} />
            {copied ? 'Copié' : 'Copier'}
          </button>
          <button class="btn act act-share" onclick={share}>
            <Icon name="share" size={18} /> Partager
          </button>
        </div>

        <div class="notice" role="note">
          <Icon name="clock" size={18} />
          <p>
            Valable {INVITATION_DAYS} jours, une seule fois. Il ne sera plus affiché ensuite :
            partage-le maintenant.
            <span class="notice-date">Expire le {expiresLabel}.</span>
          </p>
        </div>
      {/if}
    </div>

    <div class="iv-actions">
      {#if step === 'choix'}
        <button class="btn btn-primary" onclick={create} disabled={busy} aria-busy={busy}>
          <Icon name="link" size={18} />
          {busy ? 'Création…' : 'Créer le lien'}
        </button>
      {:else}
        <button class="btn btn-outline btn-done" onclick={close}>Terminer</button>
      {/if}
    </div>
  </div>
</div>

<style>
  /* Fenêtre : voile, feuille et animation viennent de app.css (.ui-overlay, .ui-sheet, .ui-head).
     Ici, la mise en page interne (en-tête fixe, zone qui défile, bas fixe). */
  .iv {
    display: flex;
    flex-direction: column;
    max-height: min(88svh, 720px);
    padding: 0;
    overflow: hidden;
  }

  /* ── En-tête ── */
  .iv-header {
    margin: 0;
    padding: var(--sp-4) var(--gutter) var(--sp-3);
  }

  .iv-titles { min-width: 0; }
  .iv-header h2 { color: var(--text); overflow-wrap: anywhere; }
  .iv-sub { margin-top: 2px; font-size: var(--fs-sm); color: var(--text-secondary); }

  .iv-close {
    flex-shrink: 0;
    width: 44px;
    height: 44px;
    margin: -4px -4px 0 0;
    border: var(--line-w) solid var(--line);
    background: var(--surface);
    color: var(--text);
    box-shadow: var(--shadow-sm);
    display: flex;
    align-items: center;
    justify-content: center;
    cursor: pointer;
    touch-action: manipulation;
    transition: transform var(--dur-fast) var(--ease-out);
  }
  .iv-close:active:not(:disabled) { transform: translate(var(--press), var(--press)); box-shadow: none; }
  .iv-close:disabled { opacity: 0.5; }

  .iv-scroll {
    flex: 1;
    min-height: 0;
    overflow-y: auto;
    overscroll-behavior: contain;
    -webkit-overflow-scrolling: touch;
    /* marge à droite/bas pour que les ombres franches ne soient pas coupées */
    padding: 2px calc(var(--gutter) + 4px) var(--sp-4) var(--gutter);
    display: flex;
    flex-direction: column;
    gap: var(--sp-4);
  }

  .field { display: flex; flex-direction: column; gap: 6px; }

  .field-label {
    font-size: var(--fs-sm);
    font-weight: var(--fw-bold);
    text-transform: uppercase;
    letter-spacing: var(--tracking-caps);
  }

  .optional { font-weight: var(--fw-medium); text-transform: none; letter-spacing: 0; color: var(--text-secondary); }

  .hint { font-size: 13px; color: var(--text-secondary); }

  /* ── Choix du rôle ── */
  .roles {
    margin: 0;
    padding: 0;
    border: none;
    display: flex;
    flex-direction: column;
    gap: var(--sp-3);
  }

  .roles legend { padding: 0; margin-bottom: var(--sp-2); }

  .role {
    position: relative;
    display: flex;
    align-items: center;
    gap: var(--sp-3);
    min-height: 72px;
    padding: var(--sp-3);
    border: var(--line-w) solid var(--line);
    background: var(--surface);
    cursor: pointer;
    touch-action: manipulation;
    transition: transform var(--dur-fast) var(--ease-out);
  }
  .role:active { transform: translate(2px, 2px); }

  .role.on {
    background: var(--highlight);
    box-shadow: var(--shadow-sm);
  }

  .role input {
    position: absolute;
    opacity: 0;
    width: 1px;
    height: 1px;
    pointer-events: none;
  }

  .role:has(input:focus-visible) { outline: 3px solid var(--accent); outline-offset: 2px; }

  .role-icon {
    width: 40px;
    height: 40px;
    flex-shrink: 0;
    border: var(--line-w) solid var(--line);
    display: flex;
    align-items: center;
    justify-content: center;
    background: var(--surface);
    color: var(--text);
  }

  .role.on .role-icon { background: var(--accent); color: var(--on-accent); }

  .role-text { flex: 1; min-width: 0; display: flex; flex-direction: column; gap: 2px; }
  .role-name { font-weight: var(--fw-bold); font-size: var(--fs-base); color: var(--text); }
  .role-desc { font-size: 13px; line-height: 1.35; color: var(--text-secondary); }
  .role.on .role-desc { color: var(--text); }

  /* Case carrée de sélection (le rond d'une pastille n'existe plus) */
  .role-dot {
    width: 24px;
    height: 24px;
    flex-shrink: 0;
    border: var(--line-w) solid var(--line);
    background: var(--surface);
    position: relative;
  }

  .role.on .role-dot { background: var(--accent); }

  .role-dot::after {
    content: '';
    position: absolute;
    left: 4px;
    top: 4px;
    width: 12px;
    height: 7px;
    border: solid var(--on-accent);
    border-width: 0 0 3px 3px;
    transform: translateY(1px) rotate(-45deg) scale(0);
    transition: transform var(--dur-base) var(--ease-snap);
  }

  .role.on .role-dot::after { transform: translateY(1px) rotate(-45deg) scale(1); }

  /* ── Fondateur ── */
  .explain {
    display: flex;
    gap: var(--sp-3);
    align-items: flex-start;
    padding: var(--sp-3);
    border: var(--line-w) solid var(--line);
    background: var(--highlight);
    color: var(--text);
    font-size: 15px;
    line-height: 1.45;
  }

  .explain-icon { color: var(--text); flex-shrink: 0; margin-top: 1px; }

  /* ── Lien ── */
  .link-box { position: relative; }

  .link-icon {
    position: absolute;
    left: 14px;
    top: 50%;
    transform: translateY(-50%);
    color: var(--text);
    pointer-events: none;
  }

  .link-input {
    padding-left: 42px;
    font-size: var(--fs-sm);
    font-variant-numeric: tabular-nums;
    text-overflow: ellipsis;
    user-select: all;
    -webkit-user-select: all;
  }

  .link-actions {
    display: grid;
    grid-template-columns: 1fr 1fr;
    gap: var(--sp-3);
  }

  .act { min-height: 52px; font-size: 15px; }
  .act-copy { background: var(--surface); color: var(--text); }
  .act-copy.done { background: var(--success-bg); color: var(--success); }
  .act-share { background: var(--accent); color: var(--on-accent); }

  .notice {
    display: flex;
    gap: 10px;
    align-items: flex-start;
    padding: var(--sp-3);
    border: var(--line-w) solid var(--line);
    background: var(--surface-sunken);
    color: var(--text);
    font-size: var(--fs-sm);
    line-height: 1.45;
  }

  .notice :global(.icon) { margin-top: 1px; flex-shrink: 0; }
  .notice-date { display: block; margin-top: var(--sp-1); color: var(--text-secondary); }

  .iv-error {
    font-size: var(--fs-sm);
    line-height: 1.4;
    color: var(--text);
    background: var(--error-bg);
    border: var(--line-w) solid var(--error);
    padding: 9px var(--sp-3);
  }

  /* ── Bas de fenêtre ── */
  .iv-actions {
    padding: var(--sp-3) calc(var(--gutter) + 4px) calc(var(--sp-4) + env(safe-area-inset-bottom, 0px)) var(--gutter);
    border-top: var(--line-w) solid var(--line);
  }

  .iv-actions .btn { width: 100%; min-height: 52px; padding: 14px; }
  .iv-actions .btn-primary[aria-busy='true'] { cursor: progress; }

  @media (hover: hover) and (pointer: fine) {
    .role:hover:not(.on) { background: var(--surface-hover); }
  }
</style>
