// Import d'une recette par lien (v1.99.0, lot V1-3) : lecture schema.org/Recipe,
// sites autorisés, interrupteur. La fonction est désactivée par défaut.
import { describe, expect, it } from 'vitest'
import { lireRecette, minutesIso, texte } from '../../supabase/functions/importer-recette/lire.ts'
import { adresseAutorisee, traiter, type Reglages, type Telecharger } from '../../supabase/functions/importer-recette/index.ts'
import { splitIngredientLine, toFormRecipe } from '../../src/lib/importRecipe'

const page = (ld: unknown, extra = '') =>
  `<html><head><title>x</title>${extra}<script type="application/ld+json">${JSON.stringify(ld)}</script></head><body><img src="photo.jpg"></body></html>`

const RECETTE = {
  '@context': 'https://schema.org',
  '@type': 'Recipe',
  name: 'Gratin dauphinois &amp; crème',
  image: 'https://exemple.test/photo.jpg',
  description: 'Un long texte d’auteur qui ne doit pas être repris.',
  recipeYield: '6 personnes',
  totalTime: 'PT1H30M',
  recipeIngredient: ['1 kg de pommes de terre', '50 cl de crème', ' 2 gousses d’ail '],
  recipeInstructions: [
    { '@type': 'HowToStep', text: 'Éplucher les pommes de terre.' },
    { '@type': 'HowToSection', name: 'Cuisson', itemListElement: [{ '@type': 'HowToStep', text: '<b>Cuire</b> 1 h à 180 °C.' }] },
  ],
}

describe('lireRecette', () => {
  it('garde titre, ingrédients, étapes, portions et temps ; jamais la photo ni la description', () => {
    const r = lireRecette(page(RECETTE), 'https://exemple.test/r')!
    expect(r).toEqual({
      titre: 'Gratin dauphinois & crème',
      ingredients: ['1 kg de pommes de terre', '50 cl de crème', '2 gousses d’ail'],
      etapes: ['Éplucher les pommes de terre.', 'Cuire 1 h à 180 °C.'],
      portions: 6,
      minutes: 90,
      source: 'https://exemple.test/r',
    })
    expect(JSON.stringify(r)).not.toMatch(/photo|auteur/)
  })
  it('trouve la recette dans un @graph, un tableau, ou un @type multiple', () => {
    expect(lireRecette(page({ '@graph': [{ '@type': 'WebPage' }, RECETTE] }), 's')?.titre).toBe('Gratin dauphinois & crème')
    expect(lireRecette(page([{ '@type': 'Organization' }, { ...RECETTE, '@type': ['Recipe', 'Thing'] }]), 's')?.portions).toBe(6)
  })
  it('étapes données en un seul texte : une par ligne', () => {
    const r = lireRecette(page({ ...RECETTE, recipeInstructions: 'Étape un.\nÉtape deux.<br>Étape trois.' }), 's')!
    expect(r.etapes).toEqual(['Étape un.', 'Étape deux.', 'Étape trois.'])
  })
  it('ignore un JSON-LD cassé et une page sans recette', () => {
    expect(lireRecette('<script type="application/ld+json">{oups</script>', 's')).toBeNull()
    expect(lireRecette(page({ '@type': 'Article', name: 'x' }), 's')).toBeNull()
    expect(lireRecette(page({ '@type': 'Recipe', name: 'Vide' }), 's')).toBeNull()
  })
  it('respecte les limites de la base (60 ingrédients, 40 étapes, titre 120)', () => {
    const r = lireRecette(page({
      '@type': 'Recipe', name: 'T'.repeat(300),
      recipeIngredient: Array.from({ length: 80 }, (_, i) => `ing ${i}`),
      recipeInstructions: Array.from({ length: 60 }, (_, i) => `étape ${i}`),
    }), 's')!
    expect(r.titre.length).toBe(120)
    expect(r.ingredients).toHaveLength(60)
    expect(r.etapes).toHaveLength(40)
  })
  it('durées ISO 8601 et texte nettoyé', () => {
    expect(minutesIso('PT45M')).toBe(45)
    expect(minutesIso('P0DT2H')).toBe(120)
    expect(minutesIso('PT0M')).toBeNull()
    expect(minutesIso('45 min')).toBeNull()
    expect(texte('<p>Un&nbsp;&quot;test&quot; &#233;t&#xe9;</p>')).toBe('Un "test" été')
  })
})

describe('adresseAutorisee', () => {
  const sites = ['marmiton.org', 'cuisineaz.com']
  it('accepte le domaine et ses sous-domaines en https', () => {
    expect(adresseAutorisee('https://www.marmiton.org/recettes/x.aspx', sites)?.hostname).toBe('www.marmiton.org')
    expect(adresseAutorisee('https://marmiton.org/x', sites)).not.toBeNull()
  })
  it('refuse le reste : http, autre site, sosie, IP, port, identifiants, adresse invalide', () => {
    for (const u of [
      'http://www.marmiton.org/x', 'https://exemple.com/x', 'https://marmiton.org.pirate.com/x',
      'https://faux-marmiton.org/x', 'https://127.0.0.1/x', 'https://[::1]/x', 'https://marmiton.org:8443/x',
      'https://moi:secret@marmiton.org/x', 'pas une adresse', 'file:///etc/passwd',
    ]) expect(adresseAutorisee(u, sites), u).toBeNull()
  })
})

