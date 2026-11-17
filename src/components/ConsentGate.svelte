<script lang="ts">
  // Fenêtre d'accueil obligatoire (v2.0.0, lot C) : pseudo + tranche d'âge + acceptation
  // des conditions, en une seule fois. Rien d'autre n'est accessible avant.
  // Moins de 15 ans : écran d'attente jusqu'à l'accord d'un parent du foyer.
  import Icon from './Icon.svelte'
  import ErrorState from './ErrorState.svelte'
  import { href } from '../lib/router.svelte'
  import { profileState } from '../lib/profile.svelte'
  import { consent, loadConsent, setConsentStatus } from '../lib/consent.svelte'
  import { acceptTerms, pseudoAvailable, consentErrorMessage } from '../lib/api/conformite'
  import { pseudoProblem, suggestPseudo, PSEUDO_MAX } from '../lib/pseudo'
  import { AGE_LABELS, TERMS_DATE_LABEL, type AgeGroup } from '../lib/legal'

  let { onsignout }: { onsignout: () => void } = $props()

  const existingPseudo = $derived(profileState.profile?.pseudo ?? null)
  let pseudo = $state(suggestPseudo(profileState.profile?.display_name ?? ''))
  let pseudoError = $state<string | null>(null)
  let pseudoFree = $state<boolean | null>(null)
  let age = $state<AgeGroup | null>(null)
  let accepted = $state(false)
  let busy = $state(false)
  let formError = $state<string | null>(null)
  let checking = $state(false)

  const canSubmit = $derived(
    !busy && age !== null && accepted && (existingPseudo !== null || (pseudoProblem(pseudo) === null && pseudoFree !== false)),
  )

  // Pas de défilement de la page derrière
  $effect(() => {
    const before = document.body.style.overflow
    document.body.style.overflow = 'hidden'
    return () => {
      document.body.style.overflow = before
    }
  })

  async function checkPseudo() {
    pseudoFree = null
    pseudoError = pseudoProblem(pseudo)
    if (pseudoError) return
    const asked = pseudo.trim()
    try {
      const free = await pseudoAvailable(asked)
      if (asked !== pseudo.trim()) return // on a retapé entre-temps
      pseudoFree = free
      if (!free) pseudoError = 'Ce pseudo est déjà pris'
    } catch {
      // pas grave : la base vérifiera à l'envoi
    }
  }

  async function submit() {
    if (!canSubmit || !age) return
    const id = profileState.profile?.id
    if (!id) return
    busy = true
    formError = null
    try {
      const status = await acceptTerms(age, existingPseudo ? null : pseudo.trim())
      if (!existingPseudo && profileState.profile) profileState.profile.pseudo = pseudo.trim()
      setConsentStatus(id, status)
    } catch (e: any) {
      const msg = consentErrorMessage(e)
      if (/pseudo/i.test(msg)) pseudoError = msg
      else formError = msg
    } finally {
      busy = false
    }
  }

  async function recheck() {
    const id = profileState.profile?.id
    if (!id) return
    checking = true
    await loadConsent(id)
    checking = false
  }
</script>

