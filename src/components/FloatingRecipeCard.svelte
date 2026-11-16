<script lang="ts">
  import Icon from './Icon.svelte'
  // Carte recette « flottante » de la page d'accueil.
  // Couches imbriquées, chacune avec UNE seule transformation,
  // pour que les animations ne se marchent pas dessus :
  //   .slot     → position + parallaxe (souris uniquement)
  //   .drift-x  → va-et-vient horizontal  ┐ trois durées différentes :
  //   .drift-y  → va-et-vient vertical    ├ la trajectoire ne se répète
  //   .drift-r  → balancement (rotation)  ┘ jamais, ça paraît « vivant »
  //   .card     → apparition + appui / survol
  import { href } from '../lib/router.svelte'
  import { sizedImage } from '../lib/images'
  import { categoryColor } from '../lib/categoryColors'
  import type { FloatSlot } from '../lib/floatLayout'
  import type { RecipeWithCategory } from '../lib/types'

  interface Props {
    slot: FloatSlot
    index: number
    /** null = carte fantôme pendant le chargement */
    recipe: RecipeWithCategory | null
    featured?: boolean
    /** Bouton « planifier » sur la carte (ouvre la fenêtre semaine + courses) */
    onplan?: (recipeId: string) => void
  }

  let { slot, index, recipe, featured = false, onplan }: Props = $props()

  const imgSrc = $derived(
    recipe?.image_url ? sizedImage(recipe.image_url, slot.w, slot.h) : null,
  )

  function formatTime(min: number | null): string {
    if (!min) return ''
    if (min < 60) return `${min} min`
    const h = Math.floor(min / 60)
    const m = min % 60
    return m ? `${h}h${String(m).padStart(2, '0')}` : `${h}h`
  }
</script>

<div
  class="slot"
  style:left="{slot.x}px"
  style:top="{slot.y}px"
  style:width="{slot.w}px"
  style:height="{slot.h}px"
  style:--depth={slot.depth}
