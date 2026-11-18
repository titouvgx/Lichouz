// Modération par le super-admin (v2.9.0, migration 35). Les trois fonctions SQL
// refusent tout autre compte (42501) ; ici on ne fait que les appeler.
import { supabase } from '../supabase'

export interface ModerationComment {
  id: string
  body: string
  created_at: string
  recipe_id: string
  recipe_title: string
  author_id: string
  author_pseudo: string | null
  author_name: string | null
  family_name: string | null
  disabled: boolean
}

export interface ModerationAccount {
  user_id: string
  pseudo: string | null
  display_name: string
  role: 'admin' | 'member'
  family_name: string | null
  created_at: string
  disabled: boolean
  is_super: boolean
}

function db() {
  if (!supabase) throw new Error('Supabase non configuré')
  return supabase
}

export async function fetchModerationComments(limit = 100): Promise<ModerationComment[]> {
  const { data, error } = await db().rpc('moderation_comments', { p_limit: limit })
  if (error) throw error
  return (data ?? []) as ModerationComment[]
}

export async function deleteModerationComment(id: string): Promise<void> {
  const { error } = await db().rpc('moderation_delete_comment', { p_id: id })
  if (error) throw error
}

export async function fetchModerationAccounts(): Promise<ModerationAccount[]> {
  const { data, error } = await db().rpc('moderation_accounts')
  if (error) throw error
  return (data ?? []) as ModerationAccount[]
}
