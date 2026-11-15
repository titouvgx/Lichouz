// Couche données — Liste de courses
// Génération depuis le planning, cochage, ajout manuel.

import { supabase } from '../supabase'
import {
  addQuantities, formatQuantity, fromIngredient, parseQuantity, ingredientKey, type Quantity,
} from '../quantities'
import type {
  ShoppingList,
  ShoppingListItemWithCategory,
  ShoppingCategory,
} from '../types'

// ────────── Liste active ──────────

/**
 * Récupère la liste de courses active du foyer (s'il y en a une).
 */
export async function fetchActiveList(
  familyId: string,
): Promise<ShoppingList | null> {
  if (!supabase) return null

  const { data, error } = await supabase
    .from('shopping_lists')
    .select('*')
    .eq('family_id', familyId)
    .eq('status', 'active')
    .order('created_at', { ascending: false })
    .limit(1)
    .maybeSingle()

  if (error) throw error
  return data as ShoppingList | null
}

/**
 * Charge les articles d'une liste avec leur rayon.
 */
export async function fetchListItems(
  listId: string,
): Promise<ShoppingListItemWithCategory[]> {
  if (!supabase) return []

  const { data, error } = await supabase
    .from('shopping_list_items')
    .select('*, shopping_categories(*)')
    .eq('shopping_list_id', listId)
    .order('position')

  if (error) throw error
  return (data ?? []) as ShoppingListItemWithCategory[]
}

// ────────── Historique (listes terminées) ──────────

/**
 * Récupère les listes terminées du foyer, triées par date (récentes d'abord).
 */
export async function fetchCompletedLists(
  familyId: string,
  limit = 20,
): Promise<ShoppingList[]> {
  if (!supabase) return []

  const { data, error } = await supabase
    .from('shopping_lists')
    .select('*')
    .eq('family_id', familyId)
    .eq('status', 'completed')
    .order('completed_at', { ascending: false })
    .limit(limit)

  if (error) throw error
  return (data ?? []) as ShoppingList[]
}

/** Résumé d'une liste terminée pour l'historique. */
export interface ListSummary {
  total: number
  checked: number
  /** Premiers articles (ordre de la liste), pour l'aperçu */
  preview: string[]
}

/**
 * Résumés (articles pris / total + aperçu) de plusieurs listes en une requête
 * légère (nom + coché seulement). Lecture par blocs de 1000 lignes.
 */
export async function fetchListSummaries(
  listIds: string[],
  previewCount = 4,
): Promise<Map<string, ListSummary>> {
  const result = new Map<string, ListSummary>()
  if (!supabase || listIds.length === 0) return result

  const CHUNK = 1000
  const rows: { shopping_list_id: string; name: string; checked: boolean; position: number }[] = []
  for (let from = 0; ; from += CHUNK) {
    const { data, error } = await supabase
      .from('shopping_list_items')
      .select('shopping_list_id, name, checked, position')
      .in('shopping_list_id', listIds)
      .order('shopping_list_id')
      .order('position')
      .range(from, from + CHUNK - 1)
    if (error) throw error
    const chunk = data ?? []
    rows.push(...chunk)
    if (chunk.length < CHUNK) break
  }

  for (const id of listIds) result.set(id, { total: 0, checked: 0, preview: [] })
  rows.sort((a, b) => a.position - b.position)
  for (const row of rows) {
    const s = result.get(row.shopping_list_id)
    if (!s) continue
    s.total++
    if (row.checked) s.checked++
    if (s.preview.length < previewCount) s.preview.push(row.name)
  }
  return result
}

// ────────── Génération depuis le planning ──────────

export interface AggregatedIngredient {
  name: string
  quantity: Quantity
  shopping_category_id: string | null
  source_recipe_id: string | null
  /** Toutes les recettes qui demandent cet ingrédient (sans doublon, dans l'ordre du planning) */
  source_recipe_ids: string[]
}

/**
 * Additionne les ingrédients de toutes les recettes d'un plan, en ajustant
 * chaque recette à ses portions. Les unités compatibles sont regroupées
 * (g + kg, cl + l…), voir lib/quantities.ts.
 */
