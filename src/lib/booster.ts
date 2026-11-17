// Booster du jour (v2.4.0) : les 5 recettes de l'accueil sortent d'un paquet,
// une ouverture par jour (par personne et par téléphone).
// Tirage : toutes les recettes que je peux lire (foyer, famille, catalogue),
// sans celles cuisinées ces 14 derniers jours ni déjà prévues cette semaine
// et la suivante, les mieux notées ayant plus de chances.
// Même graine pour tout le foyer → tout le foyer a le même booster.
import { supabase } from './supabase'
import { pickWeightedSeeded } from './random'
import { fetchRatingStats, type RatingStats } from './api/ratings'
import { getMonday, toISODate, slotDate } from './api/meals'

export const BOOSTER_SIZE = 5
/** Jours en arrière : une recette cuisinée depuis moins longtemps est mise de côté. */
export const RECENT_DAYS = 14
/** Jours en avant : une recette déjà prévue n'est pas reproposée. */
export const AHEAD_DAYS = 7

/**
 * Chance d'être tirée : une recette sans vote compte comme « 3 étoiles » (1,5) ;
 * une 5 étoiles a 5 fois plus de chances qu'une 1 étoile (2,5 contre 0,5).
 */
export function boosterWeight(stats: RatingStats | undefined): number {
  return stats && stats.votes > 0 ? stats.average / 2 : 1.5
}

/**
 * Les `count` recettes du booster. S'il ne reste pas assez de recettes après
 * avoir écarté les récentes, on complète avec elles (jamais de booster à moitié vide).
 * `groupOf` (facultatif) : une seule recette par groupe (ex. une par origine).
 */
export function pickBooster(
  ids: readonly string[],
  recent: ReadonlySet<string>,
  stats: ReadonlyMap<string, RatingStats>,
  count: number,
  seed: string,
  groupOf?: (id: string) => string | null | undefined,
): string[] {
  const weight = (id: string) => boosterWeight(stats.get(id))
  const ordered = [
    ...pickWeightedSeeded(ids.filter((id) => !recent.has(id)), weight, ids.length, seed),
    ...pickWeightedSeeded(ids.filter((id) => recent.has(id)), weight, ids.length, `${seed}:complement`),
  ]
  const out: string[] = []
  const groups = new Set<string>()
  for (const id of ordered) {
    if (out.length >= count) break
    const g = groupOf?.(id)
    if (g != null) {
      if (groups.has(g)) continue
      groups.add(g)
    }
    out.push(id)
  }
  return out
}

/** Recettes à écarter : repas du foyer de J-14 à J+7 (restes compris : même recette). */
export function recentRecipeIds(
  slots: { week_start: string; day_of_week: number; recipe_id: string }[],
  today: Date,
): Set<string> {
  const from = new Date(today); from.setDate(from.getDate() - RECENT_DAYS)
  const to = new Date(today); to.setDate(to.getDate() + AHEAD_DAYS)
  const a = toISODate(from), b = toISODate(to)
  const out = new Set<string>()
  for (const s of slots) {
    const d = slotDate(s.week_start, s.day_of_week)
    if (d >= a && d <= b) out.add(s.recipe_id)
  }
  return out
}

export async function fetchRecentRecipeIds(familyId: string, today = new Date()): Promise<Set<string>> {
  if (!supabase) return new Set()
  const from = new Date(today); from.setDate(from.getDate() - RECENT_DAYS)
  const to = new Date(today); to.setDate(to.getDate() + AHEAD_DAYS)
  const { data: plans, error } = await supabase
    .from('meal_plans')
    .select('id, week_start')
    .eq('family_id', familyId)
    .gte('week_start', toISODate(getMonday(from)))
    .lte('week_start', toISODate(to))
  if (error) throw error
  if (!plans?.length) return new Set()
  const weekByPlan = new Map(plans.map((p: { id: string; week_start: string }) => [p.id, p.week_start]))
  const { data: slots, error: e2 } = await supabase
    .from('meal_slots')
    .select('meal_plan_id, day_of_week, recipe_id')
    .in('meal_plan_id', [...weekByPlan.keys()])
  if (e2) throw e2
  return recentRecipeIds(
    (slots ?? []).map((s: any) => ({ ...s, week_start: weekByPlan.get(s.meal_plan_id)! })),
    today,
  )
}

/** Tirage complet ; les étoiles et le planning sont des bonus (le booster marche sans). */
export async function drawBoosterIds(
  ids: string[],
  familyId: string | null,
  dateKey: string,
  count = BOOSTER_SIZE,
  kind = 'jour',
  groupOf?: (id: string) => string | null | undefined,
  userId: string | null = null,
): Promise<string[]> {
  // Tirage déjà fait aujourd'hui sur ce téléphone : on le garde tel quel
  // (sinon planifier une carte ou une nouvelle étoile changerait les cartes).
  const cached = readCachedDraw(userId, kind, dateKey)
  if (cached) return cached
  const [stats, recent] = await Promise.all([
    fetchRatingStats(ids).catch(() => new Map<string, RatingStats>()),
    familyId ? fetchRecentRecipeIds(familyId).catch(() => new Set<string>()) : Promise.resolve(new Set<string>()),
  ])
  // Graine du booster du jour inchangée depuis v2.4.0 (même tirage qu'avant)
  const seed = kind === 'jour' ? `lichouz:booster:${familyId ?? 'seul'}:${dateKey}` : `lichouz:booster:${kind}:${familyId ?? 'seul'}:${dateKey}`
  const picked = pickBooster(ids, recent, stats, count, seed, groupOf)
  saveCachedDraw(userId, kind, dateKey, picked)
  return picked
}

// ── Une ouverture par jour et par booster (sur ce téléphone) ──
// Booster du jour : clé d'origine (v2.4.0) ; thèmes : clé suffixée.

const openedKey = (userId: string, kind: string) =>
  kind === 'jour' ? `lichouz:booster-ouvert:${userId}` : `lichouz:booster-ouvert:${userId}:${kind}`

export function boosterOpenedToday(userId: string | null, dateKey: string, kind = 'jour'): boolean {
  if (!userId) return true
  try { return localStorage.getItem(openedKey(userId, kind)) === dateKey } catch { return true }
}

export function markBoosterOpened(userId: string | null, dateKey: string, kind = 'jour'): void {
  if (!userId) return
  try { localStorage.setItem(openedKey(userId, kind), dateKey) } catch { /* navigation privée : tant pis */ }
}

// ── Tirage du jour mémorisé (v2.5.0) ──
// Une entrée par booster, remplacée le lendemain : { date, ids }.

const drawKey = (userId: string, kind: string) => `lichouz:booster-tirage:${userId}:${kind}`

export function readCachedDraw(userId: string | null, kind: string, dateKey: string): string[] | null {
  if (!userId) return null
  try {
    const v = JSON.parse(localStorage.getItem(drawKey(userId, kind)) ?? 'null')
    return v && v.date === dateKey && Array.isArray(v.ids) && v.ids.length > 0 && v.ids.every((x: unknown) => typeof x === 'string')
      ? v.ids
      : null
  } catch {
    return null
  }
}

export function saveCachedDraw(userId: string | null, kind: string, dateKey: string, ids: string[]): void {
  if (!userId || ids.length === 0) return
  try { localStorage.setItem(drawKey(userId, kind), JSON.stringify({ date: dateKey, ids })) } catch { /* tant pis */ }
}
