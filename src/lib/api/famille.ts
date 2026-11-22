// Familles, super-familles et invitations par lien.
// Toutes les écritures sensibles passent par des fonctions de la base
// (create_invitation, revoke_invitation, create_family) qui vérifient les
// droits ; la création de compte passe par la fonction serveur
// « accepter-invitation » (voir supabase/functions/).

import { supabase } from '../supabase'
import type { Family, FamilyMember, Invitation, SuperFamily } from '../types'

function db() {
  if (!supabase) throw new Error('Supabase non configuré')
  return supabase
}

// ────────── Membres et familles ──────────

export interface Member extends FamilyMember {
  family_id: string
  created_at: string
  /** Compte désactivé (v1.99.0, migration 27) : visible seulement par qui peut le gérer */
  disabled?: boolean
}

/** Membres d'une famille (sa famille, ou une famille de sa super-famille pour le fondateur). */
export async function fetchMembers(familyId: string): Promise<Member[]> {
  const { data, error } = await db()
    .from('profiles')
    .select('id, display_name, role, family_id, created_at')
    .eq('family_id', familyId)
    .order('created_at')
  if (error) throw error
  const members = (data ?? []) as Member[]
  // Comptes désactivés : liste vide si on n'a pas le droit de gérer cette famille
  // (ou si la migration 27 n'est pas encore passée : on n'affiche simplement rien).
  const { data: off } = await db().rpc('disabled_members', { p_family: familyId })
  const disabled = new Set(((off ?? []) as { user_id: string }[]).map((d) => d.user_id))
  return members.map((m) => ({ ...m, disabled: disabled.has(m.id) }))
}

/**
 * Désactive / réactive un compte (set_account_disabled, migration 27). Un compte
 * désactivé garde tout mais ne voit plus rien. Mêmes droits que « retirer » :
 * admin de la famille, fondateur, super-admin ; jamais soi-même, le fondateur
 * ni un super-admin.
 */
export async function setAccountDisabled(memberId: string, disabled: boolean): Promise<void> {
  const { error } = await db().rpc('set_account_disabled', { p_user: memberId, p_disabled: disabled })
  if (error) throw error
}

/** Le compte connecté est-il désactivé ? (faux si la fonction n'existe pas encore) */
export async function myAccountDisabled(): Promise<boolean> {
  const { data, error } = await db().rpc('my_account_disabled')
  if (error) return false
  return data === true
}

/** Change le rôle d'un membre (admin de la famille ou fondateur ; jamais soi-même). */
export async function setMemberRole(memberId: string, role: 'admin' | 'member'): Promise<void> {
  const { data, error } = await db().from('profiles').update({ role }).eq('id', memberId).select('id')
  if (error) throw error
  if (!data?.length) throw new Error('Modification refusée')
}

export async function renameFamily(familyId: string, name: string): Promise<void> {
  const { data, error } = await db().from('families').update({ name: name.trim() }).eq('id', familyId).select('id')
  if (error) throw error
  if (!data?.length) throw new Error('Modification refusée')
}

/** Familles d'une super-famille (visibles par ses membres et son fondateur). */
export async function fetchFamilies(superFamilyId: string): Promise<Family[]> {
  const { data, error } = await db()
    .from('families')
    .select('*')
    .eq('super_family_id', superFamilyId)
    .order('created_at')
  if (error) throw error
  return (data ?? []) as Family[]
}

/** Nombre de membres par famille (pour l'aperçu du fondateur et du super-admin). */
export async function countMembers(familyIds: string[]): Promise<Record<string, number>> {
  if (!familyIds.length) return {}
  const { data, error } = await db().from('profiles').select('family_id').in('family_id', familyIds)
  if (error) throw error
  const n: Record<string, number> = {}
  for (const r of data ?? []) n[r.family_id] = (n[r.family_id] ?? 0) + 1
  return n
}

/** Crée une famille dans sa super-famille (fondateur : 3 au maximum). */
export async function createFamily(name: string, superFamilyId?: string): Promise<string> {
  const { data, error } = await db().rpc('create_family', {
    p_name: name.trim(),
    p_super_family_id: superFamilyId ?? null,
  })
  if (error) throw error
  return data as string
}

/**
 * Retire quelqu'un de sa famille : son compte est supprimé (accès coupé tout de
 * suite, réinvitable avec le même e-mail). Droits vérifiés par la base
 * (remove_member) : admin de la famille, fondateur, super-admin ; jamais
 * soi-même, le fondateur ni un super-admin.
 */
export async function removeMember(memberId: string): Promise<void> {
  const { error } = await db().rpc('remove_member', { p_member: memberId })
  if (error) throw error
}

export type DeleteMyAccountResult = 'supprime' | 'mot_de_passe_incorrect' | 'trop_d_essais'

