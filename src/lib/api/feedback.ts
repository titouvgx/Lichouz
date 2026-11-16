// Retours des utilisateurs et journal des erreurs (v1.6.0, migration 23).
// Droits vérifiés par la base : chacun envoie et relit ses retours ; seul le
// super-admin lit tout, change le statut, supprime, et lit le journal.

import { supabase } from '../supabase'
import { auth } from '../auth.svelte'
import { APP_VERSION } from '../version'

export type FeedbackKind = 'idee' | 'bug' | 'autre'
export type FeedbackStatus = 'nouveau' | 'lu' | 'fait'
export const FEEDBACK_MAX = 2000

export interface FeedbackRow {
  id: string
  created_at: string
  kind: FeedbackKind
  message: string
  app_version: string | null
  status: FeedbackStatus
  profiles: { display_name: string } | null
  families: { name: string } | null
}

export interface ErrorRow {
  id: string
  created_at: string
  message: string
  route: string | null
  app_version: string | null
  user_agent: string | null
  profiles: { display_name: string } | null
}

/** Envoie une idée, un bug ou une remarque. La base remet l'auteur et la famille. */
export async function sendFeedback(kind: FeedbackKind, message: string): Promise<void> {
  if (!supabase) throw new Error('Supabase non configuré')
  const text = message.trim()
  if (!text) throw new Error('Écris quelques mots avant d’envoyer.')
  if (text.length > FEEDBACK_MAX) throw new Error(`${FEEDBACK_MAX} caractères au maximum.`)
  if (!auth.user) throw new Error('Connexion requise')
  const { error } = await supabase
    .from('feedback')
    .insert({ user_id: auth.user.id, kind, message: text, app_version: APP_VERSION.slice(0, 20) })
  if (error) throw error
}

/** Super-admin : les 100 derniers retours, avec l'auteur et sa famille. */
export async function fetchFeedback(): Promise<FeedbackRow[]> {
  if (!supabase) return []
  const { data, error } = await supabase
    .from('feedback')
    .select('id, created_at, kind, message, app_version, status, profiles(display_name), families(name)')
    .order('created_at', { ascending: false })
    .limit(100)
  if (error) throw error
  return (data ?? []) as unknown as FeedbackRow[]
}

/** Super-admin : change le statut d'un retour (le texte, lui, ne change jamais). */
export async function setFeedbackStatus(id: string, status: FeedbackStatus): Promise<void> {
  if (!supabase) throw new Error('Supabase non configuré')
  const { data, error } = await supabase.from('feedback').update({ status }).eq('id', id).select('id')
  if (error) throw error
  if (!data || data.length === 0) throw new Error('Action refusée')
}

/** Super-admin : les 100 dernières erreurs. */
export async function fetchErrors(): Promise<ErrorRow[]> {
  if (!supabase) return []
  const { data, error } = await supabase
    .from('app_errors')
    .select('id, created_at, message, route, app_version, user_agent, profiles(display_name)')
    .order('created_at', { ascending: false })
    .limit(100)
  if (error) throw error
  return (data ?? []) as unknown as ErrorRow[]
}

/** Super-admin : vide le journal des erreurs. Renvoie le nombre d'erreurs supprimées. */
export async function clearErrors(): Promise<number> {
  if (!supabase) throw new Error('Supabase non configuré')
  const { data, error } = await supabase
    .from('app_errors')
    .delete()
    .lt('created_at', new Date(Date.now() + 60_000).toISOString())
    .select('id')
  if (error) throw error
  return data?.length ?? 0
}