async function aggregatePlanIngredients(planId: string): Promise<Map<string, AggregatedIngredient>> {
  if (!supabase) throw new Error('Supabase non configuré')

  const { data: slots, error } = await supabase
    .from('meal_slots')
    .select(`
      portions,
      recipe_id,
      recipes (
        id,
        default_portions,
        recipe_ingredients (name, quantity, unit, shopping_category_id)
      )
    `)
    .eq('meal_plan_id', planId)

  if (error) throw error
  if (!slots || slots.length === 0) {
    throw new Error('Le planning est vide. Ajoute des recettes avant de générer la liste.')
  }

  return aggregateSlots(slots as unknown as PlannedSlot[])
}

/** Un créneau du planning avec sa recette (forme renvoyée par Supabase). */
export interface PlannedSlot {
  portions: number
  recipes: {
    id: string
    default_portions: number | null
    recipe_ingredients: { name: string; quantity: number | null; unit: string | null; shopping_category_id: string | null }[] | null
  } | null
}

/** Calcul pur (testé) : additionne les ingrédients des créneaux, ajustés aux portions. */
export function aggregateSlots(slots: PlannedSlot[]): Map<string, AggregatedIngredient> {
  const aggregated = new Map<string, AggregatedIngredient>()
  for (const slot of slots) {
    const recipe = slot.recipes
    if (!recipe?.recipe_ingredients) continue
    const scale = slot.portions / (recipe.default_portions || 4)

    for (const ing of recipe.recipe_ingredients) {
      const key = ingredientKey(ing.name)
      const qty = fromIngredient(ing.quantity, ing.unit, scale)
      const existing = aggregated.get(key)
      if (existing) {
        existing.quantity = addQuantities(existing.quantity, qty)
        if (!existing.source_recipe_ids.includes(recipe.id)) existing.source_recipe_ids.push(recipe.id)
      } else {
        aggregated.set(key, {
          name: ing.name.trim(),
          quantity: qty,
          shopping_category_id: ing.shopping_category_id,
          source_recipe_id: recipe.id,
          source_recipe_ids: [recipe.id],
        })
      }
    }
  }
  return aggregated
}

/**
 * Génère une nouvelle liste de courses active à partir du plan de la semaine.
 */
export async function generateListFromPlan(
  familyId: string,
  planId: string,
): Promise<ShoppingList> {
  if (!supabase) throw new Error('Supabase non configuré')

  const aggregated = await aggregatePlanIngredients(planId)

  const { data: list, error: listErr } = await supabase
    .from('shopping_lists')
    .insert({ family_id: familyId, meal_plan_id: planId, status: 'active' })
    .select('*')
    .single()
  if (listErr) throw listErr

  const items = [...aggregated.values()].map((ing, i) => ({
    shopping_list_id: list.id,
    name: ing.name,
    quantity: formatQuantity(ing.quantity, { roundCounts: true }),
    shopping_category_id: ing.shopping_category_id,
    source_recipe_id: ing.source_recipe_id,
    source_recipe_ids: ing.source_recipe_ids,
    is_extra: false,
    checked: false,
    position: i,
  }))
  if (items.length > 0) {
    const { error: itemsErr } = await supabase.from('shopping_list_items').insert(items)
    if (itemsErr) throw itemsErr
  }
  return list as ShoppingList
}

/**
 * Calcul pur (testé) de la liste recalculée : articles issus du planning,
 * cochés s'ils l'étaient déjà, « il en manque » conservé, numérotés après
 * les articles ajoutés à la main (qui, eux, ne sont pas touchés).
 */
export function buildRegeneratedItems(
  listId: string,
  aggregated: Map<string, AggregatedIngredient>,
  current: Pick<ShoppingListItemWithCategory, 'name' | 'is_extra' | 'checked' | 'needed' | 'checked_by' | 'checked_at' | 'position'>[],
) {
  const extras = current.filter((i) => i.is_extra)
  const checkedBefore = new Map(
    current.filter((i) => !i.is_extra && i.checked).map((i) => [ingredientKey(i.name), i]),
  )
  const neededBefore = new Set(
    current.filter((i) => !i.is_extra && i.needed).map((i) => ingredientKey(i.name)),
  )
  let position = extras.reduce((m, i) => Math.max(m, i.position), -1) + 1

  return [...aggregated.entries()].map(([key, ing]) => {
    const was = checkedBefore.get(key)
    return {
      shopping_list_id: listId,
      name: ing.name,
      quantity: formatQuantity(ing.quantity, { roundCounts: true }),
      shopping_category_id: ing.shopping_category_id,
      source_recipe_id: ing.source_recipe_id,
      source_recipe_ids: ing.source_recipe_ids,
      is_extra: false,
      checked: !!was,
      needed: neededBefore.has(key),
      checked_by: was?.checked_by ?? null,
      checked_at: was?.checked_at ?? null,
      position: position++,
    }
  })

}

