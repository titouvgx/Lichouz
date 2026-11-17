<script lang="ts">
  // Carte recette sortie d'un booster à thème (v2.5.0) : photo ou grande
  // initiale, titre sur une étiquette blanche. Toucher = ouvrir la recette.
  // `burst` : la carte jaillit du paquet (au-dessus d'elle) à l'ouverture.
  import Icon from './Icon.svelte'
  import { href } from '../lib/router.svelte'
  import { sizedImage } from '../lib/images'
  import { categoryColor } from '../lib/categoryColors'
  import type { RecipeWithCategory } from '../lib/types'

  let { recipe, index, burst = false }: { recipe: RecipeWithCategory; index: number; burst?: boolean } = $props()
  const img = $derived(sizedImage(recipe.image_url, 320, 320))
</script>

<a
  class="bcard"
  class:burst
  href={href('recette', recipe.id)}
  style:--i={index}
  style:--cat={categoryColor(recipe.recipe_categories?.name)}
>
  <span class="media" aria-hidden="true">
    {#if img}
      <img src={img} alt="" loading="lazy" decoding="async" draggable="false" />
    {:else}
      <span class="initial">{recipe.title.trim().charAt(0)}</span>
    {/if}
  </span>
  <span class="bc-label">
    <span class="bc-title">{recipe.title}</span>
    {#if recipe.prep_time_min}
      <span class="bc-meta"><Icon name="clock" size={12} /> {recipe.prep_time_min} min</span>
    {/if}
  </span>
</a>

<style>
  .bcard {
    display: flex;
    flex-direction: column;
    min-width: 0;
    background: var(--cat);
    border: var(--line-w) solid var(--line);
    box-shadow: var(--shadow-md);
    color: var(--ink, var(--text));
    text-decoration: none;
    touch-action: manipulation;
    -webkit-tap-highlight-color: transparent;
    transform: rotate(calc((var(--i) - 2) * 1.2deg));
    transition: transform var(--dur-fast) var(--ease-out);
  }
  .bcard:active { transform: translate(var(--press), var(--press)); box-shadow: none; }
  .media { position: relative; display: grid; place-items: center; aspect-ratio: 1; overflow: hidden; }
  .media img { position: absolute; inset: 0; width: 100%; height: 100%; object-fit: cover; }
  .initial { font-size: 40px; font-weight: var(--fw-bold); line-height: 1; }
  .bc-label {
    flex: 1;
    display: flex;
    flex-direction: column;
    gap: 2px;
    padding: 5px 6px 6px;
    background: var(--surface);
    border-top: var(--line-w) solid var(--line);
    color: var(--text);
  }
  .bc-title { font-weight: var(--fw-bold); font-size: 13px; text-transform: none; letter-spacing: 0; line-height: 1.15; overflow-wrap: anywhere; }
  .bc-meta { display: inline-flex; align-items: center; gap: 4px; font-size: 12px; color: var(--text-secondary); }

  /* Ouverture : les cartes sortent du haut (là où était le paquet), l'une après l'autre */
  .burst { animation: burst-up 0.55s var(--ease-snap) calc(var(--i) * 100ms) backwards; }
  @keyframes burst-up {
    from { opacity: 0; transform: translate3d(0, -140px, 0) scale(0.3) rotate(-12deg); }
    40%  { opacity: 1; }
  }
</style>