>
  <div class="drift-x" style:--dx="{slot.dx}px" style:--dur="{slot.durX}s" style:--delay="{slot.delayX}s">
  <div class="drift-y" style:--dy="{slot.dy}px" style:--dur="{slot.durY}s" style:--delay="{slot.delayY}s">
  <div
    class="drift-r"
    style:--rot="{slot.rot}deg"
    style:--wob="{slot.wobble}deg"
    style:--dur="{slot.durR}s"
    style:--delay="{slot.delayR}s"
  >
    {#if recipe}
      <a
        href={href('recette', recipe.id)}
        class="card"
        style:--i={index}
        style:--cat={categoryColor(recipe.recipe_categories?.name)}
        aria-label="{recipe.title}{recipe.prep_time_min ? `, ${formatTime(recipe.prep_time_min)}` : ''}"
      >
        {#if imgSrc}
          <img
            src={imgSrc}
            alt=""
            class="card-img"
            width={slot.w}
            height={slot.h}
            decoding="async"
            draggable="false"
          />
        {:else}
          <!-- Pas de photo : grande initiale graphique plutôt qu'un émoji -->
          <span class="card-monogram" aria-hidden="true">{recipe.title.trim().charAt(0)}</span>
        {/if}

        {#if featured}
          <span class="sticker" aria-hidden="true"><Icon name="star" size={12} strokeWidth={2.5} /><span class="sticker-label">Coup de cœur</span></span>
        {/if}

        <div class="card-overlay" aria-hidden="true">
          {#if recipe.recipe_categories}
            <span class="card-badge">{recipe.recipe_categories.name}</span>
          {/if}
          <span class="card-title">{recipe.title}</span>
          {#if recipe.prep_time_min}
            <span class="card-meta"><Icon name="clock" size={12} /> {formatTime(recipe.prep_time_min)}</span>
          {/if}
        </div>
      </a>
      {#if onplan}
        <!-- Bouton à côté du lien (un bouton ne peut pas être DANS un lien) -->
        <button
          class="plan-btn"
          style:--i={index}
          onclick={() => onplan?.(recipe.id)}
          aria-label="Ajouter {recipe.title} à ma semaine"
        >
          <Icon name="calendar" size={slot.w < 140 ? 15 : 17} strokeWidth={2.2} />
        </button>
      {/if}
    {:else}
      <div class="card skeleton" style:--i={index} aria-hidden="true"></div>
    {/if}
  </div>
  </div>
  </div>
</div>

<style>
  /* ── Couche 1 : position + parallaxe ── */
  .slot {
    position: absolute;
    transform: translate3d(
      calc(var(--px, 0) * var(--depth) * 8px),
      calc(var(--py, 0) * var(--depth) * 6px),
      0
    );
    transition: transform 0.6s cubic-bezier(0.2, 0.8, 0.2, 1);
  }

  /* La carte appuyée / survolée passe devant les autres */
  .slot:hover,
  .slot:focus-within,
  .slot:active {
    z-index: 3;
  }

  /* ── Couches 2 à 4 : flottement continu ──
     Chaque couche fait un aller-retour simple (alternate) sur un seul axe,
     avec sa propre durée. Combinés, ça donne un mouvement irrégulier. */
  .drift-x,
  .drift-y,
  .drift-r {
    width: 100%;
    height: 100%;
    animation-duration: var(--dur);
    animation-delay: var(--delay);
    animation-timing-function: ease-in-out;
    animation-iteration-count: infinite;
    animation-direction: alternate;
    will-change: transform;
  }

  .drift-x { animation-name: drift-x; }
  .drift-y { animation-name: drift-y; }
  .drift-r { animation-name: drift-r; transform: rotate(var(--rot)); position: relative; }

  /* Bouton « ajouter à ma semaine », en haut à droite de la carte */
  .plan-btn {
    position: absolute;
    top: -10px;
    right: -10px;
    z-index: 2;
    width: 44px;
    height: 44px;
    border: var(--line-w) solid var(--line);
    background: var(--surface);
    color: var(--text);
    display: flex;
    align-items: center;
    justify-content: center;
    cursor: pointer;
    touch-action: manipulation;
    box-shadow: var(--shadow-sm);
    animation: drop-in var(--dur-sheet) var(--ease-snap) calc(var(--i) * 90ms + 260ms) backwards;
    transition: transform var(--dur-fast) var(--ease-out);
  }

  .plan-btn:active { transform: translate(var(--press), var(--press)); box-shadow: none; }

  @media (hover: hover) and (pointer: fine) {
    .plan-btn:hover { background: var(--accent); color: var(--on-accent); }
  }

  @keyframes drift-x {
    from { transform: translate3d(calc(var(--dx) * -1), 0, 0); }
    to   { transform: translate3d(var(--dx), 0, 0); }
  }

  @keyframes drift-y {
    from { transform: translate3d(0, calc(var(--dy) * -1), 0); }
    to   { transform: translate3d(0, var(--dy), 0); }
  }

  @keyframes drift-r {
    from { transform: rotate(calc(var(--rot) - var(--wob))); }
    to   { transform: rotate(calc(var(--rot) + var(--wob))); }
  }

  /* ── Couche 5 : la carte ──
     Brut : bloc carré, bordure noire, ombre franche ; photo en haut,
     étiquette blanche en bas avec le titre en noir (lisible sur toute photo). */
  .card {
    position: relative;
    display: block;
    width: 100%;
    height: 100%;
    overflow: hidden;
    background: var(--cat);
    border: var(--line-w) solid var(--line);
    box-shadow: var(--shadow-md);
    color: var(--text);
    text-decoration: none;
    animation: drop-in var(--dur-sheet) var(--ease-snap) calc(var(--i) * 90ms + 80ms) backwards;
    transition: transform var(--dur-fast) var(--ease-out);
    /* Mobile : pas de menu « enregistrer l'image » ni de sélection au appui long */
    -webkit-touch-callout: none;
    -webkit-user-select: none;
    user-select: none;
    -webkit-tap-highlight-color: transparent;
    touch-action: manipulation;
    /* Les textes s'adaptent à la taille de LA CARTE, pas de l'écran */
    container-type: inline-size;
  }

  /* Au doigt : la carte s'enfonce sur son ombre */
  .card:active {
    transform: translate(4px, 4px);
    box-shadow: none;
  }

  /* Survol : uniquement avec une vraie souris, sinon l'effet « colle » sur mobile */
  @media (hover: hover) and (pointer: fine) {
    .card:hover { transform: translate(-2px, -2px); box-shadow: var(--shadow-lg); }
  }

  .card:focus-visible {
    outline: 3px solid var(--accent);
    outline-offset: 3px;
  }

  /* Les cartes tombent à leur place, l'une après l'autre */
  @keyframes drop-in {
    from { opacity: 0; transform: translate3d(0, -40px, 0); }
    to   { opacity: 1; transform: translate3d(0, 0, 0); }
  }

  .card-img {
    position: absolute;
    inset: 0;
    width: 100%;
    height: 100%;
    object-fit: cover;
    pointer-events: none;
  }

  /* Recette sans photo : grande initiale noire sur la couleur de la catégorie */
  .card-monogram {
    position: absolute;
    inset: 0;
    display: flex;
    align-items: flex-start;
    justify-content: center;
    padding-top: 6cqw;
    font-family: var(--font-display);
    font-weight: var(--fw-bold);
    font-size: 58cqw; /* proportionnelle à la largeur de la carte */
    line-height: 1;
    text-transform: uppercase;
    color: var(--ink);
    background: var(--cat);
  }

  /* Étiquette compacte : la photo garde au moins les deux tiers de la carte */
  .card-overlay {
    position: absolute;
    inset: auto 0 0 0;
    max-height: 36%;
    padding: 5px 7px 6px;
    background: var(--surface);
    border-top: var(--line-w) solid var(--line);
    display: flex;
    flex-direction: column;
    gap: 2px;
  }

  /* Catégorie : seulement sur les grandes cartes (la photo d'abord) */
  .card-badge {
    display: none;
    align-self: flex-start;
    max-width: 100%;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
    font-size: 10px;
    font-weight: var(--fw-bold);
    letter-spacing: var(--tracking-caps);
    text-transform: uppercase;
    padding: 1px 5px;
    border: var(--line-thin) solid var(--ink);
    background: var(--cat);
    color: var(--ink);
  }

  .card-title {
    font-family: var(--font-display);
    font-size: 13px;
    font-weight: var(--fw-bold);
    line-height: 1.15;
    display: -webkit-box;
    -webkit-line-clamp: 2;
    line-clamp: 2;
    -webkit-box-orient: vertical;
    overflow: hidden;
    overflow-wrap: break-word;
    hyphens: auto;
  }

  /* Temps de préparation : seulement sur les grandes cartes */
  .card-meta {
    display: none;
    font-size: 11px;
    color: var(--text-secondary);
  }

  .sticker {
    display: inline-flex;
    align-items: center;
    position: absolute;
    top: 6px;
    left: 6px;
    padding: 2px 7px;
    border: var(--line-w) solid var(--ink);
    background: var(--accent);
    color: var(--on-accent);
    font-size: 11px;
    font-weight: var(--fw-bold);
    text-transform: uppercase;
    white-space: nowrap;
    animation: pulse-soft 2.5s ease-in-out infinite;
  }

  .sticker-label {
    margin-left: 4px;
  }

  /* Carte fantôme pendant le chargement : elle flotte déjà et clignote doucement */
  .skeleton {
    background: var(--surface);
    animation:
      drop-in var(--dur-sheet) var(--ease-out) calc(var(--i) * 80ms) backwards,
      skeleton-blink 1.2s ease-in-out infinite;
  }

  @keyframes skeleton-blink {
    50% { opacity: 0.55; }
  }

  /* Petites cartes (iPhone SE, vieux Android) : on allège */
  @container (max-width: 140px) {
    .card-overlay { padding: 4px 5px 5px; }
    .card-badge { display: none; }
    .card-title { font-size: 12px; letter-spacing: -0.01em; }
    .card-meta { font-size: 10px; }
    .sticker { padding: 2px 5px; }
    .sticker-label { display: none; }
  }

  /* Grandes cartes (tablette, ordinateur) */
  @container (min-width: 180px) {
    .card-title { font-size: 16px; }
    .card-meta { display: block; font-size: 12px; }
    .card-badge { display: block; }
  }
</style>