/**
 * Recalcule la liste active depuis le planning SANS rien perdre :
 *   - les articles ajoutés à la main (is_extra) sont gardés tels quels
 *   - les articles issus du planning sont recalculés, et ceux qui étaient
 *     déjà cochés le restent
 * Tout ou rien (migration 22) : la base remplace les articles en UNE
 * transaction (replace_planned_items). Une coupure réseau ne peut plus
 * laisser une liste vidée à moitié.
 * @returns le nombre d'articles issus du planning après recalcul
 */
export async function regenerateList(listId: string, planId: string): Promise<number> {
  if (!supabase) throw new Error('Supabase non configuré')
  const aggregated = await aggregatePlanIngredients(planId)
  const current = await fetchListItems(listId)
  const fresh = buildRegeneratedItems(listId, aggregated, current)
  const { data, error } = await supabase.rpc('replace_planned_items', {
    p_list_id: listId,
    p_plan_id: planId,
    p_items: fresh.map(({ shopping_list_id: _ignored, ...item }) => item),
  })
  if (error) throw error
  return typeof data === 'number' ? data : fresh.length
}

// ────────── Actions sur les articles ──────────

/**
 * Coche ou décoche un article.
 */
export async function toggleItem(
  itemId: string,
  checked: boolean,
  userId: string,
): Promise<void> {
  if (!supabase) throw new Error('Supabase non configuré')

  const { error } = await supabase
    .from('shopping_list_items')
    .update({
      checked,
      checked_by: checked ? userId : null,
      checked_at: checked ? new Date().toISOString() : null,
    })
    .eq('id', itemId)

  if (error) throw error
}

/**
 * Ajoute un article manuellement (hors recettes).
 */
export async function addExtraItem(
  listId: string,
  name: string,
  quantity: string | null,
  shoppingCategoryId: string | null,
): Promise<void> {
  if (!supabase) throw new Error('Supabase non configuré')

  // Trouver la position max pour mettre à la fin
  const { data: maxPos } = await supabase
    .from('shopping_list_items')
    .select('position')
    .eq('shopping_list_id', listId)
    .order('position', { ascending: false })
    .limit(1)
    .maybeSingle()

  const nextPos = (maxPos?.position ?? -1) + 1

  const { error } = await supabase
    .from('shopping_list_items')
    .insert({
      shopping_list_id: listId,
      name: name.trim(),
      quantity: quantity?.trim() || null,
      shopping_category_id: shoppingCategoryId,
      is_extra: true,
      checked: false,
      position: nextPos,
    })

  if (error) throw error
}

// ────────── Ajout depuis une recette ──────────

export interface IngredientToAdd {
  name: string
  quantity: number | null
  unit: string | null
  shopping_category_id: string | null
}

/**
 * Ajoute des ingrédients sélectionnés à la liste de courses active
 * (créée si besoin). Un ingrédient déjà présent voit sa quantité additionnée.
 * @param asExtra true quand la recette n'est PAS planifiée (« Juste les
 *   ingrédients ») : les articles sont alors marqués « ajoutés à la main » et
 *   survivent à une régénération depuis le planning.
 * @returns le nombre d'ingrédients ajoutés ou mis à jour
 */
