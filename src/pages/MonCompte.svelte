<script lang="ts">
  import Icon from '../components/Icon.svelte'
  import ConfirmDialog from '../components/ConfirmDialog.svelte'
  import { auth, signOut } from '../lib/auth.svelte'
  import { profileState, loadProfile, clearProfile, canInviteInOwnFamily } from '../lib/profile.svelte'
  import { pendingToggles } from '../lib/offline'
  import { supabase } from '../lib/supabase'
  import { navigate, href } from '../lib/router.svelte'
  import { toast } from '../lib/toast.svelte'
  import { VERSION_LABEL } from '../lib/version'
  import { deleteMyAccount } from '../lib/api/famille'
  import { forgetWelcome } from '../lib/bienvenue.svelte'
  import { THEME_CHOICES, setTheme, theme } from '../lib/theme.svelte'

  let displayName = $state('')
  let newPassword = $state('')
  let confirmPassword = $state('')
  let showPassword = $state(false)

  let saving = $state(false)
  let savingPw = $state(false)
  let nameError = $state<string | null>(null)
  let pwError = $state<string | null>(null)

  let confirmSignOut = $state(false)
  let confirmClear = $state(false)
  let pendingCount = $state(0)

  // Charger les infos initiales
  $effect(() => {
    if (profileState.profile) {
      displayName = profileState.profile.display_name ?? ''
    }
  })

  const savedName = $derived(profileState.profile?.display_name ?? '')
  const nameChanged = $derived(displayName.trim() !== savedName)

  async function handleSaveName() {
    if (!supabase || !auth.user || saving) return
    nameError = null
    if (!displayName.trim()) {
      nameError = 'Le nom ne peut pas être vide.'
      return
    }
    if (!nameChanged) {
      toast.info('Ce nom est déjà enregistré.')
      return
    }

    saving = true

    const { error: err } = await supabase
      .from('profiles')
      .update({ display_name: displayName.trim() })
      .eq('id', auth.user.id)

    if (err) {
      toast.error(err.message)
    } else {
      toast.success('Nom mis à jour !')
      await loadProfile(auth.user.id)
    }
    saving = false
  }

  // Indicateur de force volontairement simple (longueur + variété)
  const strength = $derived.by(() => {
    const p = newPassword
    if (!p) return null
    if (p.length < 10) return { level: 0, label: 'Trop court (10 caractères min.)' }
    let score = 0
    if (p.length >= 10) score++
    if (p.length >= 14) score++
    if (/[a-z]/i.test(p) && /\d/.test(p)) score++
    if (/[^a-z0-9]/i.test(p) || (/[a-z]/.test(p) && /[A-Z]/.test(p))) score++
    if (score <= 1) return { level: 1, label: 'Faible' }
    if (score === 2) return { level: 2, label: 'Correct' }
    return { level: 3, label: 'Solide' }
  })

  const passwordsMatch = $derived(confirmPassword.length > 0 && confirmPassword === newPassword)
  const passwordsDiffer = $derived(confirmPassword.length > 0 && confirmPassword !== newPassword)

  async function handleChangePassword() {
    if (!supabase || savingPw) return
    pwError = null
    if (newPassword.length < 10) {
      pwError = 'Le mot de passe doit faire au moins 10 caractères.'
      return
    }
    if (newPassword !== confirmPassword) {
      pwError = 'Les deux mots de passe ne correspondent pas.'
      return
    }

    savingPw = true

    const { error: err } = await supabase.auth.updateUser({ password: newPassword })

    if (err) {
      pwError = err.message.toLowerCase().includes('different from the old')
        ? "Le nouveau mot de passe doit être différent de l'ancien."
        : err.message
    } else {
      toast.success('Mot de passe changé !')
      newPassword = ''
      confirmPassword = ''
      showPassword = false
    }
    savingPw = false
  }

  function handleSignOut() {
    confirmSignOut = false
    clearProfile(true) // déconnexion : on efface aussi les données gardées sur le téléphone
    signOut()
    navigate('login')
  }

  function askClear() {
    try {
      pendingCount = pendingToggles().length
    } catch {
      pendingCount = 0
    }
    confirmClear = true
  }

  /** Efface uniquement les données hors connexion (clés `courses:`), sans déconnecter. */
  function handleClearOffline() {
    let removed = 0
    try {
      for (const key of Object.keys(localStorage)) {
        if (key.startsWith('courses:')) {
          localStorage.removeItem(key)
          removed++
        }
      }
    } catch {
      // stockage indisponible : rien à effacer
    }
    confirmClear = false
    toast.success(removed > 0
      ? 'Données hors connexion effacées. La liste sera rechargée depuis internet.'
      : 'Rien à effacer sur ce téléphone.')
  }

  // ── Supprimer mon compte (migration 21, delete_my_account) ──
  const CONFIRM_WORD = 'SUPPRIMER'
  let confirmDelete = $state(false)
  let deleteWord = $state('')
  let deletePassword = $state('')
  let showDeletePassword = $state(false)
  let deleting = $state(false)
  let deleteError = $state<string | null>(null)

  // Blocages connus d'avance (la base vérifie de toute façon, y compris « dernier admin »)
  const deleteBlocked = $derived(
    profileState.context?.isSuperAdmin
      ? 'Tu es super-admin : ton compte ne peut pas être supprimé depuis l’appli (il faut d’abord transmettre ce rôle, dans Supabase).'
      : profileState.context?.isFounder
        ? 'Tu es fondateur de ta super-famille : ton compte ne peut pas être supprimé depuis l’appli. Demande d’abord au super-admin de transmettre ton rôle.'
        : null,
  )
  const deleteReady = $derived(deleteWord.trim().toUpperCase() === CONFIRM_WORD && deletePassword.length > 0)

  function askDelete() {
    deleteWord = ''
    deletePassword = ''
    showDeletePassword = false
    deleteError = null
    confirmDelete = true
  }

  async function handleDeleteAccount() {
    if (!deleteReady || deleting || !auth.user) return
    deleting = true
    deleteError = null
    const userId = auth.user.id
    try {
      const r = await deleteMyAccount(deletePassword)
      if (r === 'mot_de_passe_incorrect') {
        deleteError = 'Mot de passe incorrect. Ton compte n’a pas été supprimé.'
        deletePassword = ''
      } else if (r === 'trop_d_essais') {
        deleteError = 'Trop d’essais ratés. Réessaie dans 15 minutes. Ton compte n’a pas été supprimé.'
        deletePassword = ''
      } else {
        // Supprimé côté serveur : on oublie tout sur ce téléphone
        confirmDelete = false
        deletePassword = ''
        clearProfile(true)
        forgetWelcome(userId)
        await signOut('local')
        navigate('login')
        toast.success('Ton compte a été supprimé. Merci d’avoir utilisé Lichouz !')
      }
    } catch (e: any) {
      deleteError = e?.message
        ? `${e.message}. Ton compte n’a pas été supprimé.`
        : 'Impossible de joindre le serveur. Ton compte n’a pas été supprimé.'
    } finally {
      deleting = false
    }
  }

  const userEmail = $derived(auth.user?.email ?? '')
  const role = $derived(profileState.profile?.role === 'admin' ? 'Administrateur' : 'Membre')
  const initial = $derived(savedName.trim().charAt(0).toUpperCase())