/**
 * Supprime le compte de la personne connectée (delete_my_account, migration 21).
 * Mot de passe vérifié par la base (5 erreurs en 15 min → bloqué 15 min).
 * Refus (erreur avec message lisible) : super-admin, fondateur, dernier admin
 * d'une famille qui a encore des membres. Ses recettes restent (auteur vide).
 */
export async function deleteMyAccount(password: string): Promise<DeleteMyAccountResult> {
  const { data, error } = await db().rpc('delete_my_account', { p_password: password })
  if (error) throw error
  if (data !== 'supprime' && data !== 'mot_de_passe_incorrect' && data !== 'trop_d_essais') {
    throw new Error('Réponse inattendue du serveur : rien n’a été confirmé.')
  }
  return data
}

/**
 * Supprime une famille VIDE (0 membre, 0 lien en attente), avec son planning,
 * ses listes et ses recettes. Fondateur ou super-admin ; vérifié par la base
 * (delete_family), qui refuse aussi sa propre famille et celle du catalogue.
 */
export async function deleteFamily(familyId: string): Promise<void> {
  const { error } = await db().rpc('delete_family', { p_family: familyId })
  if (error) throw error
}

// ────────── Invitations ──────────

export const INVITATION_DAYS = 7

export interface NewInvitation {
  id: string
  token: string
  expires_at: string
  url: string
}

/** Adresse du lien d'invitation (le jeton est après le #, il n'est donc jamais envoyé au serveur web). */
export function invitationUrl(token: string): string {
  const { origin, pathname } = window.location
  return `${origin}${pathname}#/rejoindre/${token}`
}

/**
 * Crée un lien d'invitation. Le jeton n'est renvoyé qu'ICI : la base ne garde
 * que son empreinte. Il faut donc le partager tout de suite.
 */
export async function createInvitation(
  kind: 'fondateur' | 'membre',
  opts: { familyId?: string; role?: 'admin' | 'member'; label?: string; email?: string } = {},
): Promise<NewInvitation> {
  const { data, error } = await db().rpc('create_invitation', {
    p_kind: kind,
    p_family_id: opts.familyId ?? null,
    p_role: opts.role ?? null,
    p_label: opts.label?.trim() || null,
    // v1.7.0 (migration 24) : lien réservé à cette adresse ; la base n'en garde que l'empreinte
    p_email: opts.email?.trim().toLowerCase() || null,
  })
  if (error) throw error
  const row = (Array.isArray(data) ? data[0] : data) as { id: string; token: string; expires_at: string }
  return { ...row, url: invitationUrl(row.token) }
}

export async function revokeInvitation(id: string): Promise<void> {
  const { error } = await db().rpc('revoke_invitation', { p_id: id })
  if (error) throw error
}

/** Liens d'une famille (membres) ou liens « fondateur » (super-admin). */
export async function fetchInvitations(filter: { familyIds?: string[]; kind?: 'fondateur' }): Promise<Invitation[]> {
  // Colonnes explicites : l'empreinte de l'adresse (email_hash) ne sert pas à l'écran
  let q = db()
    .from('invitations')
    .select('id, kind, family_id, role, label, created_by, created_at, expires_at, used_at, used_by, revoked_at, email_hint')
    .order('created_at', { ascending: false })
    .limit(100)
  if (filter.kind) q = q.eq('kind', filter.kind)
  if (filter.familyIds) q = q.in('family_id', filter.familyIds)
  const { data, error } = await q
  if (error) throw error
  return (data ?? []) as Invitation[]
}

export type InvitationStatus = 'valide' | 'utilisee' | 'expiree' | 'annulee'

export function invitationStatus(i: Invitation, now = Date.now()): InvitationStatus {
  if (i.revoked_at) return 'annulee'
  if (i.used_at) return 'utilisee'
  if (new Date(i.expires_at).getTime() <= now) return 'expiree'
  return 'valide'
}

/** Noms des comptes ayant utilisé des liens (pour l'historique des invitations). */
export async function namesOf(userIds: string[]): Promise<Record<string, string>> {
  const ids = [...new Set(userIds.filter(Boolean))]
  if (!ids.length) return {}
  const { data } = await db().from('profiles').select('id, display_name').in('id', ids)
  return Object.fromEntries((data ?? []).map((p) => [p.id, p.display_name]))
}

// ────────── Rejoindre (sans compte) ──────────

export interface InvitationInfo {
  status: 'valide' | 'utilisee' | 'expiree' | 'annulee' | 'inconnue'
  kind: 'fondateur' | 'membre' | null
  role: 'admin' | 'member' | null
  family_name: string | null
  /** Indice de l'adresse à qui le lien est réservé (« m•••@gmail.com »), sinon null */
  email_hint: string | null
}

