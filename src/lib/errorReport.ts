// Journal des erreurs (v1.6.0, migration 23) : une erreur sur le téléphone de
// quelqu'un de la famille est envoyée dans public.app_errors, lisible par le
// super-admin seulement (Administration).
//
// Vie privée : rien de personnel ne doit partir. Le texte est nettoyé
// (e-mails, jetons, paramètres d'adresse) et la page envoyée se limite à son
// nom (« recette », « rejoindre »…), jamais au jeton d'invitation qui la suit.
// Jamais d'envoi sans être connecté, hors connexion, ni plus de 10 fois par
// ouverture de l'appli. Un échec d'envoi est ignoré (pas de boucle).

import { supabase } from './supabase'
import { auth } from './auth.svelte'
import { APP_VERSION } from './version'

const MAX_PER_LAUNCH = 10
let sentThisLaunch = 0
const alreadySent = new Set<string>()

/** Retire ce qui pourrait identifier une personne ou ouvrir un accès. Calcul pur (testé). */
export function sanitizeErrorText(text: string, max: number): string {
  return text
    .replace(/[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}/gi, '[e-mail]')
    .replace(/eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+(\.[A-Za-z0-9_-]+)?/g, '[jeton]')
    .replace(/([?&#][A-Za-z_]*(token|hash|code|key|password|secret)[A-Za-z_]*=)[^&#\s]+/gi, '$1[masqué]')
    .replace(/\?[^\s#)]*/g, '?[…]')
    .replace(/#\/rejoindre\/[^\s)]+/g, '#/rejoindre/[jeton]')
    .replace(/\b[A-Za-z0-9_-]{32,}\b/g, (m) => (/^[0-9a-f-]{36}$/i.test(m) ? m : '[jeton]'))
    .slice(0, max)
}

/** Nom de la page seulement : « #/rejoindre/<jeton> » → « rejoindre ». Calcul pur (testé). */
export function routeName(hash: string): string {
  const name = hash.replace(/^#\/?/, '').split(/[/?]/)[0]
  return (name || 'accueil').slice(0, 40)
}

/** Erreurs sans intérêt (réseau coupé, extensions, annulations) : pas envoyées. Calcul pur (testé). */
export function isNoise(message: string): boolean {
  return (
    /^Script error\.?$/i.test(message) ||
    /ResizeObserver loop/i.test(message) ||
    /AbortError|The operation was aborted/i.test(message) ||
    /Failed to fetch|Load failed|NetworkError|network request failed/i.test(message)
  )
}

/**
 * Texte de l'erreur, SANS ses détails : une erreur de la base peut porter dans
 * `details` / `hint` le contenu de la ligne refusée (texte d'une recette…).
 * On ne garde que le nom, le code et le message. Calcul pur (testé).
 */
export function messageOf(reason: unknown): { message: string; stack?: string } {
  if (reason instanceof Error) {
    const code = (reason as { code?: unknown }).code
    return {
      message: `${reason.name}${typeof code === 'string' ? ` ${code}` : ''}: ${reason.message}`,
      stack: reason.stack,
    }
  }
  if (typeof reason === 'string') return { message: reason }
  if (reason && typeof reason === 'object') {
    const r = reason as { code?: unknown; message?: unknown }
    const code = typeof r.code === 'string' ? `${r.code}: ` : ''
    return { message: typeof r.message === 'string' ? `${code}${r.message}` : `${code}Erreur sans message` }
  }
  return { message: String(reason) }
}

/** Envoie une erreur au journal. Ne lève jamais d'exception. */
export async function reportError(reason: unknown): Promise<void> {
  try {
    if (!supabase || !auth.user || !navigator.onLine) return
    if (sentThisLaunch >= MAX_PER_LAUNCH) return
    const { message, stack } = messageOf(reason)
    if (!message || isNoise(message)) return
    const clean = sanitizeErrorText(message, 500)
    if (alreadySent.has(clean)) return
    alreadySent.add(clean)
    sentThisLaunch++
    // Sans .select() : un membre n'a pas le droit de relire le journal.
    await supabase.from('app_errors').insert({
      user_id: auth.user.id, // la base remet de toute façon l'auteur
      message: clean,
      stack: stack ? sanitizeErrorText(stack, 4000) : null,
      route: routeName(location.hash),
      app_version: APP_VERSION.slice(0, 20),
      user_agent: navigator.userAgent.slice(0, 300),
    })
  } catch {
    // Silencieux : le journal ne doit jamais casser l'appli
  }
}

/** Branche le journal sur les erreurs non rattrapées (à appeler une fois au démarrage). */
export function installErrorReporting(): void {
  window.addEventListener('error', (e) => void reportError(e.error ?? e.message))
  window.addEventListener('unhandledrejection', (e) => void reportError(e.reason))
}
