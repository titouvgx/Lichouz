// Succès (v2.7.0, migration 32) : lecture de ma progression, enregistrement des
// paliers atteints (la base décide), séances « En cuisine », boosters ouverts.
import { supabase } from '../supabase'
import type { Unlocked } from '../succes'

function db() {
  if (!supabase) throw new Error('Supabase non configuré')
  return supabase
}

export interface MyAchievements {
  progress: Record<string, number>
  unlocked: Unlocked[]
}

export async function fetchMyAchievements(): Promise<MyAchievements> {
  const { data, error } = await db().rpc('my_achievements')
  if (error) throw error
  const d = (data ?? {}) as Partial<MyAchievements>
  return { progress: d.progress ?? {}, unlocked: d.unlocked ?? [] }
}

/** Demande à la base d'enregistrer les paliers atteints ; renvoie seulement les nouveaux. */
export async function refreshAchievements(): Promise<Unlocked[]> {
  const { data, error } = await db().rpc('refresh_my_achievements')
  if (error) throw error
  return (data ?? []) as Unlocked[]
}

/** Fin d'un passage en mode « En cuisine » (la base calcule et plafonne la durée). */
export async function recordCookSession(userId: string, recipeId: string, startedAt: Date, endedAt = new Date()): Promise<void> {
  if (endedAt.getTime() - startedAt.getTime() < 60_000) return // moins d'une minute : on ignore
  const { error } = await db().from('cook_sessions').insert({
    profile_id: userId,
    recipe_id: recipeId,
    started_at: startedAt.toISOString(),
    ended_at: endedAt.toISOString(),
    minutes: 1, // recalculé par la base
  })
  if (error) throw error
}

/** Booster ouvert (ou passé) : une ligne par booster et par jour ; un doublon est ignoré. */
export async function recordBoosterOpening(userId: string, kind: string, day: string, recipeIds: string[]): Promise<void> {
  const { error } = await db().from('booster_openings').insert({
    profile_id: userId,
    kind,
    day,
    recipe_ids: recipeIds.slice(0, 5),
  })
  if (error && error.code !== '23505') throw error
}
