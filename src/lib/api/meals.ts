// Couche données — Planning des repas
// CRUD pour meal_plans et meal_slots.

import { supabase } from '../supabase'
import type { Course, MealPlan, MealSlotWithRecipe, WeekTemplate } from '../types'

// ────────── Utilitaires dates ──────────

/** Retourne le lundi de la semaine contenant `date`. */
export function getMonday(date: Date): Date {
  const d = new Date(date)
  const day = d.getDay() // 0 = dimanche, 1 = lundi…
  const diff = day === 0 ? -6 : 1 - day
  d.setDate(d.getDate() + diff)
  d.setHours(0, 0, 0, 0)
  return d
}

/** Formate en YYYY-MM-DD (format attendu par Supabase pour le type date). */
export function toISODate(d: Date): string {
  const y = d.getFullYear()
  const m = String(d.getMonth() + 1).padStart(2, '0')
  const day = String(d.getDate()).padStart(2, '0')
  return `${y}-${m}-${day}`
}

/** Date réelle d'un créneau (lundi de la semaine + jour 0 à 6). */
export function slotDate(weekStart: string, day: number): string {
  const [y, m, d] = weekStart.split('-').map(Number)
  return toISODate(new Date(y, m - 1, d + day))
}

/** Avance ou recule d'un nombre de semaines. */
export function shiftWeek(monday: Date, weeks: number): Date {
  const d = new Date(monday)
  d.setDate(d.getDate() + weeks * 7)
  return d
}

// ────────── Plan de la semaine ──────────

/**
 * Récupère (ou crée) le plan de repas pour une semaine donnée.
 * @param familyId – UUID du foyer
 * @param weekStart – date du lundi (YYYY-MM-DD)
 */
export async function fetchOrCreatePlan(
  familyId: string,
  weekStart: string,
): Promise<MealPlan> {
  if (!supabase) throw new Error('Supabase non configuré')

  // 1. Essayer de récupérer le plan existant
  const { data: existing, error: selErr } = await supabase
    .from('meal_plans')
    .select('*')
    .eq('family_id', familyId)
    .eq('week_start', weekStart)
    .maybeSingle()

  if (selErr) throw selErr
  if (existing) return existing as MealPlan

  // 2. Le plan n'existe pas → le créer
  const { data: created, error: insErr } = await supabase
    .from('meal_plans')
    .insert({ family_id: familyId, week_start: weekStart })
    .select('*')
    .single()

  if (insErr) throw insErr
  return created as MealPlan
}

// ────────── Slots (créneaux) ──────────

/**
 * Charge tous les slots d'un plan avec les infos de la recette.
 */
export async function fetchSlots(planId: string): Promise<MealSlotWithRecipe[]> {
  if (!supabase) return []

  const { data, error } = await supabase
    .from('meal_slots')
    .select(`
      *,
      recipes (
        id,
        title,
        image_url,
        default_portions,
        prep_time_min
      )
    `)
    .eq('meal_plan_id', planId)
    .order('day_of_week')

  if (error) throw error
  return (data ?? []) as MealSlotWithRecipe[]
}

/**
 * Lecture seule : créneaux déjà remplis sur plusieurs semaines (sans créer de plan).
 * Sert à afficher « déjà prévu » dans la fenêtre d'ajout à la semaine.
 * @returns un objet { 'AAAA-MM-JJ' (lundi) : créneaux de cette semaine }
 */
export async function fetchSlotsForWeeks(
  familyId: string,
  weekStarts: string[],
): Promise<Record<string, MealSlotWithRecipe[]>> {
  const result: Record<string, MealSlotWithRecipe[]> = {}
  for (const w of weekStarts) result[w] = []
  if (!supabase || weekStarts.length === 0) return result

  const { data: plans, error: plansErr } = await supabase
    .from('meal_plans')
    .select('id, week_start')
    .eq('family_id', familyId)
    .in('week_start', weekStarts)
  if (plansErr) throw plansErr
  if (!plans || plans.length === 0) return result

  const weekByPlan = new Map(plans.map((p: { id: string; week_start: string }) => [p.id, p.week_start]))
  const { data: slots, error: slotsErr } = await supabase
    .from('meal_slots')
    .select('*, recipes (id, title, image_url, default_portions, prep_time_min)')
    .in('meal_plan_id', [...weekByPlan.keys()])
  if (slotsErr) throw slotsErr

  for (const slot of (slots ?? []) as MealSlotWithRecipe[]) {
    const week = weekByPlan.get(slot.meal_plan_id)
    if (week) result[week].push(slot)
  }
  return result
}

/** Ordre d'affichage des plats d'un repas. */
export const COURSES: readonly { key: Course; label: string }[] = [
  { key: 'entree', label: 'Entrée' },
  { key: 'plat', label: 'Plat' },
  { key: 'dessert', label: 'Dessert' },
]

export const courseLabel = (c: Course | undefined) => COURSES.find((x) => x.key === (c ?? 'plat'))!.label

/** Sorte de plat proposée d'après la catégorie de la recette (Entrée, Dessert, sinon plat). */
export function courseFromCategory(name: string | null | undefined): Course {
  const n = (name ?? '').trim().toLowerCase()
  if (n === 'entrée' || n === 'apéritif') return 'entree'
  if (n === 'dessert' || n === 'petit-déj & goûter') return 'dessert'
  return 'plat'
}

/** Ordre dans le temps d'un repas (pour les restes : toujours plus tard). */
export function mealRank(day: number, meal: 'midi' | 'soir'): number {
  return day * 2 + (meal === 'soir' ? 1 : 0)
}

/**
 * Ajoute ou remplace un plat d'un repas (DELETE + INSERT : l'unicité porte sur
 * jour × repas × sorte de plat). Remplacer un repas cuisiné supprime ses restes.
 */
