// Étoiles (v2.2.0, migration 30) : mon vote (privé) et la moyenne (visible par
// tous ceux qui lisent la recette).
import { supabase } from '../supabase'

export interface RatingStats {
  average: number
  votes: number
}

function db() {
  if (!supabase) throw new Error('Supabase non configuré')
  return supabase
}

/** Moyennes des recettes demandées (50 au plus par appel, comme la base). */
export async function fetchRatingStats(recipeIds: string[]): Promise<Map<string, RatingStats>> {
  const out = new Map<string, RatingStats>()
  for (let i = 0; i < recipeIds.length; i += 50) {
    const { data, error } = await db().rpc('recipe_rating_stats', { p_recipes: recipeIds.slice(i, i + 50) })
    if (error) throw error
    for (const r of (data ?? []) as { recipe_id: string; average: number | string; votes: number }[]) {
      out.set(r.recipe_id, { average: Number(r.average), votes: r.votes })
    }
  }
  return out
}

export async function fetchMyRating(recipeId: string, userId: string): Promise<number | null> {
  const { data, error } = await db()
    .from('recipe_ratings')
    .select('stars')
    .eq('recipe_id', recipeId)
    .eq('profile_id', userId)
    .maybeSingle()
  if (error) throw error
  return data?.stars ?? null
}

/** Pose ou change ma note (une seule par recette). */
export async function setMyRating(recipeId: string, userId: string, stars: number): Promise<void> {
  const { error } = await db()
    .from('recipe_ratings')
    .upsert({ recipe_id: recipeId, profile_id: userId, stars }, { onConflict: 'recipe_id,profile_id' })
  if (error) throw error
}

export async function clearMyRating(recipeId: string, userId: string): Promise<void> {
  const { data, error } = await db()
    .from('recipe_ratings')
    .delete()
    .eq('recipe_id', recipeId)
    .eq('profile_id', userId)
    .select('id')
  if (error) throw error
  if (!data?.length) throw new Error('Note introuvable')
}

/** « 4,3 » (virgule française). */
export function formatAverage(n: number): string {
  return n.toLocaleString('fr-FR', { minimumFractionDigits: 1, maximumFractionDigits: 1 })
}
