<script lang="ts">
  // « Administration » (#/admin), réservée au super-admin :
  //   - liens « fondateur » (création, suivi, annulation) ;
  //   - vue d'ensemble en lecture seule : super-familles, familles, nombre de personnes ;
  //   - statistiques (admin_stats, migration 20) : uniquement des nombres, aucun contenu.
  // La base refuse tout à qui n'est pas super-admin : l'écran ne fait que le dire.
  import { untrack } from 'svelte'
  import ErrorState from '../components/ErrorState.svelte'
  import Icon from '../components/Icon.svelte'
  import ConfirmDialog from '../components/ConfirmDialog.svelte'
  import InviteDialog from '../components/InviteDialog.svelte'
  import { profileState } from '../lib/profile.svelte'
  import { href } from '../lib/router.svelte'
  import { toast } from '../lib/toast.svelte'
  import {
    fetchInvitations, revokeInvitation, invitationStatus, namesOf, fetchOverview, fetchAdminStats,
    type InvitationStatus, type SuperFamilyOverview, type AdminStats,
  } from '../lib/api/famille'
  import type { Invitation } from '../lib/types'
  import {
    fetchFeedback, setFeedbackStatus, fetchErrors, clearErrors,
    type FeedbackRow, type FeedbackStatus, type ErrorRow,
  } from '../lib/api/feedback'

  const ctx = $derived(profileState.context)
  const isSuperAdmin = $derived(!!ctx?.isSuperAdmin)
  const checking = $derived(!ctx && profileState.loading)

  // ── Liens fondateur ──
  let invites = $state<Invitation[]>([])
  let usedNames = $state<Record<string, string>>({})
  let invitesLoading = $state(true)
  let invitesError = $state<string | null>(null)
  let showPast = $state(false)

  // ── Vue d'ensemble ──
  let overview = $state<SuperFamilyOverview[]>([])
  let overviewLoading = $state(true)
  let overviewError = $state<string | null>(null)

  // ── Statistiques ──
  let stats = $state<AdminStats | null>(null)
  let statsLoading = $state(true)
  let statsError = $state<string | null>(null)

  let inviting = $state(false)
  let revokeTarget = $state<Invitation | null>(null)
  let revoking = $state(false)

  $effect(() => {
    if (!isSuperAdmin) return
    untrack(() => {
      void loadInvites()
      void loadOverview()
      void loadStats()
      void loadFeedback()
      void loadErrors()
    })
  })

  // ── Retours et journal des erreurs (v1.6.0) ──
  let feedback = $state<FeedbackRow[]>([])
  let feedbackLoading = $state(true)
  let feedbackError = $state<string | null>(null)
  let showDoneFeedback = $state(false)
  let errors = $state<ErrorRow[]>([])
  let errorsLoading = $state(true)
  let errorsError = $state<string | null>(null)
  let confirmClearErrors = $state(false)
  let clearing = $state(false)

  const KIND_LABEL = { idee: 'Idée', bug: 'Bug', autre: 'Autre' } as const
  const openFeedback = $derived(feedback.filter((f) => f.status !== 'fait'))
  const doneFeedback = $derived(feedback.filter((f) => f.status === 'fait'))
  const dateTime = (iso: string) =>
    new Date(iso).toLocaleString('fr-FR', { day: 'numeric', month: 'short', hour: '2-digit', minute: '2-digit' })

  async function loadFeedback() {
    feedbackLoading = true
    feedbackError = null
    try {
      feedback = await fetchFeedback()
    } catch (e) {
      feedbackError = messageOf(e, 'Les retours n’ont pas pu être chargés.')
    } finally {
      feedbackLoading = false
    }
  }

  async function markFeedback(f: FeedbackRow, status: FeedbackStatus) {
    try {
      await setFeedbackStatus(f.id, status)
      feedback = feedback.map((x) => (x.id === f.id ? { ...x, status } : x))
    } catch (e) {
      toast.error(messageOf(e, 'Le statut n’a pas pu être changé.'))
    }
  }

  async function loadErrors() {
    errorsLoading = true
    errorsError = null
    try {
      errors = await fetchErrors()
    } catch (e) {
      errorsError = messageOf(e, 'Le journal n’a pas pu être chargé.')
    } finally {
      errorsLoading = false
    }
  }

  async function doClearErrors() {
    if (clearing) return
    clearing = true
    try {
      const n = await clearErrors()
      errors = []
      toast.success(`${n} erreur${n > 1 ? 's' : ''} supprimée${n > 1 ? 's' : ''}`)
      confirmClearErrors = false
    } catch (e) {
      toast.error(messageOf(e, 'Le journal n’a pas pu être vidé.'))
    } finally {
      clearing = false
    }
  }

  async function loadInvites() {
    invitesLoading = true
    invitesError = null
    try {
      const list = await fetchInvitations({ kind: 'fondateur' })
      usedNames = await namesOf(list.map((i) => i.used_by ?? ''))
      invites = list
    } catch (e) {
      invitesError = messageOf(e, 'Les liens n’ont pas pu être chargés.')
    } finally {
      invitesLoading = false
    }
  }

  async function loadOverview() {
    overviewLoading = true
    overviewError = null
    try {
      overview = await fetchOverview()
    } catch (e) {
      overviewError = messageOf(e, 'La vue d’ensemble n’a pas pu être chargée.')
    } finally {
      overviewLoading = false
    }
  }

  async function confirmRevoke() {
    const inv = revokeTarget
    if (!inv || revoking) return
    revoking = true
    try {
      await revokeInvitation(inv.id)
      const now = new Date().toISOString()
      invites = invites.map((i) => (i.id === inv.id ? { ...i, revoked_at: now } : i))
      toast.success('Lien annulé : il ne marchera plus.')
      revokeTarget = null
    } catch (e) {
      toast.error(messageOf(e, 'Le lien n’a pas pu être annulé.'))
    } finally {
      revoking = false
    }
  }

  async function loadStats() {
    statsLoading = true
    statsError = null
    try {
      stats = await fetchAdminStats()
    } catch (e) {
      statsError = messageOf(e, 'Les statistiques n’ont pas pu être chargées.')
    } finally {
      statsLoading = false
    }
  }

  // ── Dérivés ──
  const pending = $derived(invites.filter((i) => invitationStatus(i) === 'valide'))
  const past = $derived(invites.filter((i) => invitationStatus(i) !== 'valide'))
  const totalFamilies = $derived(overview.reduce((n, sf) => n + sf.families.length, 0))
  const totalPeople = $derived(
    overview.reduce((n, sf) => n + sf.families.reduce((m, f) => m + f.members, 0), 0),
  )

  // ── Utilitaires ──
  function messageOf(e: unknown, fallback: string): string {
    const m = (e as { message?: unknown } | null)?.message
    if (typeof m !== 'string' || !m.trim()) return fallback
    if (/failed to fetch|network|load failed/i.test(m)) return 'Pas de réseau : réessaie quand tu seras connecté.'
    return m
  }

  function fmtDate(iso: string | null): string {
    if (!iso) return ''
    const d = new Date(iso)
    const opts: Intl.DateTimeFormatOptions = { day: 'numeric', month: 'long' }
    if (d.getFullYear() !== new Date().getFullYear()) opts.year = 'numeric'
    return d.toLocaleDateString('fr-FR', opts)
  }

  function plural(n: number, one: string, many: string): string {
    return `${n} ${n > 1 ? many : one}`
  }

  function initialOf(name: string | null | undefined): string {
    return (name ?? '').trim().charAt(0).toUpperCase() || '?'
  }

  const STATUS_TAG: Record<InvitationStatus, string> = {
    valide: 'En attente',
    utilisee: 'Utilisé',
    expiree: 'Expiré',
    annulee: 'Annulé',
  }

  function statusText(i: Invitation, s: InvitationStatus): string {
    switch (s) {
      case 'valide': return `En attente jusqu’au ${fmtDate(i.expires_at)}`
      case 'utilisee': return `Utilisé par ${(i.used_by && usedNames[i.used_by]) || 'quelqu’un'} le ${fmtDate(i.used_at)}`
      case 'expiree': return `Expiré le ${fmtDate(i.expires_at)}`
      case 'annulee': return 'Annulé'
    }
  }