export async function addIngredientsToList(
  familyId: string,
  ingredients: IngredientToAdd[],
  portions: number,
  defaultPortions: number,
  recipeId: string,
  asExtra = false,
): Promise<number> {
  if (!supabase) throw new Error('Supabase non configuré')
  if (ingredients.length === 0) return 0

  let list = await fetchActiveList(familyId)
  if (!list) {
    const { data: created, error: createErr } = await supabase
      .from('shopping_lists')
      .insert({ family_id: familyId, meal_plan_id: null, status: 'active' })
      .select('*')
      .single()
    if (createErr) throw createErr
    list = created as ShoppingList
  }

  const existingItems = await fetchListItems(list.id)
  const existingByKey = new Map(existingItems.map((it) => [ingredientKey(it.name), it]))
  const scale = portions / (defaultPortions || 4)
  let nextPos = existingItems.reduce((m, it) => Math.max(m, it.position), -1) + 1

  const toInsert: any[] = []
  const toUpdate: { id: string; quantity: string | null; source_recipe_ids: string[] }[] = []

  for (const ing of ingredients) {
    const qty = fromIngredient(ing.quantity, ing.unit, scale)
    const existing = existingByKey.get(ingredientKey(ing.name))
    if (existing) {
      const sources = existing.source_recipe_ids ?? []
      toUpdate.push({
        id: existing.id,
        // Arrondi après addition ; si l'article était déjà arrondi, on peut
        // compter une pièce de trop, jamais une de moins.
        quantity: formatQuantity(addQuantities(parseQuantity(existing.quantity), qty), { roundCounts: true }),
        source_recipe_ids: sources.includes(recipeId) ? sources : [...sources, recipeId],
      })
    } else {
      toInsert.push({
        shopping_list_id: list.id,
        name: ing.name.trim(),
        quantity: formatQuantity(qty, { roundCounts: true }),
        shopping_category_id: ing.shopping_category_id,
        source_recipe_id: recipeId,
        source_recipe_ids: [recipeId],
        is_extra: asExtra,
        checked: false,
        position: nextPos++,
      })
    }
  }

  for (const upd of toUpdate) {
    const { error } = await supabase
      .from('shopping_list_items')
      .update({ quantity: upd.quantity, source_recipe_ids: upd.source_recipe_ids })
      .eq('id', upd.id)
    if (error) throw error
  }
  if (toInsert.length > 0) {
    const { error } = await supabase.from('shopping_list_items').insert(toInsert)
    if (error) throw error
  }
  return toInsert.length + toUpdate.length
}

/**
 * Supprime un article de la liste.
 */
export async function removeItem(itemId: string): Promise<void> {
  if (!supabase) throw new Error('Supabase non configuré')

  const { error } = await supabase
    .from('shopping_list_items')
    .delete()
    .eq('id', itemId)

  if (error) throw error
}

/**
 * Marque la liste comme terminée.
 */
export async function completeList(listId: string): Promise<void> {
  if (!supabase) throw new Error('Supabase non configuré')

  const { error } = await supabase
    .from('shopping_lists')
    .update({
      status: 'completed',
      completed_at: new Date().toISOString(),
    })
    .eq('id', listId)

  if (error) throw error
}

/**
 * Supprime une liste et tous ses articles.
 */
export async function deleteList(listId: string): Promise<void> {
  if (!supabase) throw new Error('Supabase non configuré')

  const { data, error } = await supabase
    .from('shopping_lists')
    .delete()
    .eq('id', listId)
    .select('id')

  if (error) throw error
  // RLS : seul un admin du foyer peut supprimer (sinon 0 ligne, sans erreur)
  if (!data || data.length === 0) {
    throw new Error('Suppression refusée : seul un administrateur du foyer peut supprimer une liste.')
  }
}

// ────────── Partage (WhatsApp, SMS…) ──────────

/**
 * Texte de la liste à partager : articles encore à prendre, par rayon (dans
 * l'ordre du magasin), sans les cochés. Calcul pur (testé).
 */
export function shareListText(
  items: Pick<ShoppingListItemWithCategory, 'name' | 'quantity' | 'checked' | 'position' | 'shopping_categories'>[],
  title = 'Liste de courses',
): string {
  const groups = new Map<string, { name: string; order: number; lines: { pos: number; text: string }[] }>()
  for (const it of items) {
    if (it.checked) continue
    const cat = it.shopping_categories
    const key = cat?.id ?? '__none__'
    if (!groups.has(key)) groups.set(key, { name: cat?.name ?? 'Sans rayon', order: cat?.position ?? 999, lines: [] })
    groups.get(key)!.lines.push({ pos: it.position, text: `- ${it.name}${it.quantity ? ` (${it.quantity})` : ''}` })
  }
  const blocks = [...groups.values()]
    .sort((a, b) => a.order - b.order)
    .map((g) => [g.name, ...g.lines.sort((a, b) => a.pos - b.pos).map((l) => l.text)].join('\n'))
  return blocks.length ? `${title}\n\n${blocks.join('\n\n')}` : `${title}\n\nTout est pris.`
}
