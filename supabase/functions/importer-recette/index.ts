// Fonction serveur Supabase « importer-recette » (v1.99.0, lot V1-3)
// ------------------------------------------------------------------
// Lit la page d'une recette sur un site AUTORISÉ et renvoie seulement ses
// faits (titre, ingrédients, étapes, portions, temps), lus dans le format
// standard schema.org/Recipe que publient les sites de recettes.
// La photo et les textes d'auteur ne sont jamais repris.
//
// ⚠️ DÉSACTIVÉE PAR DÉFAUT. Décision du 16/11/2026 : l'infrastructure est prête
// mais rien n'est importé tant que la question juridique (droit d'auteur,
// conditions d'utilisation des sites) n'est pas tranchée. Pour l'activer, il
// faudra les DEUX : secret IMPORT_ENABLED = true ET la liste IMPORT_SITES
// (domaines autorisés), plus IMPORT_ENABLED = true côté appli
// (src/lib/importRecipe.ts). Voir supabase/functions/README.md.
//
// Sécurité :
// - « Verify JWT » ACTIVÉ : seule une personne connectée peut l'appeler ;
// - seulement https, seulement les domaines de IMPORT_SITES (pas d'adresse IP,
//   pas de port), redirections suivies seulement vers ces domaines (3 au plus) ;
// - 8 secondes et 2 Mo au plus par page ;
// - CORS limité aux adresses de l'appli ; aucune clé secrète utilisée.
// ------------------------------------------------------------------

import { lireRecette } from './lire.ts'

export interface Reglages {
  /** Interrupteur général (secret IMPORT_ENABLED = 'true') */
  active: boolean
  /** Domaines autorisés, ex. ['marmiton.org'] (sous-domaines compris) */
  sites: string[]
  origines: string[]
}

/** Téléchargement (remplacé par un faux dans les tests). */
export type Telecharger = (url: string, signal: AbortSignal) => Promise<Response>

export const ORIGINES_PAR_DEFAUT = ['https://titouvgx.github.io', 'http://localhost:5173', 'http://localhost:4173']
const TAILLE_MAX = 2 * 1024 * 1024
const DELAI_MS = 8000
const REDIRECTIONS_MAX = 3

function entetesCors(origine: string | null, origines: string[]): Record<string, string> {
  const h: Record<string, string> = {
    'Access-Control-Allow-Methods': 'POST, OPTIONS',
    'Access-Control-Allow-Headers':
      'authorization, x-client-info, apikey, content-type, x-retry-count, traceparent, tracestate, baggage',
    'Access-Control-Max-Age': '600',
    Vary: 'Origin',
  }
  if (origine && origines.includes(origine)) h['Access-Control-Allow-Origin'] = origine
  return h
}

function json(statut: number, corps: unknown, cors: Record<string, string>): Response {
  return new Response(JSON.stringify(corps), {
    status: statut,
    headers: { ...cors, 'Content-Type': 'application/json; charset=utf-8', 'Cache-Control': 'no-store' },
  })
}

/** Adresse autorisée : https, port par défaut, nom de domaine (pas d'IP) de la liste. */
export function adresseAutorisee(brute: string, sites: string[]): URL | null {
  let u: URL
  try {
    u = new URL(brute)
  } catch {
    return null
  }
  if (u.protocol !== 'https:' || u.port !== '' || u.username || u.password) return null
  const hote = u.hostname.toLowerCase().replace(/\.$/, '')
  // Pas d'adresse IP (v4 ou v6) : seulement des noms de la liste
  if (/^\d+(\.\d+){3}$/.test(hote) || hote.includes(':') || hote.startsWith('[')) return null
  const ok = sites.some((s) => {
    const d = s.trim().toLowerCase().replace(/^\.+|\.+$/g, '')
    return d.length > 0 && (hote === d || hote.endsWith(`.${d}`))
  })
  return ok ? u : null
}

/** Lit au plus `max` octets d'une réponse (null si trop gros). */
async function lireLimite(rep: Response, max: number): Promise<string | null> {
  const longueur = Number(rep.headers.get('Content-Length') ?? 0)
  if (longueur > max) return null
  if (!rep.body) return await rep.text()
  const lecteur = rep.body.getReader()
  const morceaux: Uint8Array[] = []
  let total = 0
  for (;;) {
    const { done, value } = await lecteur.read()
    if (done) break
    total += value.byteLength
    if (total > max) {
      await lecteur.cancel()
      return null
    }
    morceaux.push(value)
  }
  const tout = new Uint8Array(total)
  let pos = 0
  for (const m of morceaux) {
    tout.set(m, pos)
    pos += m.byteLength
  }
  return new TextDecoder('utf-8').decode(tout)
}

