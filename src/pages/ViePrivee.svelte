<script lang="ts">
  // Vie privée (v2.0.0, lot C) : pseudo, documents, télécharger mes données,
  // accords parentaux (adultes du foyer), lien vers la suppression du compte.
  import Icon from '../components/Icon.svelte'
  import ConfirmDialog from '../components/ConfirmDialog.svelte'
  import { href } from '../lib/router.svelte'
  import { toast } from '../lib/toast.svelte'
  import { profileState } from '../lib/profile.svelte'
  import { TERMS_DATE_LABEL } from '../lib/legal'
  import { pseudoProblem, PSEUDO_MAX } from '../lib/pseudo'
  import {
    exportMyData,
    fetchParentalConsents,
    confirmParentalConsent,
    revokeParentalConsent,
    updatePseudo,
    consentErrorMessage,
    type ParentalConsent,
  } from '../lib/api/conformite'

  // ── Pseudo ──
  const currentPseudo = $derived(profileState.profile?.pseudo ?? '')
  let pseudo = $state(profileState.profile?.pseudo ?? '')
  let pseudoError = $state<string | null>(null)
  let savingPseudo = $state(false)
  const changedAt = $derived(profileState.profile?.pseudo_changed_at ?? null)
  const nextChange = $derived.by(() => {
    if (!changedAt) return null
    const d = new Date(changedAt)
    d.setDate(d.getDate() + 30)
    return d > new Date() ? d.toLocaleDateString('fr-FR', { day: 'numeric', month: 'long' }) : null
  })

  async function savePseudo() {
    const id = profileState.profile?.id
    if (!id) return
    pseudoError = pseudoProblem(pseudo)
    if (pseudoError) return
    savingPseudo = true
    try {
      await updatePseudo(id, pseudo)
      if (profileState.profile) {
        const caseOnly = pseudo.trim().toLowerCase() === currentPseudo.toLowerCase()
        profileState.profile.pseudo = pseudo.trim()
        if (!caseOnly) profileState.profile.pseudo_changed_at = new Date().toISOString()
      }
      toast.success('Pseudo enregistré')
    } catch (e) {
      pseudoError = consentErrorMessage(e)
    } finally {
      savingPseudo = false
    }
  }

  // ── Télécharger mes données ──
  let exporting = $state(false)
  async function download() {
    exporting = true
    try {
      const data = await exportMyData()
      const blob = new Blob([JSON.stringify(data, null, 2)], { type: 'application/json' })
      const url = URL.createObjectURL(blob)
      const a = document.createElement('a')
      a.href = url
      a.download = `lichouz-mes-donnees-${new Date().toISOString().slice(0, 10)}.json`
      document.body.appendChild(a)
      a.click()
      a.remove()
      setTimeout(() => URL.revokeObjectURL(url), 1000)
      toast.success('Fichier téléchargé')
    } catch (e) {
      toast.error(consentErrorMessage(e))
    } finally {
      exporting = false
    }
  }

  // ── Accords parentaux ──
  let children = $state<ParentalConsent[]>([])
  let loadingChildren = $state(true)
  let confirmFor = $state<ParentalConsent | null>(null)
  let revokeFor = $state<ParentalConsent | null>(null)
  let isParent = $state(false)

  async function loadChildren() {
    try {
      children = await fetchParentalConsents()
    } catch {
      children = []
    } finally {
      loadingChildren = false
    }
  }
  $effect(() => {
    void loadChildren()
  })

  async function doConfirm() {
    const c = confirmFor
    confirmFor = null
    if (!c || !isParent) return
    try {
      await confirmParentalConsent(c.profile_id)
      toast.success(`Accord donné pour ${c.display_name}`)
      await loadChildren()
    } catch (e: any) {
      toast.error(e?.message ?? 'Accord impossible')
    }
  }

  async function doRevoke() {
    const c = revokeFor
    revokeFor = null
    if (!c) return
    try {
      await revokeParentalConsent(c.profile_id)
      toast.success(`Accord retiré pour ${c.display_name}`)
      await loadChildren()
    } catch (e: any) {
      toast.error(e?.message ?? 'Retrait impossible')
    }
  }
</script>

