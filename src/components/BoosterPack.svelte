<script lang="ts">
  // Booster du jour (v2.4.0) : un paquet scellé au centre de l'accueil.
  // Toucher → le haut se déchire et s'envole, le paquet s'efface, puis
  // onopen() : l'accueil fait sortir les 5 cartes vers leur place.
  // « Passer » → onskip() : les cartes arrivent directement.
  // Seuls transform et opacity sont animés ; mouvement réduit = jamais affiché
  // (l'accueil montre les cartes directement).
  import CatLogo from './CatLogo.svelte'

  interface Props {
    /** false tant que le tirage n'est pas prêt : le paquet attend */
    ready: boolean
    onopen: () => void
    onskip: () => void
  }
  let { ready, onopen, onskip }: Props = $props()

  /** Durée de la déchirure avant de lâcher les cartes (ms) */
  const TEAR_MS = 650

  let tearing = $state(false)

  function open() {
    if (tearing || !ready) return
    tearing = true
    navigator.vibrate?.(30)
    setTimeout(onopen, TEAR_MS)
  }
</script>

<div class="booster" class:tearing>
  <button class="pack" onclick={open} disabled={!ready} aria-label="Ouvrir le booster du jour : 5 recettes">
    <span class="pack-top" aria-hidden="true">
      <span class="tear-hint">Déchire ici</span>
    </span>
    <span class="pack-body" aria-hidden="true">
      <span class="pack-logo"><CatLogo size={56} /></span>
      <span class="pack-title">Booster<br />du jour</span>
      <span class="pack-sub">5 recettes</span>
    </span>
  </button>
  <p class="hint" aria-hidden="true">{ready ? 'Touche pour ouvrir' : 'Préparation…'}</p>
  <button class="skip" onclick={onskip} disabled={tearing}>Passer</button>
</div>

<style>
  .booster {
    position: absolute;
    inset: 0;
    z-index: 2;
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    gap: var(--sp-3);
    pointer-events: none;
  }
  .booster > * { pointer-events: auto; }

  .pack {
    position: relative;
    width: 168px;
    height: 236px;
    padding: 0;
    border: none;
    background: none;
    cursor: pointer;
    touch-action: manipulation;
    -webkit-tap-highlight-color: transparent;
    animation: pack-in var(--dur-sheet) var(--ease-snap) both, pack-float 2.8s ease-in-out 0.5s infinite alternate;
  }
  .pack:disabled { cursor: progress; }
  .pack:focus-visible { outline: 3px solid var(--accent); outline-offset: 6px; }

  /* Haut du paquet : bande avec ligne pointillée, c'est elle qui part */
  .pack-top {
    position: absolute;
    inset: 0 0 auto 0;
    height: 42px;
    display: grid;
    place-items: center;
    background: var(--band);
    color: var(--text-on-band);
    border: var(--line-w) solid var(--line);
    border-bottom: 2px dashed var(--text-on-band);
    box-shadow: var(--shadow-md);
    transform-origin: 10% 100%;
  }
  .tear-hint {
    font-size: 11px;
    font-weight: var(--fw-bold);
    text-transform: uppercase;
    letter-spacing: var(--tracking-caps);
  }

  .pack-body {
    position: absolute;
    inset: 40px 0 0 0;
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    gap: var(--sp-2);
    background: var(--accent);
    color: var(--on-accent);
    border: var(--line-w) solid var(--line);
    box-shadow: var(--shadow-md);
  }
  .pack-logo {
    display: grid;
    place-items: center;
    width: 72px;
    height: 72px;
    background: var(--surface);
    border: var(--line-w) solid var(--line);
  }
  .pack-title {
    font-family: var(--font-display, inherit);
    font-weight: var(--fw-bold);
    font-size: 22px;
    line-height: 1;
    text-transform: uppercase;
    text-align: center;
  }
  .pack-sub { font-size: 13px; font-weight: var(--fw-bold); }

  .hint { font-size: 14px; font-weight: var(--fw-bold); color: var(--text); }

  .skip {
    min-height: 44px;
    min-width: 44px;
    padding: 0 var(--sp-3);
    border: none;
    background: none;
    color: var(--text);
    font: inherit;
    font-weight: var(--fw-bold);
    text-decoration: underline;
    text-decoration-thickness: 2px;
    text-underline-offset: 3px;
    cursor: pointer;
    touch-action: manipulation;
  }

  /* ── Déchirure ── */
  .tearing .pack { animation: pack-shake 0.25s ease-in-out; }
  .tearing .pack-top { animation: tear-off 0.5s var(--ease-out) forwards; }
  .tearing .pack-body { animation: pack-burst 0.35s ease-in 0.3s forwards; }
  .tearing .hint, .tearing .skip { opacity: 0; transition: opacity var(--dur-fast); }

  @keyframes pack-in {
    from { opacity: 0; transform: translate3d(0, 30px, 0) scale(0.9); }
  }
  @keyframes pack-float {
    from { transform: translate3d(0, -4px, 0) rotate(-2deg); }
    to   { transform: translate3d(0, 4px, 0) rotate(2deg); }
  }
  @keyframes pack-shake {
    25% { transform: rotate(-4deg); }
    75% { transform: rotate(4deg); }
  }
  @keyframes tear-off {
    to { transform: translate3d(70px, -120px, 0) rotate(35deg); opacity: 0; }
  }
  @keyframes pack-burst {
    to { transform: scale(1.25); opacity: 0; }
  }

  @media (prefers-reduced-motion: reduce) {
    .pack, .tearing .pack, .tearing .pack-top, .tearing .pack-body { animation: none; }
  }
</style>