<div class="screen" role="dialog" aria-modal="true" aria-labelledby="gate-title">
  <div class="content">
    {#if consent.status === 'attente_parent'}
      <div class="logo" aria-hidden="true"><Icon name="users" size={36} /></div>
      <h1 id="gate-title">Il manque l’accord d’un parent</h1>
      <p class="lead">Comme tu as moins de 15 ans, un parent doit donner son accord pour que tu utilises Lichouz.</p>
      <ol class="card steps">
        <li>Ton parent ouvre Lichouz sur <strong>son</strong> téléphone, avec son compte.</li>
        <li>Il va dans <strong>Mon compte → Vie privée</strong>.</li>
        <li>Il touche <strong>« Je donne mon accord »</strong> à côté de ton prénom.</li>
      </ol>
      <div class="actions">
        <button class="btn btn-primary" onclick={recheck} aria-busy={checking}>
          <Icon name="refresh" size={18} /> {checking ? 'Vérification…' : 'C’est fait, vérifier'}
        </button>
        <button class="link" onclick={onsignout}>Se déconnecter</button>
      </div>
    {:else if consent.status === 'erreur'}
      <h1 id="gate-title" class="sr-only">Connexion impossible</h1>
      <ErrorState
        title="Connexion impossible"
        message="L’appli n’arrive pas à vérifier ton compte. Vérifie ton réseau puis réessaie."
        onretry={recheck}
        busy={checking}
      />
      <button class="link" onclick={onsignout}>Se déconnecter</button>
    {:else}
      <div class="logo" aria-hidden="true"><Icon name="shield" size={36} /></div>
      <h1 id="gate-title">Avant de continuer</h1>
      <p class="lead">Lichouz a maintenant des règles écrites : ce qu’on peut y faire, et ce qu’on fait de tes données. Trois choses à faire, une seule fois.</p>

      <form class="card form" onsubmit={(e) => { e.preventDefault(); submit() }}>
        <!-- 1. Pseudo -->
        <div class="field">
          <span class="step-num" aria-hidden="true">1</span>
          {#if existingPseudo}
            <span class="label-text">Ton pseudo</span>
            <p class="done"><Icon name="check" size={18} /> <strong>{existingPseudo}</strong></p>
          {:else}
            <label for="gate-pseudo" class="label-text">Choisis ton pseudo</label>
            <p class="help">Unique dans toute l’appli. Lettres sans accent, chiffres, « _ » et « . ».</p>
            <input
              id="gate-pseudo"
              class="input"
              class:error={pseudoError != null}
              aria-invalid={pseudoError != null}
              aria-describedby={pseudoError ? 'gate-pseudo-error' : undefined}
              autocomplete="username"
              autocapitalize="off"
              spellcheck="false"
              maxlength={PSEUDO_MAX}
              placeholder="ex. cheffe_margot"
              bind:value={pseudo}
              oninput={() => { pseudoError = null; pseudoFree = null }}
              onblur={checkPseudo}
            />
            {#if pseudoError}
              <p id="gate-pseudo-error" class="field-error" role="alert">{pseudoError}</p>
            {:else if pseudoFree}
              <p class="ok"><Icon name="check" size={16} /> Disponible</p>
            {/if}
          {/if}
        </div>

        <!-- 2. Âge -->
        <fieldset class="field">
          <span class="step-num" aria-hidden="true">2</span>
          <legend class="label-text">Ton âge</legend>
          <div class="choices">
            {#each Object.entries(AGE_LABELS) as [value, label] (value)}
              <label class="choice" class:active={age === value}>
                <input type="radio" name="age" {value} bind:group={age} />
                <span>{label}</span>
              </label>
            {/each}
          </div>
          {#if age === 'moins_15'}
            <p class="note">Avant 15 ans, la loi demande aussi l’accord d’un parent. Après avoir validé, un parent de ton foyer le donnera depuis son compte.</p>
          {/if}
        </fieldset>

        <!-- 3. Conditions -->
        <div class="field">
          <span class="step-num" aria-hidden="true">3</span>
          <span class="label-text">Les conditions</span>
          <p class="help">
            À lire : <a href={href('cgu')}>conditions d’utilisation</a>, <a href={href('confidentialite')}>confidentialité</a>
            et <a href={href('stockage')}>stockage</a> (version du {TERMS_DATE_LABEL}).
          </p>
          <label class="accept">
            <input type="checkbox" class="check" bind:checked={accepted} />
            <span>J’ai lu et j’accepte les conditions d’utilisation et la politique de confidentialité.</span>
          </label>
        </div>

        {#if formError}<p class="field-error" role="alert">{formError}</p>{/if}
        <button type="submit" class="btn btn-primary submit" disabled={!canSubmit} aria-busy={busy}>
          {busy ? 'Enregistrement…' : 'Valider et entrer'}
        </button>
      </form>
      <button class="link" onclick={onsignout}>Se déconnecter</button>
    {/if}
  </div>
</div>

<style>
  .screen {
    position: fixed;
    inset: 0;
    z-index: 200;
    overflow-y: auto;
    overscroll-behavior: contain;
    background: var(--page);
    display: flex;
    justify-content: center;
    padding: calc(var(--sp-5) + env(safe-area-inset-top, 0px)) var(--gutter) calc(var(--sp-5) + env(safe-area-inset-bottom, 0px));
    animation: ui-fade var(--dur-base) var(--ease-out);
  }
  .content {
    width: 100%;
    max-width: 460px;
    margin: auto 0;
    display: grid;
    gap: var(--sp-4);
  }
  .logo {
    width: 72px;
    height: 72px;
    display: grid;
    place-items: center;
    justify-self: center;
    background: var(--accent);
    color: var(--on-accent);
    border: var(--line-w) solid var(--line);
    box-shadow: var(--shadow-md);
  }
  h1 { font-size: var(--fs-2xl); line-height: 1.05; text-align: center; }
  .lead { text-align: center; color: var(--text-secondary); line-height: 1.45; }

  .form { padding: var(--sp-4); display: grid; gap: var(--sp-5); }
  .field { position: relative; display: grid; gap: var(--sp-2); border: none; margin: 0; padding: 0 0 0 40px; min-width: 0; }
  .step-num {
    position: absolute;
    left: 0;
    top: -2px;
    width: 28px;
    height: 28px;
    display: grid;
    place-items: center;
    background: var(--accent);
    color: var(--on-accent);
    border: var(--line-w) solid var(--line);
    font-weight: var(--fw-bold);
    font-size: var(--fs-sm);
  }
  legend { padding: 0; margin-bottom: var(--sp-2); }
  .label-text {
    font-size: var(--fs-sm);
    font-weight: var(--fw-bold);
    text-transform: uppercase;
    letter-spacing: var(--tracking-caps);
  }
  .help, .note { font-size: var(--fs-sm); color: var(--text-secondary); line-height: 1.45; }
  .note { color: var(--text); background: var(--highlight); border: var(--line-w) solid var(--line); padding: 9px 12px; }
  .help a { color: var(--text); font-weight: var(--fw-bold); text-decoration-thickness: 2px; text-underline-offset: 3px; }
  .done, .ok { display: flex; align-items: center; gap: var(--sp-2); }
  .ok { font-size: var(--fs-sm); font-weight: var(--fw-bold); }
  .field-error {
    font-size: var(--fs-sm);
    line-height: 1.4;
    background: var(--error-bg);
    border: var(--line-w) solid var(--error);
    padding: 9px 12px;
  }

  .choices { display: grid; gap: var(--sp-2); }
  .choice, .accept {
    min-height: var(--tap);
    display: flex;
    align-items: center;
    gap: var(--sp-3);
    padding: var(--sp-2) var(--sp-3);
    border: var(--line-w) solid var(--line);
    background: var(--surface);
    cursor: pointer;
    line-height: 1.35;
    touch-action: manipulation;
  }
  .choice.active { background: var(--highlight); box-shadow: var(--shadow-sm); font-weight: var(--fw-bold); }
  .choice input { width: 22px; height: 22px; flex: none; accent-color: var(--accent); margin: 0; }
  .accept .check { flex: none; }
  .accept { align-items: flex-start; }
  .accept span { padding-top: 1px; }

  .submit { min-height: 52px; width: 100%; }
  .steps { margin: 0; padding: var(--sp-4) var(--sp-4) var(--sp-4) calc(var(--sp-4) + 20px); display: grid; gap: var(--sp-3); line-height: 1.45; }
  .actions { display: grid; gap: var(--sp-3); }
  .actions .btn { min-height: 52px; width: 100%; }
  .link {
    justify-self: center;
    min-height: 44px;
    padding: 0 var(--sp-3);
    background: none;
    border: none;
    color: var(--text);
    font: inherit;
    font-size: var(--fs-sm);
    font-weight: var(--fw-bold);
    text-decoration: underline;
    text-decoration-thickness: 2px;
    text-underline-offset: 3px;
    cursor: pointer;
  }

  .sr-only { position: absolute; width: 1px; height: 1px; overflow: hidden; clip: rect(0 0 0 0); white-space: nowrap; }

  @media (hover: hover) and (pointer: fine) {
    .choice:hover, .accept:hover, .link:hover { background: var(--highlight); }
  }
</style>