/** Logique de la fonction, indépendante de Deno (testée dans tests/unit). */
export async function traiter(req: Request, reglages: Reglages, telecharger: Telecharger): Promise<Response> {
  const origine = req.headers.get('Origin')
  const cors = entetesCors(origine, reglages.origines)

  if (req.method === 'OPTIONS') return new Response(null, { status: 204, headers: cors })
  if (req.method !== 'POST') return json(405, { erreur: 'Méthode non autorisée' }, cors)
  if (origine && !reglages.origines.includes(origine)) return json(403, { erreur: 'Origine non autorisée' }, cors)

  // Interrupteur : tant que la question juridique n'est pas réglée, rien n'est lu
  if (!reglages.active || reglages.sites.length === 0) {
    return json(503, { erreur: 'L’import par lien n’est pas encore activé.', code: 'desactive' }, cors)
  }

  let corps: Record<string, unknown>
  try {
    const t = await req.text()
    if (t.length > 2048) return json(413, { erreur: 'Demande trop grande' }, cors)
    corps = JSON.parse(t)
  } catch {
    return json(400, { erreur: 'Demande illisible' }, cors)
  }
  const brute = typeof corps.url === 'string' ? corps.url.trim() : ''
  const depart = adresseAutorisee(brute, reglages.sites)
  if (!depart) {
    return json(400, { erreur: 'Ce site n’est pas dans la liste des sites autorisés.', code: 'site_refuse' }, cors)
  }
  let cible: URL = depart

  const controle = new AbortController()
  const minuteur = setTimeout(() => controle.abort(), DELAI_MS)
  try {
    let rep: Response | null = null
    for (let i = 0; i <= REDIRECTIONS_MAX; i++) {
      rep = await telecharger(cible.toString(), controle.signal)
      if (rep.status >= 300 && rep.status < 400) {
        const suite = rep.headers.get('Location')
        const prochaine: URL | null = suite ? adresseAutorisee(new URL(suite, cible).toString(), reglages.sites) : null
        if (!prochaine) return json(502, { erreur: 'Le site renvoie vers une adresse non autorisée.', code: 'redirection' }, cors)
        cible = prochaine
        rep = null
        continue
      }
      break
    }
    if (!rep) return json(502, { erreur: 'Trop de redirections.', code: 'redirection' }, cors)
    if (!rep.ok) return json(502, { erreur: `Le site a répondu ${rep.status}.`, code: 'site_erreur' }, cors)
    const type = rep.headers.get('Content-Type') ?? ''
    if (!/text\/html|application\/xhtml/i.test(type)) {
      return json(422, { erreur: 'Cette adresse n’est pas une page de recette.', code: 'pas_html' }, cors)
    }
    const html = await lireLimite(rep, TAILLE_MAX)
    if (html === null) return json(413, { erreur: 'Page trop lourde.', code: 'trop_gros' }, cors)
    const recette = lireRecette(html, cible.toString())
    if (!recette) {
      return json(422, { erreur: 'Aucune recette lisible sur cette page.', code: 'introuvable' }, cors)
    }
    return json(200, { recette }, cors)
  } catch (e) {
    const delai = (e as Error)?.name === 'AbortError'
    return json(504, { erreur: delai ? 'Le site met trop de temps à répondre.' : 'Le site est injoignable.', code: delai ? 'delai' : 'reseau' }, cors)
  } finally {
    clearTimeout(minuteur)
  }
}

// ── Démarrage (Deno, chez Supabase) ──
declare const Deno: { env: { get(n: string): string | undefined }; serve(h: (r: Request) => Response | Promise<Response>): void } | undefined
if (typeof Deno !== 'undefined') {
  const liste = (n: string) => (Deno!.env.get(n) ?? '').split(',').map((x) => x.trim()).filter(Boolean)
  const reglages: Reglages = {
    active: Deno.env.get('IMPORT_ENABLED') === 'true',
    sites: liste('IMPORT_SITES'),
    origines: liste('ALLOWED_ORIGINS').length ? liste('ALLOWED_ORIGINS') : ORIGINES_PAR_DEFAUT,
  }
  const telecharger: Telecharger = (url, signal) =>
    fetch(url, {
      redirect: 'manual',
      signal,
      headers: { Accept: 'text/html', 'User-Agent': 'Lichouz/1.99 (appli familiale ; import de recette à la demande)' },
    })
  Deno.serve((req) => traiter(req, reglages, telecharger))
}
