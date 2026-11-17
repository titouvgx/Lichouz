// Conformité (v2.0.0, migration 29) : acceptation des conditions, pseudo,
// accord parental, export de mes données.
import { supabase } from '../supabase'
import { TERMS_VERSION, type AgeGroup } from '../legal'

export type ConsentStatus = 'a_accepter' | 'attente_parent' | 'ok'

function db() {
  if (!supabase) throw new Error('Supabase non configuré')
  return supabase
}

/** Où en est la personne connectée pour la version en vigueur ? */
export async function fetchConsentStatus(userId: string): Promise<ConsentStatus> {
  const { data, error } = await db()
    .from('terms_acceptances')
    .select('age_group, parent_confirmed_at')
    .eq('profile_id', userId)
    .eq('version', TERMS_VERSION)
    .maybeSingle()
  if (error) throw error
  if (!data) return 'a_accepter'
  return data.age_group === 'moins_15' && !data.parent_confirmed_at ? 'attente_parent' : 'ok'
}

/** Pseudo + acceptation en une seule opération (la base vérifie tout). */
export async function acceptTerms(ageGroup: AgeGroup, pseudo: string | null): Promise<ConsentStatus> {
  const { data, error } = await db().rpc('accept_terms', {
    p_version: TERMS_VERSION,
    p_age_group: ageGroup,
    p_pseudo: pseudo,
  })
  if (error) throw error
  return data === 'attente_parent' ? 'attente_parent' : 'ok'
}

export async function pseudoAvailable(pseudo: string): Promise<boolean> {
  const { data, error } = await db().rpc('pseudo_available', { p: pseudo.trim() })
  if (error) throw error
  return data === true
}

/** Change mon pseudo (au plus une fois tous les 30 jours, vérifié par la base). */
export async function updatePseudo(userId: string, pseudo: string): Promise<void> {
  const { data, error } = await db().from('profiles').update({ pseudo: pseudo.trim() }).eq('id', userId).select('id')
  if (error) throw error
  if (!data?.length) throw new Error('Modification refusée')
}

export interface ParentalConsent {
  profile_id: string
  display_name: string
  accepted_at: string
  confirmed_at: string | null
}

export async function fetchParentalConsents(): Promise<ParentalConsent[]> {
  const { data, error } = await db().rpc('parental_consents')
  if (error) throw error
  return (data ?? []) as ParentalConsent[]
}

export async function confirmParentalConsent(childId: string): Promise<void> {
  const { error } = await db().rpc('confirm_parental_consent', { p_child: childId })
  if (error) throw error
}

export async function revokeParentalConsent(childId: string): Promise<void> {
  const { error } = await db().rpc('revoke_parental_consent', { p_child: childId })
  if (error) throw error
}

/** Toutes mes données (droit d'accès / portabilité), en JSON. */
export async function exportMyData(): Promise<unknown> {
  const { data, error } = await db().rpc('export_my_data')
  if (error) throw error
  return data
}

/** Messages d'erreur lisibles pour la fenêtre d'accueil et le changement de pseudo. */
export function consentErrorMessage(e: any): string {
  const code = e?.code as string | undefined
  const msg = String(e?.message ?? '')
  if (code === '23505') return 'Ce pseudo est déjà pris'
  if (code === '23514') return 'Ce pseudo n’est pas valable'
  if (/30 jours/.test(msg)) return 'Tu as déjà changé de pseudo il y a moins de 30 jours'
  if (/plus en vigueur/.test(msg)) return 'Les conditions ont changé : recharge l’appli'
  if (/Failed to fetch|NetworkError|network/i.test(msg)) return 'Pas de connexion : réessaie quand tu as du réseau'
  return 'Ça n’a pas marché, réessaie'
}