</script>

<div class="page">
  <header class="head">
    <h1>Mon compte</h1>
    <p class="head-sub">Ton profil et les réglages de ce téléphone.</p>
  </header>

  <!-- Avatar + résumé -->
  <section class="profile-card card" aria-label="Profil">
    <div class="avatar" aria-hidden="true">
      {#if initial}
        {initial}
      {:else}
        <Icon name="user" size={28} />
      {/if}
    </div>
    <div class="profile-info">
      <span class="profile-name">{savedName || 'Sans nom'}</span>
      {#if profileState.profile?.pseudo}<span class="profile-pseudo">@{profileState.profile.pseudo}</span>{/if}
      {#if userEmail}<span class="profile-email">{userEmail}</span>{/if}
      {#if profileState.profile}<span class="profile-role-badge">{role}</span>{/if}
    </div>
  </section>

  <!-- Famille et administration -->
  <nav class="links card" aria-label="Famille">
    <a class="link-row row" href={href('famille')}>
      <span class="section-icon"><Icon name="users" size={18} /></span>
      <span class="link-text">
        <span class="link-title">Ma famille</span>
        <span class="link-sub">
          {profileState.context?.family?.name ?? 'Membres'}{canInviteInOwnFamily() ? ' · inviter des personnes' : ''}
        </span>
      </span>
      <Icon name="chevron-right" size={18} />
    </a>
    <a class="link-row row" href={href('mes-recettes')}>
      <span class="section-icon"><Icon name="chef" size={18} /></span>
      <span class="link-text">
        <span class="link-title">Mes recettes</span>
        <span class="link-sub">Partager, modifier, archiver</span>
      </span>
      <Icon name="chevron-right" size={18} />
    </a>
    <a class="link-row row" href={href('evenements')}>
      <span class="section-icon"><Icon name="calendar" size={18} /></span>
      <span class="link-text">
        <span class="link-title">Événements</span>
        <span class="link-sub">Noël, anniversaires : qui vient, qui fait quoi</span>
      </span>
      <Icon name="chevron-right" size={18} />
    </a>
    <a class="link-row row" href={href('avis')}>
      <span class="section-icon"><Icon name="mail" size={18} /></span>
      <span class="link-text">
        <span class="link-title">Idées et retours</span>
        <span class="link-sub">Une idée, un bug : écris à Titouan</span>
      </span>
      <Icon name="chevron-right" size={18} />
    </a>
    <a class="link-row row" href={href('nouveautes')}>
      <span class="section-icon"><Icon name="star" size={18} /></span>
      <span class="link-text">
        <span class="link-title">Nouveautés</span>
        <span class="link-sub">Ce qui a changé dans l’appli</span>
      </span>
      <Icon name="chevron-right" size={18} />
    </a>
    {#if profileState.context?.isSuperAdmin}
      <a class="link-row row" href={href('admin')}>
        <span class="section-icon"><Icon name="lock" size={18} /></span>
        <span class="link-text">
          <span class="link-title">Administration</span>
          <span class="link-sub">Inviter des fondateurs, vue d'ensemble</span>
        </span>
        <Icon name="chevron-right" size={18} />
      </a>
    {/if}
    <a class="link-row row" href={href('vie-privee')}>
      <span class="section-icon"><Icon name="shield" size={18} /></span>
      <span class="link-text">
        <span class="link-title">Vie privée</span>
        <span class="link-sub">Pseudo, mes données, conditions</span>
      </span>
      <Icon name="chevron-right" size={18} />
    </a>
    <a class="link-row row" href={href('aide')}>
      <span class="section-icon"><Icon name="book" size={18} /></span>
      <span class="link-text">
        <span class="link-title">Aide</span>
        <span class="link-sub">À quoi sert Lichouz, comment s’en servir</span>
      </span>
      <Icon name="chevron-right" size={18} />
    </a>
  </nav>

  <!-- Nom d'affichage -->
  <section class="card" aria-labelledby="name-title">
    <h2 id="name-title" class="section-title">
      <span class="section-icon"><Icon name="pencil" size={18} /></span> Nom d'affichage
    </h2>
    <div class="field">
      <label for="display-name" class="label-text">Comment les autres te voient</label>
      <input
        id="display-name"
        type="text"
        class="input"
        class:error={nameError != null}
        aria-invalid={nameError != null}
        aria-describedby={nameError ? 'name-error' : undefined}
        placeholder="Ton prénom ou surnom"
        autocomplete="nickname"
        maxlength="40"
        bind:value={displayName}
        oninput={() => (nameError = null)}
        onkeydown={(e) => { if (e.key === 'Enter') handleSaveName() }}
      />
    </div>
    {#if nameError}<p id="name-error" class="field-error" role="alert">{nameError}</p>{/if}
    <button class="btn btn-primary btn-save" onclick={handleSaveName} aria-busy={saving}>
      {saving ? 'Enregistrement…' : 'Enregistrer le nom'}
    </button>
  </section>

  <!-- Affichage : thème (v1.99.3) -->
  <section class="card" aria-labelledby="display-title">
    <h2 id="display-title" class="section-title">
      <span class="section-icon"><Icon name="settings" size={18} /></span> Affichage
    </h2>
    <div class="theme-choices" role="radiogroup" aria-labelledby="display-title">
      {#each THEME_CHOICES as c (c.value)}
        <button
          type="button"
          class="theme-choice"
          role="radio"
          aria-checked={theme.choice === c.value}
          onclick={() => setTheme(c.value)}
        >
          <span class="theme-label">{c.label}</span>
          <span class="theme-hint">{c.hint}</span>
        </button>
      {/each}
    </div>
    <p class="theme-note">Le mode clair ou sombre suit toujours ton téléphone. Réglage gardé sur ce téléphone.</p>
  </section>

  <!-- Changer le mot de passe -->
  <section class="card" aria-labelledby="pw-title">
    <h2 id="pw-title" class="section-title">
      <span class="section-icon"><Icon name="lock" size={18} /></span> Changer le mot de passe
    </h2>

    <div class="field">
      <label for="new-password" class="label-text">Nouveau mot de passe</label>
      <div class="input-wrap">
        <input
          id="new-password"
          type={showPassword ? 'text' : 'password'}
          class="input input-has-toggle"
          class:error={pwError != null && newPassword.length < 10}
          placeholder="10 caractères minimum"
          autocomplete="new-password"
          autocapitalize="off"
          spellcheck="false"
          aria-describedby="pw-strength"
          bind:value={newPassword}
          oninput={() => (pwError = null)}
        />
        <button
          type="button"
          class="eye-btn"
          aria-label={showPassword ? 'Masquer les mots de passe' : 'Afficher les mots de passe'}
          aria-pressed={showPassword}
          onclick={() => (showPassword = !showPassword)}
        >
          <Icon name={showPassword ? 'eye-off' : 'eye'} size={20} />
        </button>
      </div>
      <div id="pw-strength" class="strength" aria-live="polite">
        {#if strength}
          <div class="strength-bar" data-level={strength.level} aria-hidden="true">
            <span></span><span></span><span></span>
          </div>
          <span class="strength-label" data-level={strength.level}>{strength.label}</span>
        {:else}
          <span class="strength-hint">Astuce : une phrase courte est plus facile à retenir et plus solide.</span>
        {/if}
      </div>
    </div>

    <div class="field">
      <label for="confirm-password" class="label-text">Confirmer le mot de passe</label>
      <input
        id="confirm-password"
        type={showPassword ? 'text' : 'password'}
        class="input"
        class:error={passwordsDiffer && pwError != null}
        placeholder="Retape le mot de passe"
        autocomplete="new-password"
        autocapitalize="off"
        spellcheck="false"
        aria-describedby="pw-match"
        bind:value={confirmPassword}
        oninput={() => (pwError = null)}
      />
      <p id="pw-match" class="match" aria-live="polite">
        {#if passwordsMatch}
          <span class="match-ok"><Icon name="check" size={14} /> Les mots de passe correspondent</span>
        {:else if passwordsDiffer}
          <span class="match-ko">Pas encore identiques</span>
        {/if}
      </p>
    </div>

    {#if pwError}<p class="field-error" role="alert">{pwError}</p>{/if}
    <button class="btn btn-primary btn-save" onclick={handleChangePassword} aria-busy={savingPw}>
      {savingPw ? 'Modification…' : 'Changer le mot de passe'}
    </button>
  </section>

  <!-- À propos / ce téléphone -->
  <section class="card" aria-labelledby="about-title">
    <h2 id="about-title" class="section-title">
      <span class="section-icon"><Icon name="settings" size={18} /></span> Ce téléphone
    </h2>
    <p class="about-text">
      La dernière liste de courses est gardée sur ce téléphone pour marcher sans réseau.
      Si elle paraît bloquée ou pas à jour, tu peux l'effacer : tu resteras connecté.
    </p>
    <button class="btn btn-outline btn-row" onclick={askClear}>
      <Icon name="refresh" size={18} /> Vider les données locales
    </button>
  </section>

  <!-- Déconnexion : à part -->
  <div class="danger-zone">
    <button class="btn btn-outline btn-logout" onclick={() => (confirmSignOut = true)}>
      <Icon name="logout" size={18} /> Se déconnecter
    </button>
  </div>

  <!-- Supprimer mon compte : tout en bas, à part -->
  <section class="delete-zone" aria-labelledby="delete-title">
    <h2 id="delete-title" class="delete-title">Supprimer mon compte</h2>
    {#if deleteBlocked}
      <p class="delete-text">{deleteBlocked}</p>
    {:else}
      <p class="delete-text">
        Ton compte et ton accès disparaissent pour de bon. Les recettes que tu as écrites
        restent dans ta famille, sans ton nom.
      </p>
      <button class="btn btn-danger btn-delete" onclick={askDelete}>
        <Icon name="trash" size={18} /> Supprimer mon compte
      </button>
    {/if}
  </section>

  <p class="app-version">Lichouz · {VERSION_LABEL}</p>
</div>

{#if confirmSignOut}
  <ConfirmDialog
    title="Se déconnecter ?"
    confirmLabel="Se déconnecter"
    danger
    onconfirm={handleSignOut}
    oncancel={() => (confirmSignOut = false)}
  >
    La liste de courses gardée sur ce téléphone sera effacée. Tu devras te reconnecter
    avec ton e-mail et ton mot de passe.
  </ConfirmDialog>
{/if}

{#if confirmDelete}
  <ConfirmDialog
    title="Supprimer ton compte ?"
    confirmLabel="Supprimer définitivement"
    danger
    busy={deleting}
    confirmDisabled={!deleteReady}
    onconfirm={handleDeleteAccount}
    oncancel={() => { if (!deleting) confirmDelete = false }}
  >
    <ul class="delete-list">
      <li><strong>Supprimé :</strong> ton compte, ton nom, tes liens d’invitation en attente.</li>
      <li><strong>Gardé :</strong> tes recettes (sans ton nom), le planning et les listes de ta famille.</li>
      <li>Impossible d’annuler. Pour revenir, il faudra une nouvelle invitation.</li>
    </ul>
    <div class="delete-form">
    <div class="field">
      <label for="delete-word" class="label-text">Tape <strong>{CONFIRM_WORD}</strong> pour confirmer</label>
      <input
        id="delete-word"
        type="text"
        class="input"
        autocomplete="off"
        autocapitalize="characters"
        spellcheck="false"
        bind:value={deleteWord}
        oninput={() => (deleteError = null)}
      />
    </div>
    <div class="field">
      <label for="delete-password" class="label-text">Ton mot de passe</label>
      <div class="input-wrap">
        <input
          id="delete-password"
          type={showDeletePassword ? 'text' : 'password'}
          class="input input-has-toggle"
          autocomplete="current-password"
          autocapitalize="off"
          spellcheck="false"
          bind:value={deletePassword}
          oninput={() => (deleteError = null)}
          onkeydown={(e) => { if (e.key === 'Enter') handleDeleteAccount() }}
        />
        <button
          type="button"
          class="eye-btn"
          aria-label={showDeletePassword ? 'Masquer le mot de passe' : 'Afficher le mot de passe'}
          aria-pressed={showDeletePassword}
          onclick={() => (showDeletePassword = !showDeletePassword)}
        >
          <Icon name={showDeletePassword ? 'eye-off' : 'eye'} size={20} />
        </button>
      </div>
    </div>
    {#if deleteError}<p class="field-error" role="alert">{deleteError}</p>{/if}
    </div>
  </ConfirmDialog>
{/if}

{#if confirmClear}
  <ConfirmDialog
    title="Vider les données hors connexion de ce téléphone ?"
    confirmLabel="Vider"
    danger={pendingCount > 0}
    onconfirm={handleClearOffline}
    oncancel={() => (confirmClear = false)}
  >
    {#if pendingCount > 0}
      <strong class="warn">
        {pendingCount === 1
          ? '1 article coché sans réseau n’a pas encore été envoyé'
          : `${pendingCount} articles cochés sans réseau n’ont pas encore été envoyés`}
        et sera perdu.
      </strong>
    {/if}
    La copie locale de la liste sera effacée et rechargée depuis internet. Tu restes connecté.
  </ConfirmDialog>
{/if}

<style>
  .page {
    padding: var(--gutter);
    padding-top: calc(var(--gutter) + env(safe-area-inset-top, 0px));
    max-width: 560px;
    margin: 0 auto;
    padding-bottom: calc(84px + env(safe-area-inset-bottom, 0px));
    display: flex;
    flex-direction: column;
    gap: var(--sp-4);
  }

  .head h1 { padding-right: 56px; /* avatar en haut à droite */ }

  .head-sub {
    margin-top: var(--sp-1);
    font-size: 15px;
    font-weight: var(--fw-medium);
    color: var(--text-secondary);
  }

  /* ── Profil ── */
  .profile-card {
    display: flex;
    align-items: center;
    gap: var(--sp-4);
    padding: var(--sp-4);
    animation: fade-up var(--dur-sheet) var(--ease-out) backwards;
  }

  .avatar {
    width: 64px;
    height: 64px;
    border: var(--line-w) solid var(--line);
    background: var(--accent);
    color: var(--on-accent);
    font-size: 28px;
    font-weight: var(--fw-bold);
    text-transform: uppercase;
    display: flex;
    align-items: center;
    justify-content: center;
    flex-shrink: 0;
    box-shadow: var(--shadow-sm);
  }

  .profile-info {
    display: flex;
    flex-direction: column;
    gap: 3px;
    min-width: 0;
  }

  .profile-name {
    font-size: 20px;
    font-weight: var(--fw-bold);
    color: var(--text);
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }
  .profile-pseudo { font-size: var(--fs-sm); font-weight: var(--fw-bold); color: var(--text-secondary); }

  .profile-email {
    font-size: 14px;
    color: var(--text-secondary);
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  .profile-role-badge {
    margin-top: var(--sp-1);
    align-self: flex-start;
    padding: 1px 8px;
    border: var(--line-thin) solid var(--line);
    background: var(--band);
    color: var(--text-on-band);
    font-size: var(--fs-xs);
    font-weight: var(--fw-bold);
    text-transform: uppercase;
    letter-spacing: var(--tracking-caps);
  }

  /* ── Menus : une carte, des lignes cliquables ── */
  .links {
    animation: fade-up var(--dur-sheet) var(--ease-out) 45ms backwards;
  }
  .link-row {
    min-height: 60px;
    padding: var(--sp-2) var(--sp-3);
    color: var(--text);
    text-decoration: none;
    touch-action: manipulation;
    transition: transform var(--dur-fast) var(--ease-out);
  }
  .link-row:active { background: var(--surface-hover); transform: translate(2px, 2px); }
  .link-row:focus-visible { outline: 3px solid var(--accent); outline-offset: -3px; }
  .link-text { flex: 1; display: grid; gap: 2px; min-width: 0; }
  .link-title { font-weight: var(--fw-bold); }
  .link-sub { font-size: 13px; color: var(--text-secondary); overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }

  /* ── Cartes ── */
  section.card:not(.profile-card) {
    padding: var(--sp-4);
    display: flex;
    flex-direction: column;
    gap: 14px;
    animation: fade-up var(--dur-sheet) var(--ease-out) 90ms backwards;
  }

  /* Titre de rubrique = bandeau noir en tête de carte (même rôle que les rayons des Courses) */
  .theme-choices { display: flex; flex-direction: column; gap: var(--sp-2); }
  .theme-choice {
    display: flex;
    flex-direction: column;
    align-items: flex-start;
    gap: 2px;
    min-height: var(--tap);
    padding: 10px 12px;
    border: var(--line-w) solid var(--line);
    background: var(--surface);
    color: var(--text);
    text-align: left;
    font: inherit;
    cursor: pointer;
    touch-action: manipulation;
    transition: transform var(--dur-fast) var(--ease-out);
  }
  .theme-choice:active { transform: translate(2px, 2px); }
  .theme-choice[aria-checked='true'] {
    background: var(--accent);
    color: var(--on-accent);
    box-shadow: var(--shadow-sm);
  }
  .theme-label { font-weight: var(--fw-bold); }
  .theme-hint { font-size: var(--fs-sm); opacity: 0.85; }
  .theme-note { margin-top: var(--sp-3); font-size: var(--fs-sm); color: var(--text-secondary); }

  .section-title {
    display: flex;
    align-items: center;
    gap: var(--sp-2);
    margin: calc(var(--sp-4) * -1) calc(var(--sp-4) * -1) var(--sp-3);
    padding: 6px var(--sp-3);
    background: var(--band);
    color: var(--text-on-band);
    font-size: 13px;
    font-weight: var(--fw-bold);
    letter-spacing: var(--tracking-caps);
    text-transform: uppercase;
  }

  /* Icône dans un petit carré bordé */
  .section-icon {
    display: inline-flex;
    align-items: center;
    justify-content: center;
    color: inherit;
    flex-shrink: 0;
  }

  .field {
    display: flex;
    flex-direction: column;
    gap: 6px;
  }

  .label-text {
    font-size: var(--fs-sm);
    font-weight: var(--fw-bold);
    text-transform: uppercase;
    letter-spacing: var(--tracking-caps);
    color: var(--text);
  }
  .label-text strong { letter-spacing: 0; }

  .input-wrap { position: relative; }
  .input-has-toggle { padding-right: 52px; }

  .eye-btn {
    position: absolute;
    right: 2px;
    top: 50%;
    transform: translateY(-50%);
    width: 44px;
    height: 44px;
    display: flex;
    align-items: center;
    justify-content: center;
    border: none;
    background: transparent;
    color: var(--text);
    cursor: pointer;
    touch-action: manipulation;
  }
  .eye-btn[aria-pressed='true'] { color: var(--text); background: var(--highlight); }
  .eye-btn:focus-visible { outline: 3px solid var(--accent); outline-offset: -3px; }

  .field-error {
    font-size: var(--fs-sm);
    line-height: 1.4;
    color: var(--text);
    background: var(--error-bg);
    border: var(--line-w) solid var(--error);
    padding: 9px 12px;
  }

  /* ── Force du mot de passe ── */
  .strength {
    display: flex;
    align-items: center;
    gap: 10px;
    min-height: 20px;
    font-size: 13px;
  }

  .strength-bar {
    display: flex;
    gap: 4px;
    flex: 0 0 96px;
  }

  .strength-bar span {
    flex: 1;
    height: 8px;
    border: var(--line-thin) solid var(--line);
    background: var(--surface-sunken);
  }

  .strength-bar[data-level='0'] span:nth-child(1) { background: var(--error); }
  .strength-bar[data-level='1'] span:nth-child(1) { background: var(--accent); }
  .strength-bar[data-level='2'] span:nth-child(-n + 2) { background: var(--accent); }
  .strength-bar[data-level='3'] span { background: var(--success); }

  .strength-label { font-weight: var(--fw-bold); color: var(--text-secondary); }
  .strength-label[data-level='0'] { color: var(--error); }
  .strength-label[data-level='1'] { color: var(--text); }
  .strength-label[data-level='2'] { color: var(--text); }
  .strength-label[data-level='3'] { color: var(--success); }

  .strength-hint { color: var(--text-secondary); line-height: 1.4; }

  .match { min-height: 18px; font-size: 13px; }
  .match-ok {
    display: inline-flex;
    align-items: center;
    gap: 4px;
    color: var(--success);
    font-weight: var(--fw-bold);
  }
  .match-ko { color: var(--text-secondary); }

  /* ── Boutons ── */
  .btn-save[aria-busy='true'] { opacity: 0.75; cursor: progress; }
  .btn-row { font-size: 15px; }

  .about-text {
    font-size: var(--fs-sm);
    line-height: 1.5;
    color: var(--text-secondary);
  }

  /* ── Déconnexion, à part ── */
  .danger-zone {
    margin-top: var(--sp-2);
    padding-top: var(--sp-5);
    border-top: var(--line-w) solid var(--line);
  }
  .btn-logout { width: 100%; font-size: 15px; }

  /* ── Supprimer mon compte ── */
  .delete-zone {
    margin-top: var(--sp-2);
    padding: var(--sp-4);
    border: var(--line-w) solid var(--error);
    background: var(--error-bg);
    box-shadow: 4px 4px 0 var(--error);
    display: flex;
    flex-direction: column;
    gap: 10px;
  }
  .delete-title {
    font-size: var(--fs-base);
    text-transform: uppercase;
    letter-spacing: var(--tracking-caps);
    color: var(--text);
    margin: 0;
  }
  .delete-text {
    font-size: var(--fs-sm);
    line-height: 1.5;
    color: var(--text);
  }
  .btn-delete { width: 100%; font-size: 15px; }
  .delete-list {
    margin: 0 0 var(--sp-3);
    padding-left: 18px;
    display: grid;
    gap: 6px;
    font-size: var(--fs-sm);
    line-height: 1.45;
  }
  .delete-form { display: grid; gap: var(--sp-3); text-align: left; }
  .delete-zone + .app-version { margin-top: var(--sp-3); }

  /* Version de l'appli (voir src/lib/version.ts) */
  .app-version {
    margin: var(--sp-5) 0 var(--sp-1);
    text-align: center;
    font-size: var(--fs-xs);
    font-weight: var(--fw-medium);
    color: var(--text-secondary);
    font-variant-numeric: tabular-nums;
  }

  .warn {
    display: block;
    margin-bottom: var(--sp-2);
    color: var(--error);
  }

  @media (hover: hover) and (pointer: fine) {
    .link-row:hover { background: var(--surface-hover); }
    .eye-btn:hover { background: var(--surface-hover); }
  }

  @media (min-width: 900px) {
    .page { padding-top: calc(32px + env(safe-area-inset-top, 0px)); }
  }
</style>