<div class="page">
  <a href={href('compte')} class="back-link"><Icon name="arrow-left" size={18} /> Mon compte</a>

  <header class="head">
    <h1>Vie privée</h1>
    <p class="head-sub">Ton pseudo, tes données, les règles de l’appli.</p>
  </header>

  <!-- Pseudo -->
  <section class="card" aria-labelledby="pseudo-title">
    <h2 id="pseudo-title" class="section-title"><span class="section-icon"><Icon name="user" size={18} /></span> Mon pseudo</h2>
    <label for="pv-pseudo" class="sr-only">Pseudo</label>
    <input
      id="pv-pseudo"
      class="input"
      class:error={pseudoError != null}
      aria-invalid={pseudoError != null}
      aria-describedby="pv-pseudo-help"
      autocapitalize="off"
      spellcheck="false"
      maxlength={PSEUDO_MAX}
      bind:value={pseudo}
      oninput={() => (pseudoError = null)}
    />
    <p id="pv-pseudo-help" class="help">
      Unique dans toute l’appli. Changement possible une fois tous les 30 jours{nextChange ? ` (prochain : à partir du ${nextChange})` : ''} ;
      les majuscules se changent quand tu veux.
    </p>
    {#if pseudoError}<p class="field-error" role="alert">{pseudoError}</p>{/if}
    <button class="btn btn-primary" onclick={savePseudo} disabled={savingPseudo || pseudo.trim() === currentPseudo} aria-busy={savingPseudo}>
      {savingPseudo ? 'Enregistrement…' : 'Enregistrer le pseudo'}
    </button>
  </section>

  <!-- Accords parentaux -->
  {#if !loadingChildren && children.length > 0}
    <section class="card" aria-labelledby="parent-title">
      <h2 id="parent-title" class="section-title"><span class="section-icon"><Icon name="users" size={18} /></span> Accords parentaux</h2>
      <p class="help">Avant 15 ans, un parent doit donner son accord pour que son enfant utilise Lichouz. Tu peux le retirer quand tu veux : l’enfant ne pourra plus ouvrir l’appli jusqu’à un nouvel accord.</p>
      <ul class="kids">
        {#each children as c (c.profile_id)}
          <li class="kid">
            <span class="kid-name">
              <strong>{c.display_name}</strong>
              <span class="kid-state">{c.confirmed_at ? 'Accord donné' : 'En attente de ton accord'}</span>
            </span>
            {#if c.confirmed_at}
              <button class="btn btn-outline" onclick={() => (revokeFor = c)}>Retirer</button>
            {:else}
              <button class="btn btn-primary" onclick={() => { isParent = false; confirmFor = c }}>Je donne mon accord</button>
            {/if}
          </li>
        {/each}
      </ul>
    </section>
  {/if}

  <!-- Mes données -->
  <section class="card" aria-labelledby="data-title">
    <h2 id="data-title" class="section-title"><span class="section-icon"><Icon name="archive" size={18} /></span> Mes données</h2>
    <p class="help">Un fichier avec tout ce que Lichouz garde sur toi : compte, profil, recettes écrites, repas cuisinés, événements, messages, erreurs. Format JSON, lisible par d’autres applis.</p>
    <button class="btn btn-outline row-btn" onclick={download} aria-busy={exporting} disabled={exporting}>
      <Icon name="arrow-right" size={18} /> {exporting ? 'Préparation…' : 'Télécharger mes données'}
    </button>
    <p class="help">Corriger : ton prénom dans <a href={href('compte')}>Mon compte</a>, tes recettes dans <a href={href('mes-recettes')}>Mes recettes</a>. Tout effacer : <a href={href('compte')}>Mon compte → Supprimer mon compte</a> (tout en bas).</p>
  </section>

  <!-- Documents -->
  <nav class="links card" aria-label="Documents">
    <a class="link-row" href={href('cgu')}>
      <span class="section-icon"><Icon name="book" size={18} /></span>
      <span class="link-text"><span class="link-title">Conditions d’utilisation</span><span class="link-sub">Version du {TERMS_DATE_LABEL}</span></span>
      <Icon name="chevron-right" size={18} />
    </a>
    <a class="link-row" href={href('confidentialite')}>
      <span class="section-icon"><Icon name="shield" size={18} /></span>
      <span class="link-text"><span class="link-title">Confidentialité</span><span class="link-sub">Ce qu’on garde, qui le voit, combien de temps</span></span>
      <Icon name="chevron-right" size={18} />
    </a>
    <a class="link-row" href={href('stockage')}>
      <span class="section-icon"><Icon name="settings" size={18} /></span>
      <span class="link-text"><span class="link-title">Stockage sur ce téléphone</span><span class="link-sub">Pas de cookie de pub ni de traceur</span></span>
      <Icon name="chevron-right" size={18} />
    </a>
  </nav>
</div>

{#if confirmFor}
  <ConfirmDialog
    title="Accord pour {confirmFor.display_name}"
    confirmLabel="Je donne mon accord"
    cancelLabel="Annuler"
    confirmDisabled={!isParent}
    onconfirm={doConfirm}
    oncancel={() => (confirmFor = null)}
  >
    <p>{confirmFor.display_name} a moins de 15 ans. En donnant ton accord, tu acceptes pour lui ou elle les <a href={href('cgu')}>conditions</a> et la <a href={href('confidentialite')}>politique de confidentialité</a>.</p>
    <label class="accept">
      <input type="checkbox" class="check" bind:checked={isParent} />
      <span>Je suis son parent (ou j’ai l’autorité parentale).</span>
    </label>
  </ConfirmDialog>
{/if}

{#if revokeFor}
  <ConfirmDialog
    title="Retirer l’accord ?"
    confirmLabel="Retirer"
    cancelLabel="Annuler"
    danger
    onconfirm={doRevoke}
    oncancel={() => (revokeFor = null)}
  >
    <p>{revokeFor.display_name} ne pourra plus ouvrir Lichouz tant qu’un parent n’aura pas redonné son accord. Ses données restent gardées.</p>
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
  .head h1 { padding-right: 56px; }
  .head-sub { margin-top: var(--sp-1); font-size: 15px; font-weight: var(--fw-medium); color: var(--text-secondary); }
  .card { padding: var(--sp-4); display: flex; flex-direction: column; gap: var(--sp-3); }
  .section-title { display: flex; align-items: center; gap: var(--sp-2); font-size: var(--fs-lg); }
  .section-icon {
    width: 32px; height: 32px; flex: none;
    display: grid; place-items: center;
    background: var(--accent); color: var(--on-accent);
    border: var(--line-w) solid var(--line);
  }
  .help { font-size: var(--fs-sm); color: var(--text-secondary); line-height: 1.45; }
  .help a { color: var(--text); font-weight: var(--fw-bold); text-decoration-thickness: 2px; text-underline-offset: 3px; }
  .field-error {
    font-size: var(--fs-sm);
    line-height: 1.4;
    background: var(--error-bg);
    border: var(--line-w) solid var(--error);
    padding: 9px 12px;
  }
  .row-btn { display: inline-flex; gap: var(--sp-2); align-items: center; justify-content: center; }
  .kids { list-style: none; margin: 0; padding: 0; display: grid; gap: var(--sp-3); }
  .kid { display: flex; align-items: center; justify-content: space-between; gap: var(--sp-3); flex-wrap: wrap; }
  .kid-name { display: flex; flex-direction: column; }
  .kid-state { font-size: var(--fs-sm); color: var(--text-secondary); }
  .kid .btn { flex: none; width: auto; }
  .links { padding: 0; gap: 0; }
  .link-row {
    display: flex;
    align-items: center;
    gap: var(--sp-3);
    min-height: 64px;
    padding: var(--sp-3) var(--sp-4);
    color: var(--text);
    text-decoration: none;
  }
  .link-row + .link-row { border-top: var(--line-w) solid var(--line); }
  .link-text { flex: 1; display: flex; flex-direction: column; min-width: 0; }
  .link-title { font-weight: var(--fw-bold); }
  .link-sub { font-size: var(--fs-sm); color: var(--text-secondary); }
  .accept { display: flex; align-items: flex-start; gap: var(--sp-3); margin-top: var(--sp-3); line-height: 1.4; cursor: pointer; }
  .accept .check { flex: none; }
  .sr-only { position: absolute; width: 1px; height: 1px; overflow: hidden; clip: rect(0 0 0 0); white-space: nowrap; }

  @media (hover: hover) and (pointer: fine) {
    .link-row:hover { background: var(--highlight); }
  }
</style>
