<script lang="ts">
  // Étoiles d'une recette (v2.2.0) : moyenne + nombre de votes (visibles par tous ceux qui
  // lisent la recette) et ma note, modifiable. Mon vote reste privé.
  import Icon from './Icon.svelte'
  import { toast } from '../lib/toast.svelte'
  import { auth } from '../lib/auth.svelte'
  import { checkAchievements } from '../lib/achievements.svelte'
  import { fetchRatingStats, fetchMyRating, setMyRating, clearMyRating, formatAverage, type RatingStats } from '../lib/api/ratings'

  let { recipeId }: { recipeId: string } = $props()

  let stats = $state<RatingStats | null>(null)
  let mine = $state<number | null>(null)
  let saving = $state(false)
  let loaded = $state(false)

  async function load() {
    const uid = auth.user?.id
    if (!uid) return
    try {
      const [s, m] = await Promise.all([fetchRatingStats([recipeId]), fetchMyRating(recipeId, uid)])
      stats = s.get(recipeId) ?? null
      mine = m
    } catch {
      // pas bloquant : la fiche reste utilisable sans les étoiles
    } finally {
      loaded = true
    }
  }
  $effect(() => {
    void recipeId
    void load()
  })

  async function rate(n: number) {
    const uid = auth.user?.id
    if (!uid || saving) return
    saving = true
    const before = mine
    mine = n === mine ? null : n
    try {
      if (mine === null) await clearMyRating(recipeId, uid)
      else await setMyRating(recipeId, uid, n)
      stats = (await fetchRatingStats([recipeId])).get(recipeId) ?? null
      toast.success(mine === null ? 'Note retirée' : `Merci ! ${n} étoile${n > 1 ? 's' : ''}`)
      void checkAchievements(true)
    } catch {
      mine = before
      toast.error('La note n’a pas pu être enregistrée')
    } finally {
      saving = false
    }
  }
</script>

{#if loaded}
  <section class="rating card" aria-labelledby="rating-title">
    <div class="avg">
      {#if stats}
        <span class="avg-num"><Icon name="star" size={20} /> {formatAverage(stats.average)}</span>
        <span class="avg-votes">{stats.votes} vote{stats.votes > 1 ? 's' : ''}</span>
      {:else}
        <span class="avg-votes">Pas encore notée</span>
      {/if}
    </div>
    <div class="mine">
      <h2 id="rating-title" class="mine-title">Ta note</h2>
      <div class="stars" role="radiogroup" aria-label="Ta note sur 5">
        {#each [1, 2, 3, 4, 5] as n (n)}
          <button
            type="button"
            class="star"
            class:on={mine !== null && n <= mine}
            role="radio"
            aria-checked={mine === n}
            aria-label="{n} étoile{n > 1 ? 's' : ''}{mine === n ? ' (touche pour retirer)' : ''}"
            disabled={saving}
            onclick={() => rate(n)}
          >
            <svg viewBox="0 0 24 24" aria-hidden="true"><path d="M12 2.8l2.8 5.8 6.3.9-4.6 4.4 1.1 6.3L12 17.2l-5.6 3 1.1-6.3-4.6-4.4 6.3-.9z" /></svg>
          </button>
        {/each}
      </div>
      <p class="hint">Ton vote reste privé ; tout le monde voit la moyenne.</p>
    </div>
  </section>
{/if}

<style>
  .rating { padding: var(--sp-3) var(--sp-4); display: grid; gap: var(--sp-3); margin: var(--sp-4) 0; }
  .avg { display: flex; align-items: baseline; gap: var(--sp-2); }
  .avg-num { display: inline-flex; align-items: center; gap: 6px; font-family: var(--font-display); font-weight: var(--fw-bold); font-size: var(--fs-xl); }
  .avg-votes { color: var(--text-secondary); font-size: var(--fs-sm); font-weight: var(--fw-medium); }
  .mine { display: grid; gap: var(--sp-2); }
  .mine-title { font-size: var(--fs-sm); font-weight: var(--fw-bold); text-transform: uppercase; letter-spacing: var(--tracking-caps); }
  .stars { display: flex; gap: 2px; }
  .star {
    width: 48px;
    height: 48px;
    display: grid;
    place-items: center;
    background: none;
    border: none;
    padding: 0;
    cursor: pointer;
    touch-action: manipulation;
  }
  .star svg { width: 36px; height: 36px; fill: var(--surface); stroke: var(--line); stroke-width: 1.8; stroke-linejoin: round; transition: transform var(--dur-fast) var(--ease-out); }
  .star.on svg { fill: var(--accent); }
  .star:active svg { transform: scale(0.88); }
  .star:disabled { cursor: progress; }
  .hint { font-size: var(--fs-sm); color: var(--text-secondary); }
  @media (prefers-reduced-motion: reduce) { .star svg { transition: none; } }
</style>
