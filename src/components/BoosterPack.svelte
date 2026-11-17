<script lang="ts">
  // Booster du jour (v2.4.0) : un paquet scellé au centre de l'accueil.
  // - Au repos : il flotte, un reflet brillant passe de temps en temps.
  // - Glisser le doigt (ou la souris) dessus : il s'incline en 3D et le reflet
  //   suit le doigt, comme une carte brillante qu'on tourne dans la lumière.
  // - Toucher sans glisser : la bande du haut se déchire et part sur le côté,
  //   puis le paquet descend et disparaît ; onopen() est appelé pendant la
  //   descente (les cartes en jaillissent), ondone() à la fin.
  // - « Passer » → onskip() : les cartes arrivent directement.
  // Seuls transform et opacity sont animés ; mouvement réduit = jamais affiché
  // (l'accueil montre les cartes directement).
  import CatLogo from './CatLogo.svelte'

  interface Props {
    /** false tant que le tirage n'est pas prêt : le paquet attend */
    ready: boolean
    onopen: () => void
    ondone?: () => void
    onskip: () => void
    /** Dès le toucher (v2.4.1) : centre du paquet dans la fenêtre, pour l'aura */
    ontear?: (center: { x: number; y: number }) => void
  }
  let { ready, onopen, ondone, onskip, ontear }: Props = $props()
  let packEl: HTMLButtonElement | undefined = $state()

  /** Déchirure de la bande, puis lâcher des cartes pendant la descente (ms) */
  const TEAR_MS = 380
  const DONE_MS = 1000
  /** Au-delà, le geste est une inclinaison, pas un toucher */
  const MOVE_TOLERANCE = 10

  let opening = $state(false)

  // ── Inclinaison + reflet (valeurs de -1 à 1 depuis le centre) ──
  let tx = $state(0)
  let ty = $state(0)
  let tilting = $state(false)
  let start: { x: number; y: number } | null = null
  let moved = false

  function track(e: PointerEvent) {
    const r = (e.currentTarget as HTMLElement).getBoundingClientRect()
    tx = Math.max(-1, Math.min(1, ((e.clientX - r.left) / r.width - 0.5) * 2))
    ty = Math.max(-1, Math.min(1, ((e.clientY - r.top) / r.height - 0.5) * 2))
  }

  function onDown(e: PointerEvent) {
    if (opening) return
    start = { x: e.clientX, y: e.clientY }
    moved = false
    tilting = true
    ;(e.currentTarget as HTMLElement).setPointerCapture?.(e.pointerId)
    track(e)
  }

  function onMove(e: PointerEvent) {
    if (opening) return
    // Souris : le reflet suit même sans clic ; doigt : seulement pendant l'appui
    if (e.pointerType === 'mouse' && !start) { tilting = true; track(e); return }
    if (!start) return
    if (Math.hypot(e.clientX - start.x, e.clientY - start.y) > MOVE_TOLERANCE) moved = true
    track(e)
  }

  function onUp() {
    const wasTap = start && !moved
    start = null
    release()
    if (wasTap) open()
  }

  function release() {
    tilting = false
    tx = 0
    ty = 0
  }

  /** Clavier (Entrée / Espace) : click avec detail 0 ; le doigt passe par onUp */
  function onClick(e: MouseEvent) {
    if (e.detail === 0) open()
  }

  function open() {
    if (opening || !ready) return
    opening = true
    release()
    navigator.vibrate?.(25)
    const r = packEl?.getBoundingClientRect()
    if (r) ontear?.({ x: r.left + r.width / 2, y: r.top + r.height / 2 })
    setTimeout(onopen, TEAR_MS)
    setTimeout(() => ondone?.(), DONE_MS)
  }
</script>