/**
 * L'adresse saisie correspond-elle à l'indice « m•••@gmail.com » ? (Première
 * lettre et domaine.) Simple aide à la saisie : la vraie vérification est faite
 * par la base à la création du compte. Calcul pur (testé).
 */
export function matchesEmailHint(email: string, hint: string | null): boolean {
  if (!hint) return true
  const [first, domain] = [hint.charAt(0).toLowerCase(), hint.split('@')[1]?.toLowerCase() ?? '']
  const m = email.trim().toLowerCase()
  return m.charAt(0) === first && m.split('@')[1] === domain
}

export async function invitationInfo(token: string): Promise<InvitationInfo> {
  const { data, error } = await db().rpc('invitation_info', { p_token: token })
  if (error) throw error
  const row = (Array.isArray(data) ? data[0] : data) as InvitationInfo | undefined
  return row ? { ...row, email_hint: row.email_hint ?? null } : { status: 'inconnue', kind: null, role: null, family_name: null, email_hint: null }
}

export interface AcceptInvitationInput {
  token: string
  email: string
  password: string
  display_name: string
  family_name?: string
}

/** Indice pour l'admin quand la fonction serveur répond sans message lisible. */
function hintFor(status: number): string {
  if (status === 401) return ' : réglage « Verify JWT » à désactiver'
  if (status === 404) return ' : fonction « accepter-invitation » non déployée'
  if (status >= 500) return ' : la fonction serveur a planté, voir ses Logs'
  return ''
}

/**
 * Crée le compte via la fonction serveur, puis essaie de connecter la personne.
 * - 'connecte' : le compte était confirmé d'office (ancienne fonction serveur) ;
 * - 'a_confirmer' : l'adresse doit être confirmée (v1.3.0) → l'e-mail de
 *   confirmation vient d'être demandé, la personne doit cliquer le lien.
 * Marche avec l'ancienne comme avec la nouvelle fonction : l'ordre de mise en
 * ligne (site / fonction) n'a pas d'importance.
 */
export async function acceptInvitation(input: AcceptInvitationInput): Promise<'connecte' | 'a_confirmer'> {
  const client = db()
  const { data, error } = await client.functions.invoke('accepter-invitation', { body: input })
  if (error) {
    // Message lisible renvoyé par la fonction (JSON { erreur })
    let message = 'Le compte n’a pas pu être créé. Réessaie dans un instant.'
    const ctx = (error as { context?: unknown }).context
    const status = ctx instanceof Response ? ctx.status : null
    try {
      const body = ctx instanceof Response ? await ctx.json() : null
      if (body?.erreur) message = body.erreur
      else if (status) message = `${message} (code ${status}${hintFor(status)})`
    } catch {
      // Réponse illisible (fonction plantée, absente, mal réglée) : on donne le code
      if (status) message = `${message} (code ${status}${hintFor(status)})`
      else message = `${message} (serveur d’invitation injoignable)`
    }
    throw new Error(message)
  }
  if (!(data as { ok?: boolean })?.ok) throw new Error('Le compte n’a pas pu être créé.')
  const { error: e2 } = await client.auth.signInWithPassword({ email: input.email.trim(), password: input.password })
  if (!e2) return 'connecte'
  if ((e2 as { code?: string }).code === 'email_not_confirmed' || /not confirmed/i.test(e2.message)) {
    try {
      await resendConfirmation(input.email)
    } catch {
      // L'écran « Vérifie ta boîte mail » propose de renvoyer l'e-mail
    }
    return 'a_confirmer'
  }
  throw new Error('Compte créé ! Connecte-toi avec ton e-mail et ton mot de passe.')
}

// ────────── Confirmation de l'adresse e-mail ──────────

/**
 * (Re)envoie l'e-mail « Confirme ton adresse » (modèle « Confirm signup » de
 * Supabase, lien …/?token_hash=…&type=signup#/confirmer-email).
 * Supabase ne dit rien si l'adresse est inconnue ou déjà confirmée (pas de fuite) ;
 * une demande par minute et par adresse au plus.
 */
export async function resendConfirmation(email: string): Promise<void> {
  const { origin, pathname } = window.location
  const { error } = await db().auth.resend({
    type: 'signup',
    email: email.trim().toLowerCase(),
    options: { emailRedirectTo: `${origin}${pathname}` },
  })
  if (!error) return
  if (/rate|limit|too many|security purposes|seconds/i.test(error.message)) {
    throw new Error('E-mail déjà envoyé il y a moins d’une minute. Patiente un peu avant de redemander.')
  }
  throw new Error('L’e-mail n’a pas pu être envoyé. Réessaie dans un instant.')
}