export async function setSlot(
  planId: string,
  dayOfWeek: number,
  mealType: 'midi' | 'soir',
  recipeId: string,
  portions: number,
  course: Course = 'plat',
): Promise<void> {
  if (!supabase) throw new Error('Supabase non configuré')

  // Garder le cuisinier déjà choisi pour ce plat
  const { data: previous } = await supabase
    .from('meal_slots')
    .select('cook_id')
    .eq('meal_plan_id', planId)
    .eq('day_of_week', dayOfWeek)
    .eq('meal_type', mealType)
    .eq('course', course)
    .maybeSingle()

  const { error: delErr } = await supabase
    .from('meal_slots')
    .delete()
    .eq('meal_plan_id', planId)
    .eq('day_of_week', dayOfWeek)
    .eq('meal_type', mealType)
    .eq('course', course)
  if (delErr) throw delErr

  const { error } = await supabase
    .from('meal_slots')
    .insert({
      meal_plan_id: planId,
      day_of_week: dayOfWeek,
      meal_type: mealType,
      course,
      recipe_id: recipeId,
      portions,
      ...(previous?.cook_id ? { cook_id: previous.cook_id } : {}),
    })

  if (error) throw error
}

/** Prévoit les restes d'un repas cuisiné sur un repas plus tard (même recette). */
export async function addLeftover(
  planId: string,
  dayOfWeek: number,
  mealType: 'midi' | 'soir',
  course: Course,
  from: MealSlotWithRecipe,
  portions: number,
): Promise<void> {
  if (!supabase) throw new Error('Supabase non configuré')
  const { error: delErr } = await supabase
    .from('meal_slots')
    .delete()
    .eq('meal_plan_id', planId)
    .eq('day_of_week', dayOfWeek)
    .eq('meal_type', mealType)
    .eq('course', course)
  if (delErr) throw delErr
  const { error } = await supabase.from('meal_slots').insert({
    meal_plan_id: planId,
    day_of_week: dayOfWeek,
    meal_type: mealType,
    course,
    recipe_id: from.recipe_id,
    portions,
    leftover_of: from.id,
  })
  if (error) throw error
}

// ────────── Recopier une semaine, semaines types (migration 26) ──────────

/** Planning d'une semaine s'il existe (sans le créer). */
export async function findPlan(familyId: string, weekStart: string): Promise<MealPlan | null> {
  if (!supabase) return null
  const { data, error } = await supabase
    .from('meal_plans')
    .select('*')
    .eq('family_id', familyId)
    .eq('week_start', weekStart)
    .maybeSingle()
  if (error) throw error
  return (data as MealPlan) ?? null
}

/** Nombre de repas d'un planning (pour proposer de recopier). */
export async function countSlots(planId: string): Promise<number> {
  if (!supabase) return 0
  const { count, error } = await supabase
    .from('meal_slots')
    .select('id', { count: 'exact', head: true })
    .eq('meal_plan_id', planId)
  if (error) throw error
  return count ?? 0
}

/** Recopie une semaine dans une autre, en une transaction. Renvoie le nombre de plats ajoutés. */
export async function copyWeek(fromPlanId: string, toPlanId: string, replace: boolean): Promise<number> {
  if (!supabase) throw new Error('Supabase non configuré')
  const { data, error } = await supabase.rpc('copy_week_slots', { p_from_plan: fromPlanId, p_to_plan: toPlanId, p_replace: replace })
  if (error) throw error
  return Number(data ?? 0)
}

export async function fetchWeekTemplates(familyId: string): Promise<WeekTemplate[]> {
  if (!supabase) return []
  const { data, error } = await supabase
    .from('week_templates')
    .select('*, week_template_slots(count)')
    .eq('family_id', familyId)
    .order('name')
  if (error) throw error
  return (data ?? []).map((t: any) => ({
    id: t.id, family_id: t.family_id, name: t.name, created_by: t.created_by, created_at: t.created_at,
    slot_count: t.week_template_slots?.[0]?.count ?? 0,
  }))
}

export async function saveWeekTemplate(planId: string, name: string): Promise<string> {
  if (!supabase) throw new Error('Supabase non configuré')
  const { data, error } = await supabase.rpc('save_week_template', { p_plan: planId, p_name: name.trim() })
  if (error) throw error
  return data as string
}

export async function applyWeekTemplate(templateId: string, planId: string, replace: boolean): Promise<number> {
  if (!supabase) throw new Error('Supabase non configuré')
  const { data, error } = await supabase.rpc('apply_week_template', { p_template: templateId, p_plan: planId, p_replace: replace })
  if (error) throw error
  return Number(data ?? 0)
}

export async function deleteWeekTemplate(templateId: string): Promise<void> {
  if (!supabase) throw new Error('Supabase non configuré')
  const { data, error } = await supabase.from('week_templates').delete().eq('id', templateId).select('id')
  if (error) throw error
  if (!data || data.length === 0) throw new Error('Cette semaine type n’a pas pu être supprimée.')
}

/**
 * Supprime un créneau (libère la case).
 */
export async function removeSlot(slotId: string): Promise<void> {
  if (!supabase) throw new Error('Supabase non configuré')

  const { error } = await supabase
    .from('meal_slots')
    .delete()
    .eq('id', slotId)

  if (error) throw error
}

/**
 * Met à jour le nombre de portions d'un créneau.
 */
export async function updateSlotPortions(
  slotId: string,
  portions: number,
): Promise<void> {
  if (!supabase) throw new Error('Supabase non configuré')

  const { error } = await supabase
    .from('meal_slots')
    .update({ portions })
    .eq('id', slotId)

  if (error) throw error
}