<div class="booster" class:opening>
  <div class="float">
    <button
      bind:this={packEl}
      class="pack"
      class:tilting
      style:--tx={tx}
      style:--ty={ty}
      onpointerdown={onDown}
      onpointermove={onMove}
      onpointerup={onUp}
      onpointercancel={() => { start = null; release() }}
      onpointerleave={(e) => { if (e.pointerType === 'mouse' && !start) release() }}
      onclick={onClick}
      disabled={!ready}
      aria-label="Ouvrir le booster du jour : 5 recettes"
    >
      <span class="pack-top" aria-hidden="true">
        <span class="tear-hint">Déchire ici</span>
        <span class="shine shine-top"></span>
      </span>
      <span class="pack-body" aria-hidden="true">
        <span class="pack-logo"><CatLogo size={56} /></span>
        <span class="pack-title">Booster<br />du jour</span>
        <span class="pack-sub">5 recettes</span>
        <span class="shine"></span>
        <span class="glow"></span>
      </span>
    </button>
  </div>
  <p class="hint" aria-hidden="true">{ready ? 'Touche pour ouvrir · fais-le bouger' : 'Préparation…'}</p>
  <button class="skip" onclick={onskip} disabled={opening}>Passer</button>
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
  /* Pendant la descente, les cartes passent devant */
  .booster.opening { z-index: 0; }
  .booster.opening > * { pointer-events: none; }

  /* Flottement au repos (couche à part : ne se mélange pas avec l'inclinaison) */
  .float {
    perspective: 700px;
    animation: pack-in var(--dur-sheet) var(--ease-snap) both, pack-float 3.2s ease-in-out 0.5s infinite alternate;
  }

  .pack {
    position: relative;
    display: block;
    width: 168px;
    height: 236px;
    padding: 0;
    border: none;
    background: none;
    cursor: pointer;
    touch-action: none; /* le doigt incline le paquet au lieu de faire défiler */
    -webkit-tap-highlight-color: transparent;
    -webkit-user-select: none;
    user-select: none;
    transform-style: preserve-3d;
    transform: rotateX(calc(var(--ty) * -12deg)) rotateY(calc(var(--tx) * 14deg));
    transition: transform 0.5s var(--ease-out);
  }
  .pack.tilting { transition: transform 0.08s linear; }
  .pack:disabled { cursor: progress; }
  .pack:focus-visible { outline: 3px solid var(--accent); outline-offset: 6px; }

  /* Bande du haut : bord inférieur en dents de scie, c'est elle qui se déchire */
  .pack-top {
    position: absolute;
    inset: 0 0 auto 0;
    height: 46px;
    display: grid;
    place-items: center;
    overflow: hidden;
    background: var(--band);
    color: var(--text-on-band);
    clip-path: polygon(0 0, 100% 0, 100% 86%,
      95% 100%, 90% 86%, 85% 100%, 80% 86%, 75% 100%, 70% 86%, 65% 100%, 60% 86%, 55% 100%, 50% 86%,
      45% 100%, 40% 86%, 35% 100%, 30% 86%, 25% 100%, 20% 86%, 15% 100%, 10% 86%, 5% 100%, 0 86%);
    transform-origin: 0% 100%;
    z-index: 1;
  }
  .tear-hint {
    margin-top: -6px;
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
    overflow: hidden;
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

  /* ── Reflet : bande claire en biais, déplacée par transform ──
     Au repos elle balaie le paquet toutes les 4 s ; quand on l'incline,
     elle suit le doigt. */
  .shine {
    position: absolute;
    top: -40%;
    left: 0;
    width: 70%;
    height: 180%;
    pointer-events: none;
    background: linear-gradient(
      100deg,
      transparent 20%,
      color-mix(in srgb, var(--surface) 65%, transparent) 45%,
      color-mix(in srgb, var(--surface) 92%, transparent) 50%,
      color-mix(in srgb, var(--surface) 65%, transparent) 55%,
      transparent 80%
    );
    mix-blend-mode: soft-light;
    transform: translateX(-120%) rotate(8deg);
    animation: sheen 4s ease-in-out 1.2s infinite;
  }
  .shine-top { opacity: 0.6; }
  .tilting .shine {
    animation: none;
    transform: translateX(calc(30% + var(--tx) * 90%)) rotate(8deg);
    transition: transform 0.08s linear;
  }

  /* Petite lueur qui suit le doigt (fondu d'opacité seulement) */
  .glow {
    position: absolute;
    inset: -30%;
    pointer-events: none;
    background: radial-gradient(circle at center, color-mix(in srgb, var(--surface) 50%, transparent), transparent 45%);
    mix-blend-mode: soft-light;
    opacity: 0;
    transform: translate(calc(var(--tx) * 30%), calc(var(--ty) * 30%));
    transition: opacity 0.3s;
  }
  .tilting .glow { opacity: 1; }

  .hint { font-size: 14px; font-weight: var(--fw-bold); color: var(--text); text-align: center; }

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

  /* ── Ouverture ──
     1. la bande se déchire de gauche à droite et part sur le côté (0 → 0,45 s)
     2. le paquet descend doucement et s'efface (0,3 → 1 s) */
  .opening .float { animation: none; }
  .opening .pack-top { animation: tear-off 0.45s var(--ease-out) forwards; }
  .opening .pack { animation: pack-down 0.7s var(--ease-in) 0.3s forwards; }
  .opening .hint, .opening .skip { opacity: 0; transition: opacity var(--dur-fast); }

  @keyframes pack-in {
    from { opacity: 0; transform: translate3d(0, 30px, 0) scale(0.9); }
  }
  @keyframes pack-float {
    from { transform: translate3d(0, -4px, 0) rotate(-1.5deg); }
    to   { transform: translate3d(0, 4px, 0) rotate(1.5deg); }
  }
  @keyframes sheen {
    0%   { transform: translateX(-120%) rotate(8deg); }
    45%  { transform: translateX(170%) rotate(8deg); }
    100% { transform: translateX(170%) rotate(8deg); }
  }
  @keyframes tear-off {
    0%   { transform: translate3d(0, 0, 0) rotate(0); }
    30%  { transform: translate3d(4px, -2px, 0) rotate(-3deg); }
    100% { transform: translate3d(190px, -50px, 0) rotate(22deg); opacity: 0; }
  }
  @keyframes pack-down {
    to { transform: translate3d(0, 320px, 0) rotate(3deg); opacity: 0; }
  }

  @media (prefers-reduced-motion: reduce) {
    .float, .shine, .opening .pack-top, .opening .pack { animation: none; }
  }
</style>