/** Valide le lien de confirmation (?token_hash=…&type=signup) : confirme l'adresse et ouvre une session. */
export async function verifySignupLink(tokenHash: string): Promise<void> {
  const { error } = await db().auth.verifyOtp({ token_hash: tokenHash, type: 'signup' })
  if (error) throw new Error('Ce lien a expiré ou a déjà servi. Connecte-toi : l’appli te proposera de renvoyer l’e-mail.')
}

// ────────── Mot de passe oublié ──────────

/** Envoie l'e-mail de réinitialisation (même réponse que le compte existe ou non). */
export async function requestPasswordReset(email: string): Promise<void> {
  const { origin, pathname } = window.location
  const { error } = await db().auth.resetPasswordForEmail(email.trim(), { redirectTo: `${origin}${pathname}` })
  // Trop de demandes : on le dit ; sinon on ne révèle pas si l'adresse existe
  if (error && /rate|limit|too many/i.test(error.message)) {
    throw new Error('Trop de demandes. Réessaie dans une heure.')
  }
}

/** Valide le lien reçu par e-mail (?token_hash=…&type=recovery) et ouvre une session. */
export async function verifyRecoveryLink(tokenHash: string): Promise<void> {
  const { error } = await db().auth.verifyOtp({ token_hash: tokenHash, type: 'recovery' })
  if (error) throw new Error('Ce lien a expiré ou a déjà servi. Demande un nouvel e-mail.')
  setRecoveryPending(true)
}

/**
 * Le lien « mot de passe oublié » ouvre une session (Supabase). Tant que le nouveau
 * mot de passe n'est pas enregistré, cette session ne doit servir qu'à ça : on la
 * marque, et l'appli la ferme si on quitte la page (v1.99.3).
 */
const RECOVERY_KEY = 'lichouz:recuperation-en-cours'
export function setRecoveryPending(on: boolean): void {
  try {
    if (on) localStorage.setItem(RECOVERY_KEY, '1')
    else localStorage.removeItem(RECOVERY_KEY)
  } catch { /* stockage indisponible */ }
}
export function isRecoveryPending(): boolean {
  try { return localStorage.getItem(RECOVERY_KEY) === '1' } catch { return false }
}

export async function setNewPassword(password: string): Promise<void> {
  const { error } = await db().auth.updateUser({ password })
  if (error) throw new Error(error.message.includes('different') ? 'Choisis un mot de passe différent de l’ancien.' : 'Le mot de passe n’a pas pu être changé.')
}

// ────────── Super-admin ──────────

export interface SuperFamilyOverview extends SuperFamily {
  founder_name: string | null
  families: (Family & { members: number })[]
}

/** Statistiques globales (uniquement des nombres), calculées par la base. Super-admin seulement. */
export interface AdminStats {
  recettes: { famille: number; super_famille: number; catalogue: number; avec_photo: number; ajoutees_7j: number; ajoutees_30j: number }
  personnes: { total: number; nouvelles_30j: number }
  planning: { repas_semaine: number; familles_actives: number }
  courses: { listes_en_cours: number; terminees_30j: number }
  invitations: { en_attente: number }
}

export async function fetchAdminStats(): Promise<AdminStats> {
  const { data, error } = await db().rpc('admin_stats')
  if (error) {
    if (/admin_stats|schema cache|does not exist/i.test(error.message)) {
      throw new Error('Statistiques indisponibles : la migration 20 n’est pas encore appliquée sur la base.')
    }
    throw error
  }
  return data as AdminStats
}

/** Vue d'ensemble pour le super-admin (lecture seule). */
export async function fetchOverview(): Promise<SuperFamilyOverview[]> {
  const client = db()
  const [sfs, fams] = await Promise.all([
    client.from('super_families').select('*').order('created_at'),
    client.from('families').select('*').order('created_at'),
  ])
  if (sfs.error) throw sfs.error
  if (fams.error) throw fams.error
  const families = (fams.data ?? []) as Family[]
  const counts = await countMembers(families.map((f) => f.id))
  const founders = await namesOf(((sfs.data ?? []) as SuperFamily[]).map((s) => s.founder_id ?? ''))
  return ((sfs.data ?? []) as SuperFamily[]).map((sf) => ({
    ...sf,
    founder_name: sf.founder_id ? founders[sf.founder_id] ?? null : null,
    families: families.filter((f) => f.super_family_id === sf.id).map((f) => ({ ...f, members: counts[f.id] ?? 0 })),
  }))
}

/** Super-admin : déplace un foyer dans une autre famille (outil temporaire, migration 38). */
export async function moveFamily(familyId: string, superFamilyId: string): Promise<void> {
  const { error } = await db().rpc('move_family', { p_family: familyId, p_super_family: superFamilyId })
  if (error) throw error
}