</script>

{#snippet skeleton(rows: number)}
  <ul class="rows" aria-hidden="true">
    {#each Array(rows) as _, i (i)}
      <li class="row sk-row" style:animation-delay="{i * 90}ms">
        <span class="sk-dot"></span>
        <span class="sk-body"><span class="sk-line"></span><span class="sk-line sk-short"></span></span>
      </li>
    {/each}
  </ul>
{/snippet}

{#snippet errorBox(message: string, retry: () => void)}
  <ErrorState error={message} {message} onretry={retry} compact />
{/snippet}

{#snippet inviteRow(inv: Invitation)}
  {@const s = invitationStatus(inv)}
  <li class="row" class:inactive={s !== 'valide'}>
    <span class="row-icon" aria-hidden="true"><Icon name="star" size={18} /></span>
    <span class="row-main">
      <span class="row-name">{inv.label || 'Lien sans nom'}</span>
      <span class="row-meta">
        <span class="status status-{s}">{STATUS_TAG[s]}</span>
        <span>{statusText(inv, s)}</span>
      </span>
      {#if inv.email_hint}<span class="row-meta">Réservé à {inv.email_hint}</span>{/if}
      <span class="row-meta">Créé le {fmtDate(inv.created_at)}</span>
    </span>
    {#if s === 'valide'}
      <button
        class="btn btn-row-action btn-cancel"
        onclick={() => (revokeTarget = inv)}
        aria-label={`Annuler le lien ${inv.label ? `pour ${inv.label}` : 'sans nom'}`}
      >Annuler</button>
    {/if}
  </li>
{/snippet}

<div class="page">
  <a href={href('compte')} class="back-link"><Icon name="arrow-left" size={18} /> Mon compte</a>

  <header class="head">
    <h1>Administration</h1>
    <p class="head-sub">Les fondateurs et tous les foyers de l’appli.</p>
  </header>

  {#if checking}
    <div class="card" aria-busy="true">
      <span class="sr-only">Chargement…</span>
      {@render skeleton(2)}
    </div>
  {:else if !isSuperAdmin}
    <div class="card state">
      <span class="state-icon"><Icon name="lock" size={28} /></span>
      <p class="state-title">Réservé à l’administrateur</p>
      <p class="state-text">Cette page sert à inviter de nouveaux fondateurs de familles.</p>
      <a href={href('compte')} class="btn btn-outline btn-small">
        <Icon name="arrow-left" size={16} /> Retour à mon compte
      </a>
    </div>
  {:else}
    <!-- ── Liens fondateur ── -->
    <section class="card" aria-labelledby="founders-title">
      <h2 id="founders-title" class="section-title">
        <span class="section-icon"><Icon name="star" size={18} /></span> Fondateurs
      </h2>
      <p class="card-text">
        Un fondateur crée son compte, puis sa famille. Il pourra y créer jusqu’à 3 foyers et y inviter qui il veut.
      </p>
      <button class="btn btn-primary btn-invite" onclick={() => (inviting = true)}>
        <Icon name="user-plus" size={20} /> Inviter un fondateur
      </button>

      {#if invitesLoading && invites.length === 0}
        {@render skeleton(2)}
      {:else if invitesError}
        {@render errorBox(invitesError, loadInvites)}
      {:else if invites.length === 0}
        <p class="empty">Aucun lien fondateur pour l’instant.</p>
      {:else}
        {#if pending.length === 0}
          <p class="empty">Aucun lien en attente.</p>
        {:else}
          <ul class="rows">
            {#each pending as inv (inv.id)}
              {@render inviteRow(inv)}
            {/each}
          </ul>
        {/if}
        {#if past.length > 0}
          {#if showPast}
            <ul class="rows">
              {#each past as inv (inv.id)}
                {@render inviteRow(inv)}
              {/each}
            </ul>
          {/if}
          <button class="link-btn" aria-expanded={showPast} onclick={() => (showPast = !showPast)}>
            <span class="chev" class:open={showPast}><Icon name="chevron-down" size={16} /></span>
            {showPast ? 'Masquer les liens passés' : `Liens passés (${past.length})`}
          </button>
        {/if}
      {/if}
    </section>

    <!-- ── Vue d'ensemble ── -->
    <section class="card" aria-labelledby="overview-title">
      <h2 id="overview-title" class="section-title">
        <span class="section-icon"><Icon name="users" size={18} /></span> Vue d’ensemble
      </h2>

      {#if overviewLoading && overview.length === 0}
        {@render skeleton(3)}
      {:else if overviewError}
        {@render errorBox(overviewError, loadOverview)}
      {:else}
        <div class="totals">
          <div class="total">
            <span class="total-n">{overview.length}</span>
            <span class="total-l">{overview.length > 1 ? 'groupes' : 'groupe'}</span>
          </div>
          <div class="total">
            <span class="total-n">{totalFamilies}</span>
            <span class="total-l">{totalFamilies > 1 ? 'foyers' : 'foyer'}</span>
          </div>
          <div class="total">
            <span class="total-n">{totalPeople}</span>
            <span class="total-l">{totalPeople > 1 ? 'personnes' : 'personne'}</span>
          </div>
        </div>

        {#if overview.length === 0}
          <p class="empty">Aucun foyer pour l’instant.</p>
        {:else}
          <ul class="sf-list">
            {#each overview as sf, si (sf.id)}
              {@const people = sf.families.reduce((m, f) => m + f.members, 0)}
              <li class="sf" style="--i: {Math.min(si, 8)}">
                <div class="sf-head">
                  <span class="sf-initial" aria-hidden="true">{initialOf(sf.name)}</span>
                  <span class="row-main">
                    <span class="row-name">{sf.name}</span>
                    <span class="row-meta">
                      {sf.founder_name ? `Fondé par ${sf.founder_name}` : 'Sans fondateur'} · le {fmtDate(sf.created_at)}
                    </span>
                    <span class="row-meta">
                      {plural(sf.families.length, 'famille', 'familles')} · {plural(people, 'personne', 'personnes')}
                    </span>
                  </span>
                </div>
                {#if sf.families.length > 0}
                  <ul class="fam-list">
                    {#each sf.families as f (f.id)}
                      <li class="fam-row">
                        <span class="fam-name">{f.name}</span>
                        <span class="fam-count">{f.members === 0 ? 'Aucun membre' : plural(f.members, 'membre', 'membres')}</span>
                      </li>
                    {/each}
                  </ul>
                {/if}
              </li>
            {/each}
          </ul>
        {/if}
      {/if}
    </section>
    <!-- ── Catalogue commun (v1.99.0) ── -->
    <section class="card" aria-labelledby="catalogue-title">
      <h2 id="catalogue-title" class="section-title">
        <span class="section-icon"><Icon name="book" size={18} /></span> Catalogue commun
      </h2>
      <p class="catalogue-text">
        Les recettes du catalogue sont lues par tous les foyers et modifiables par toi seul.
        Pour en modifier une, ouvre sa fiche puis « Modifier ». Pour en ajouter une, crée une recette
        et choisis « Catalogue commun » dans « Qui peut la voir ? » (une recette existante peut aussi y passer).
      </p>
      <a class="btn btn-outline catalogue-btn" href="#/nouvelle-recette"><Icon name="plus" size={18} /> Nouvelle recette</a>
    </section>

    <!-- ── Statistiques ── -->
    <section class="card" aria-labelledby="stats-title">
      <h2 id="stats-title" class="section-title">
        <span class="section-icon"><Icon name="list" size={18} /></span> Statistiques
      </h2>
      <p class="card-text">Uniquement des nombres : aucun titre de recette ni contenu privé n’est lu.</p>

      {#if statsLoading && !stats}
        {@render skeleton(3)}
      {:else if statsError}
        {@render errorBox(statsError, loadStats)}
      {:else if stats}
        {@const r = stats.recettes}
        {@const ajoutees = r.famille + r.super_famille}
        <h3 class="stats-sub">Recettes</h3>
        <div class="totals">
          <div class="total">
            <span class="total-n">{r.famille}</span>
            <span class="total-l">privées</span>
          </div>
          <div class="total">
            <span class="total-n">{r.super_famille}</span>
            <span class="total-l">partagées</span>
          </div>
          <div class="total">
            <span class="total-n">{r.catalogue}</span>
            <span class="total-l">catalogue</span>
          </div>
        </div>
        <ul class="stats-list">
          <li><span>Ajoutées ces 7 derniers jours</span><strong>{r.ajoutees_7j}</strong></li>
          <li><span>Ajoutées ces 30 derniers jours</span><strong>{r.ajoutees_30j}</strong></li>
          <li><span>Avec photo (hors catalogue)</span><strong>{r.avec_photo} / {ajoutees}</strong></li>
        </ul>

        <h3 class="stats-sub">Activité</h3>
        <ul class="stats-list">
          <li><span>Repas prévus cette semaine</span><strong>{stats.planning.repas_semaine}</strong></li>
          <li><span>Foyers qui planifient cette semaine</span><strong>{stats.planning.familles_actives}</strong></li>
          <li><span>Listes de courses en cours</span><strong>{stats.courses.listes_en_cours}</strong></li>
          <li><span>Courses terminées (30 jours)</span><strong>{stats.courses.terminees_30j}</strong></li>
        </ul>

        <h3 class="stats-sub">Personnes</h3>
        <ul class="stats-list">
          <li><span>Comptes</span><strong>{stats.personnes.total}</strong></li>
          <li><span>Nouveaux (30 jours)</span><strong>{stats.personnes.nouvelles_30j}</strong></li>
          <li><span>Liens d’invitation en attente</span><strong>{stats.invitations.en_attente}</strong></li>
        </ul>

        <button class="link-btn" onclick={loadStats} disabled={statsLoading} aria-busy={statsLoading}>
          <Icon name="refresh" size={16} /> {statsLoading ? 'Actualisation…' : 'Actualiser'}
        </button>
      {/if}
    </section>

    <!-- ── Idées et retours (v1.6.0) ── -->
    <section class="card" aria-labelledby="feedback-title">
      <h2 id="feedback-title" class="section-title">
        <span class="section-icon"><Icon name="mail" size={18} /></span>
        Idées et retours {#if openFeedback.length > 0}<span class="count">{openFeedback.length}</span>{/if}
      </h2>
      {#if feedbackLoading}
        <p class="empty" aria-busy="true">Chargement…</p>
      {:else if feedbackError}
        {@render errorBox(feedbackError, loadFeedback)}
      {:else if openFeedback.length === 0}
        <p class="empty">Rien de nouveau.</p>
      {:else}
        <ul class="msg-list">
          {#each openFeedback as f (f.id)}
            <li class="msg" class:unread={f.status === 'nouveau'}>
              <p class="msg-meta">
                <span class="tag">{KIND_LABEL[f.kind]}</span>
                {f.profiles?.display_name ?? 'Compte supprimé'}{f.families ? ` · ${f.families.name}` : ''} · {dateTime(f.created_at)}{f.app_version ? ` · v${f.app_version}` : ''}
              </p>
              <p class="msg-text">{f.message}</p>
              <div class="msg-actions">
                {#if f.status === 'nouveau'}
                  <button class="link-btn" onclick={() => markFeedback(f, 'lu')}>Marquer comme lu</button>
                {/if}
                <button class="link-btn" onclick={() => markFeedback(f, 'fait')}>Fait</button>
              </div>
            </li>
          {/each}
        </ul>
      {/if}
      {#if doneFeedback.length > 0}
        <button class="link-btn" onclick={() => (showDoneFeedback = !showDoneFeedback)} aria-expanded={showDoneFeedback}>
          {showDoneFeedback ? 'Masquer' : 'Voir'} les {doneFeedback.length} retours traités
        </button>
        {#if showDoneFeedback}
          <ul class="msg-list">
            {#each doneFeedback as f (f.id)}
              <li class="msg done">
                <p class="msg-meta"><span class="tag">{KIND_LABEL[f.kind]}</span> {f.profiles?.display_name ?? 'Compte supprimé'} · {dateTime(f.created_at)}</p>
                <p class="msg-text">{f.message}</p>
                <div class="msg-actions"><button class="link-btn" onclick={() => markFeedback(f, 'lu')}>Rouvrir</button></div>
              </li>
            {/each}
          </ul>
        {/if}
      {/if}
      <button class="link-btn" onclick={loadFeedback} disabled={feedbackLoading} aria-busy={feedbackLoading}>
        <Icon name="refresh" size={16} /> Actualiser
      </button>
    </section>

    <!-- ── Journal des erreurs (v1.6.0) ── -->
    <section class="card" aria-labelledby="errors-title">
      <h2 id="errors-title" class="section-title">
        <span class="section-icon"><Icon name="alert-circle" size={18} /></span>
        Erreurs de l’appli {#if errors.length > 0}<span class="count">{errors.length}</span>{/if}
      </h2>
      <p class="card-text">Gardées 90 jours. Rien de personnel : ni e-mail, ni jeton, ni adresse complète.</p>
      {#if errorsLoading}
        <p class="empty" aria-busy="true">Chargement…</p>
      {:else if errorsError}
        {@render errorBox(errorsError, loadErrors)}
      {:else if errors.length === 0}
        <p class="empty">Aucune erreur.</p>
      {:else}
        <ul class="msg-list">
          {#each errors as e (e.id)}
            <li class="msg">
              <p class="msg-meta">{dateTime(e.created_at)} · {e.route ?? '?'}{e.app_version ? ` · v${e.app_version}` : ''} · {e.profiles?.display_name ?? 'Compte supprimé'}</p>
              <p class="msg-text mono">{e.message}</p>
            </li>
          {/each}
        </ul>
        <button class="link-btn btn-cancel" onclick={() => (confirmClearErrors = true)}>Vider le journal</button>
      {/if}
      <button class="link-btn" onclick={loadErrors} disabled={errorsLoading} aria-busy={errorsLoading}>
        <Icon name="refresh" size={16} /> Actualiser
      </button>
    </section>
  {/if}
</div>

{#if confirmClearErrors}
  <ConfirmDialog
    title="Vider le journal des erreurs ?"
    confirmLabel="Vider"
    danger
    busy={clearing}
    onconfirm={doClearErrors}
    oncancel={() => (confirmClearErrors = false)}
  >
    <p>Les {errors.length} erreurs affichées seront supprimées définitivement.</p>
  </ConfirmDialog>
{/if}

{#if inviting}
  <InviteDialog
    kind="fondateur"
    onclose={() => (inviting = false)}
    oncreated={() => { void loadInvites() }}
  />
{/if}

{#if revokeTarget}
  <ConfirmDialog
    title="Annuler ce lien ?"
    confirmLabel="Annuler le lien"
    cancelLabel="Garder"
    danger
    busy={revoking}
    onconfirm={confirmRevoke}
    oncancel={() => (revokeTarget = null)}
  >
    {revokeTarget.label ? `${revokeTarget.label} ne pourra` : 'La personne qui l’a reçu ne pourra'} plus s’en servir
    pour créer son compte. Tu pourras toujours en créer un nouveau.
  </ConfirmDialog>
{/if}

<style>
  .page {
    padding: var(--gutter);
    padding-top: 0;
    max-width: 560px;
    margin: 0 auto;
    padding-bottom: calc(84px + env(safe-area-inset-bottom, 0px));
    display: flex;
    flex-direction: column;
    gap: var(--sp-4);
  }

  .back-link {
    display: inline-flex;
    align-items: center;
    align-self: flex-start;
    gap: 6px;
    min-height: 44px;
    margin-top: calc(8px + env(safe-area-inset-top, 0px));
    color: var(--text);
    font-weight: var(--fw-bold);
    text-decoration: underline;
    text-decoration-thickness: 2px;
    text-underline-offset: 3px;
    touch-action: manipulation;
  }

  .head h1 { padding-right: 56px; /* avatar */ }
  .head-sub { margin-top: var(--sp-1); font-size: 15px; font-weight: var(--fw-medium); color: var(--text-secondary); }

  /* ── Cartes ── */
  .card {
    padding: var(--sp-4);
    display: flex;
    flex-direction: column;
    gap: 14px;
  }

  /* Titre de rubrique = bandeau noir en tête de carte (même rôle que les rayons des Courses) */
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

  .card-text { font-size: var(--fs-sm); line-height: 1.5; color: var(--text-secondary); margin-top: -4px; }
  .empty { font-size: var(--fs-sm); color: var(--text-secondary); }
  .count {
    display: inline-grid; place-items: center;
    min-width: 24px; height: 24px; padding: 0 5px;
    background: var(--band); color: var(--text-on-band);
    font-size: 13px; font-weight: var(--fw-bold);
  }

  .btn-invite { min-height: 52px; padding: 14px; }
  .btn-small { min-height: 44px; padding: 0 var(--sp-4); font-size: var(--fs-sm); }

  /* ── Messages (retours, erreurs) ── */
  .msg-list { list-style: none; margin: 0; padding: 0; display: flex; flex-direction: column; }
  .msg { padding: 10px 0; border-top: var(--line-thin) solid var(--line); }
  .msg:first-child { border-top: 0; }
  .msg.unread { border-left: 6px solid var(--accent); padding-left: var(--sp-3); }
  .msg.unread .msg-text { font-weight: var(--fw-medium); }
  .msg.done { opacity: 0.75; }
  .msg-meta { margin: 0; font-size: 13px; color: var(--text-secondary); }
  .msg-text { margin: 4px 0 0; white-space: pre-wrap; overflow-wrap: anywhere; line-height: 1.45; }
  .msg-text.mono { font-family: ui-monospace, monospace; font-size: 13px; }
  .msg-actions { display: flex; flex-wrap: wrap; gap: 0 var(--sp-4); }

  /* ── Lignes ── */
  .rows { list-style: none; margin: 0; padding: 0; }

  .row {
    display: flex;
    align-items: center;
    gap: var(--sp-3);
    min-height: 60px;
    padding: var(--sp-2) 0;
  }
  .rows .row + .row { border-top: var(--line-thin) solid var(--line); }

  .row-icon {
    width: 40px;
    height: 40px;
    flex-shrink: 0;
    border: var(--line-w) solid var(--line);
    background: var(--highlight);
    color: var(--text);
    display: flex;
    align-items: center;
    justify-content: center;
  }
  .row.inactive .row-icon { background: var(--surface-sunken); color: var(--text-secondary); }
  .row.inactive .row-name { color: var(--text-secondary); }

  .row-main {
    flex: 1;
    min-width: 0;
    display: flex;
    flex-direction: column;
    gap: 3px;
  }

  .row-name { font-size: var(--fs-base); font-weight: var(--fw-bold); color: var(--text); overflow-wrap: anywhere; }

  .row-meta {
    display: flex;
    flex-wrap: wrap;
    align-items: center;
    gap: 6px;
    font-size: 13px;
    color: var(--text-secondary);
  }

  /* Statut : puce carrée */
  .status {
    padding: 1px 6px;
    border: var(--line-thin) solid var(--line);
    font-size: 11px;
    font-weight: var(--fw-bold);
    text-transform: uppercase;
    letter-spacing: var(--tracking-caps);
  }
  .status-valide { background: var(--accent); color: var(--on-accent); }
  .status-utilisee { background: var(--success-bg); color: var(--success); }
  .status-expiree, .status-annulee { background: var(--surface-sunken); color: var(--text-secondary); }

  .btn-row-action { flex-shrink: 0; min-height: 44px; padding: 0 var(--sp-3); font-size: var(--fs-sm); }
  .btn-cancel { color: var(--error); }

  .link-btn {
    display: inline-flex;
    align-items: center;
    align-self: flex-start;
    gap: 6px;
    min-height: 44px;
    padding: 0 4px;
    margin-left: -4px;
    border: none;
    background: none;
    color: var(--text);
    font-family: var(--font-body);
    font-size: var(--fs-sm);
    font-weight: var(--fw-bold);
    text-decoration: underline;
    text-decoration-thickness: 2px;
    text-underline-offset: 3px;
    cursor: pointer;
    touch-action: manipulation;
  }
  .link-btn:active:not(:disabled) { transform: translate(1px, 1px); }
  .link-btn:disabled { opacity: 0.5; }
  .link-btn.btn-cancel { color: var(--error); }

  .chev { display: inline-flex; transition: transform var(--dur-base) var(--ease-out); }
  .chev.open { transform: rotate(180deg); }

  /* ── Statistiques : blocs carrés bordés, gros chiffres ── */
  .totals {
    display: grid;
    grid-template-columns: repeat(3, 1fr);
    gap: var(--sp-3);
  }

  .total {
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    gap: 2px;
    aspect-ratio: 1;
    min-width: 0;
    padding: var(--sp-2);
    border: var(--line-w) solid var(--line);
    background: var(--surface);
    box-shadow: var(--shadow-sm);
  }

  .total-n {
    font-size: var(--fs-3xl);
    font-weight: var(--fw-bold);
    color: var(--text);
    font-variant-numeric: tabular-nums;
    line-height: 1;
    letter-spacing: -0.03em;
  }

  .total-l {
    font-size: var(--fs-xs);
    font-weight: var(--fw-bold);
    text-transform: uppercase;
    letter-spacing: var(--tracking-caps);
    color: var(--text-secondary);
  }

  .stats-sub {
    margin: var(--sp-2) 0 -2px;
    padding: 5px 10px;
    background: var(--band);
    color: var(--text-on-band);
    font-size: 13px;
    font-weight: var(--fw-bold);
    text-transform: uppercase;
    letter-spacing: var(--tracking-caps);
  }
  .stats-list { list-style: none; margin: 0; padding: 0; display: flex; flex-direction: column; }
  .stats-list li {
    display: flex;
    justify-content: space-between;
    align-items: baseline;
    gap: var(--sp-3);
    padding: 10px 2px;
    font-size: 15px;
    border-bottom: var(--line-thin) solid var(--line);
  }
  .stats-list li:last-child { border-bottom: none; }
  .stats-list span { color: var(--text-secondary); }
  .stats-list strong { font-variant-numeric: tabular-nums; color: var(--text); font-weight: var(--fw-bold); }

  /* ── Groupes de familles ── */
  .sf-list { list-style: none; margin: 0; padding: 0; display: flex; flex-direction: column; gap: var(--sp-3); }

  .sf {
    padding: var(--sp-3);
    border: var(--line-w) solid var(--line);
    background: var(--surface-sunken);
    animation: fade-up var(--dur-sheet) var(--ease-out) calc(var(--i, 0) * 45ms) backwards;
  }

  .sf-head { display: flex; align-items: flex-start; gap: var(--sp-3); }

  .sf-initial {
    width: 40px;
    height: 40px;
    flex-shrink: 0;
    border: var(--line-w) solid var(--line);
    background: var(--accent);
    color: var(--on-accent);
    font-weight: var(--fw-bold);
    font-size: var(--fs-lg);
    text-transform: uppercase;
    display: flex;
    align-items: center;
    justify-content: center;
  }

  .fam-list {
    list-style: none;
    margin: 10px 0 0 52px;
    padding: 0;
    border-left: var(--line-w) solid var(--line);
  }

  .fam-row {
    display: flex;
    align-items: baseline;
    justify-content: space-between;
    gap: 10px;
    padding: 6px 0 6px var(--sp-3);
    font-size: var(--fs-sm);
  }

  .fam-name { color: var(--text); font-weight: var(--fw-bold); overflow-wrap: anywhere; min-width: 0; }
  .fam-count { flex-shrink: 0; color: var(--text-secondary); font-variant-numeric: tabular-nums; }

  /* ── États ── */
  .state { align-items: center; text-align: center; gap: 6px; }
  .state-icon { color: var(--text); }
  .state-title { font-weight: var(--fw-bold); font-size: var(--fs-base); }
  .state-text { color: var(--text-secondary); font-size: var(--fs-sm); margin-bottom: 6px; }

  .state-error {
    display: flex;
    flex-direction: column;
    align-items: flex-start;
    gap: 10px;
    padding: var(--sp-3);
    background: var(--error-bg);
    border: var(--line-w) solid var(--error);
    color: var(--text);
    font-size: var(--fs-sm);
    line-height: 1.4;
  }

  /* ── Squelettes ── */
  .sk-row { animation: fade-up var(--dur-sheet) var(--ease-out) backwards; }
  .sk-dot {
    width: 40px;
    height: 40px;
    flex-shrink: 0;
    border: var(--line-w) solid var(--line);
    background: var(--surface-sunken);
  }
  .sk-body { flex: 1; display: flex; flex-direction: column; gap: var(--sp-2); }
  .sk-line {
    height: 12px;
    background: var(--surface-sunken);
    animation: sk-pulse 1.2s ease-in-out infinite;
  }
  .sk-short { width: 45%; }

  @keyframes sk-pulse { 50% { opacity: 0.45; } }

  @media (hover: hover) and (pointer: fine) {
    .link-btn:hover { text-decoration-thickness: 3px; }
  }

  @media (min-width: 900px) {
    .back-link { margin-top: calc(24px + env(safe-area-inset-top, 0px)); }
  }
  .catalogue-text { font-size: var(--fs-sm); color: var(--text-secondary); margin-bottom: var(--sp-3); }
  .catalogue-btn { width: 100%; }
</style>