describe('traiter (fonction serveur)', () => {
  const ON: Reglages = { active: true, sites: ['exemple.test'], origines: ['https://titouvgx.github.io'] }
  const demande = (url: string, origine = 'https://titouvgx.github.io') =>
    new Request('https://x.supabase.co/functions/v1/importer-recette', {
      method: 'POST', headers: { Origin: origine, 'Content-Type': 'application/json' }, body: JSON.stringify({ url }),
    })
  const html = (corps: string, statut = 200, entetes: Record<string, string> = { 'Content-Type': 'text/html; charset=utf-8' }): Telecharger =>
    async () => new Response(corps, { status: statut, headers: entetes })

  it('DÉSACTIVÉE par défaut : ne télécharge rien et le dit', async () => {
    let appels = 0
    const espion: Telecharger = async () => (appels++, new Response(''))
    for (const r of [{ ...ON, active: false }, { ...ON, sites: [] }]) {
      const rep = await traiter(demande('https://exemple.test/r'), r, espion)
      expect(rep.status).toBe(503)
      expect((await rep.json()).code).toBe('desactive')
    }
    expect(appels).toBe(0)
  })
  it('activée : renvoie les faits de la recette', async () => {
    const rep = await traiter(demande('https://exemple.test/r'), ON, html(page(RECETTE)))
    expect(rep.status).toBe(200)
    const { recette } = await rep.json()
    expect(recette.titre).toBe('Gratin dauphinois & crème')
    expect(rep.headers.get('Access-Control-Allow-Origin')).toBe('https://titouvgx.github.io')
  })
  it('site non autorisé : refusé sans téléchargement', async () => {
    let appels = 0
    const rep = await traiter(demande('https://autre.test/r'), ON, async () => (appels++, new Response('')))
    expect(rep.status).toBe(400)
    expect(appels).toBe(0)
  })
  it('origine inconnue refusée', async () => {
    const rep = await traiter(demande('https://exemple.test/r', 'https://pirate.test'), ON, html(page(RECETTE)))
    expect(rep.status).toBe(403)
  })
  it('redirection vers un autre site : refusée ; vers le même site : suivie', async () => {
    const vers = (loc: string): Telecharger => async (url) =>
      url.endsWith('/r') ? new Response(null, { status: 302, headers: { Location: loc } }) : new Response(page(RECETTE), { headers: { 'Content-Type': 'text/html' } })
    expect((await traiter(demande('https://exemple.test/r'), ON, vers('https://169.254.169.254/latest'))).status).toBe(502)
    expect((await traiter(demande('https://exemple.test/r'), ON, vers('https://pirate.test/x'))).status).toBe(502)
    expect((await traiter(demande('https://exemple.test/r'), ON, vers('/recette-2'))).status).toBe(200)
  })
  it('page trop lourde, pas du HTML, sans recette, erreur du site', async () => {
    expect((await traiter(demande('https://exemple.test/r'), ON, html('x'.repeat(3 * 1024 * 1024)))).status).toBe(413)
    expect((await traiter(demande('https://exemple.test/r'), ON, html('{}', 200, { 'Content-Type': 'application/json' }))).status).toBe(422)
    expect((await traiter(demande('https://exemple.test/r'), ON, html('<html></html>'))).status).toBe(422)
    expect((await traiter(demande('https://exemple.test/r'), ON, html('', 404))).status).toBe(502)
  })
  it('méthode autre que POST refusée ; OPTIONS répond pour le navigateur', async () => {
    const get = new Request('https://x/f', { method: 'GET' })
    expect((await traiter(get, ON, html(''))).status).toBe(405)
    const opt = new Request('https://x/f', { method: 'OPTIONS', headers: { Origin: 'https://titouvgx.github.io' } })
    expect((await traiter(opt, ON, html(''))).status).toBe(204)
  })
})

describe('côté appli : découper une ligne d’ingrédient', () => {
  it.each([
    ['200 g de farine', { qty: '200', unit: 'g', name: 'farine' }],
    ['1 kg de pommes de terre', { qty: '1', unit: 'kg', name: 'pommes de terre' }],
    ['50 cl de crème', { qty: '50', unit: 'cl', name: 'crème' }],
    ['3 œufs', { qty: '3', unit: '', name: 'œufs' }],
    ['1/2 citron', { qty: '0,5', unit: '', name: 'citron' }],
    ['½ botte de persil', { qty: '0,5', unit: 'botte', name: 'persil' }],
    ['2 gousses d’ail', { qty: '2', unit: 'gousses', name: 'ail' }],
    ['1 cuillère à soupe d\'huile d\'olive', { qty: '1', unit: 'c. à soupe', name: 'huile d\'olive' }],
    ['2 c. à café de sel', { qty: '2', unit: 'c. à café', name: 'sel' }],
    ['1,5 l de lait', { qty: '1,5', unit: 'l', name: 'lait' }],
    ['Sel, poivre', { qty: '', unit: '', name: 'Sel, poivre' }],
    ['2 à 3 tomates', { qty: '3', unit: '', name: 'tomates' }],
  ])('%s', (ligne, attendu) => {
    expect(splitIngredientLine(ligne)).toEqual(attendu)
  })
  it('toFormRecipe : portions et temps par défaut raisonnables', () => {
    const f = toFormRecipe({ titre: 'T', ingredients: ['200 g de farine'], etapes: ['Mélanger.'], portions: null, minutes: 25, source: 's' })
    expect(f).toEqual({ title: 'T', portions: 4, minutes: 25, ingredients: [{ qty: '200', unit: 'g', name: 'farine' }], steps: ['Mélanger.'] })
  })
})
