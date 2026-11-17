// Commentaires des recettes (v2.6.0, migration 31) : visibles dans la famille
// seulement. Lecture par recipe_comments_list (prénom de l'auteur, droits),
// écriture et suppression directes (la base force auteur, famille et date).
import { supabase } from '../supabase'

export const COMMENT_MAX = 500

export interface RecipeComment {
  id: string
  body: string
  created_at: string
  author_id: string
  author_name: string | null
  author_pseudo: string | null
  mine: boolean
  can_delete: boolean
}

function db() {
  if (!supabase) throw new Error('Supabase non configuré')
  return supabase
}

export async function fetchComments(recipeId: string): Promise<RecipeComment[]> {
  const { data, error } = await db().rpc('recipe_comments_list', { p_recipe: recipeId })
  if (error) throw error
  return (data ?? []) as RecipeComment[]
}

/** Texte prêt à envoyer, ou la raison du refus (mêmes règles que la base). */
export function commentProblem(text: string): string | null {
  const t = text.trim()
  if (!t) return 'Écris quelque chose'
  if (t.length > COMMENT_MAX) return `${COMMENT_MAX} caractères au plus`
  return null
}

/** author_id / super_family_id : envoyés pour la règle, réécrits de toute façon par la base. */
export async function addComment(recipeId: string, body: string, userId: string, superFamilyId: string): Promise<void> {
  const { error } = await db()
    .from('recipe_comments')
    .insert({ recipe_id: recipeId, body: body.trim(), author_id: userId, super_family_id: superFamilyId })
  if (error) throw error
}

export async function deleteComment(id: string): Promise<void> {
  const { data, error } = await db().from('recipe_comments').delete().eq('id', id).select('id')
  if (error) throw error
  if (!data?.length) throw new Error('Commentaire introuvable ou déjà supprimé')
}
