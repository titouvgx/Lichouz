// Tendances (v2.3.0) : meilleures recettes par étoiles, les plus cuisinées du
// mois dans mon foyer, les nouvelles recettes. Aucune migration : tout passe
// par les règles déjà en place (RLS + recipe_rating_stats qui ne compte que
// les recettes que je peux lire).
import { supabase } from './supabase'
import { fetchRecipeIndex } from './api/recipes'
import { fetchRatingStats, type RatingStats } from './api/ratings'
import { toISODate, getMonday } from './api/meals'
import type { RecipeWithCategory } from './types'

export interface RankedRecipe {
  id: string
  title: string
  average: number
  votes: number
}

/**
 * Classement par étoiles : moyenne d'abord, puis nombre de votes (une 5/5 avec
 * 4 votes passe devant une 5/5 avec 1 vote), puis titre. Sans vote = absent.
 */
export function rankByStars(
  recipes: { id: string; title: string }[],
  stats: Map<string, RatingStats>,
  limit: number,
): RankedRecipe[] {
  return recipes
    .flatMap((r) => {
      const s = stats.get(r.id)
      return s && s.votes > 0 ? [{ id: r.id, title: r.title, average: s.average, votes: s.votes }] : []
    })
    .sort((a, b) => b.average - a.average || b.votes - a.votes || a.title.localeCompare(b.title, 'fr'))
    .slice(0, limit)
}

export interface CookedCount {
  recipeId: string
  count: number
}

export { slotDate } from './api/meals'
import { slotDate } from './api/meals'

/**
 * Plus cuisinées : créneaux du mois en cours jusqu'à aujourd'hui compris
 * (un repas prévu plus tard n'est pas encore « cuisiné »), restes exclus.
 */
export function countCooked(
  slots: { week_start: string; day_of_week: number; recipe_id: string; leftover_of?: string | null }[],
  today: Date,
  limit: number,
): CookedCount[] {
  const monthStart = toISODate(new Date(today.getFullYear(), today.getMonth(), 1))
  const todayKey = toISODate(today)
  const counts = new Map<string, number>()
  for (const s of slots) {
    if (s.leftover_of) continue
    const date = slotDate(s.week_start, s.day_of_week)
    if (date < monthStart || date > todayKey) continue
    counts.set(s.recipe_id, (counts.get(s.recipe_id) ?? 0) + 1)
  }
  return [...counts]
    .map(([recipeId, count]) => ({ recipeId, count }))
    .sort((a, b) => b.count - a.count || a.recipeId.localeCompare(b.recipeId))
    .slice(0, limit)
}

function db() {
  if (!supabase) throw new Error('Supabase non configuré')
  return supabase
}

/** Top N par étoiles parmi toutes les recettes que je peux lire (non archivées). */
export async function fetchTopRated(limit: number): Promise<RankedRecipe[]> {
  const index = await fetchRecipeIndex()
  const stats = await fetchRatingStats(index.map((r) => r.id))
  return rankByStars(index, stats, limit)
}

/** Les plus cuisinées du mois dans mon foyer (le planning est par foyer). */
export async function fetchMostCooked(familyId: string, limit: number, today = new Date()): Promise<CookedCount[]> {
  // Semaines qui touchent le mois : du lundi de la semaine du 1er jusqu'à aujourd'hui
  const first = getMonday(new Date(today.getFullYear(), today.getMonth(), 1))
  const { data: plans, error } = await db()
    .from('meal_plans')
    .select('id, week_start')
    .eq('family_id', familyId)
    .gte('week_start', toISODate(first))
    .lte('week_start', toISODate(today))
  if (error) throw error
  if (!plans?.length) return []
  const weekByPlan = new Map(plans.map((p: { id: string; week_start: string }) => [p.id, p.week_start]))
  const { data: slots, error: e2 } = await db()
    .from('meal_slots')
    .select('meal_plan_id, day_of_week, recipe_id, leftover_of')
    .in('meal_plan_id', [...weekByPlan.keys()])
  if (e2) throw e2
  return countCooked(
    (slots ?? []).map((s: any) => ({ ...s, week_start: weekByPlan.get(s.meal_plan_id)! })),
    today,
    limit,
  )
}

/** Nouvelles recettes des 30 derniers jours (hors catalogue livré), les plus récentes d'abord. */
export async function fetchNewRecipes(limit: number, today = new Date()): Promise<RecipeWithCategory[]> {
  const since = new Date(today)
  since.setDate(since.getDate() - 30)
  const { data, error } = await db()
    .from('recipes')
    .select('*, recipe_categories(*)')
    .is('archived_at', null)
    .neq('visibility', 'catalogue')
    .gte('created_at', since.toISOString())
    .order('created_at', { ascending: false })
    .limit(limit)
  if (error) throw error
  return (data ?? []) as RecipeWithCategory[]
}
