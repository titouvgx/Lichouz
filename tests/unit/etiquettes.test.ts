// Étiquettes (v1.8.0) : la liste de l'appli = la liste de la base (migration 25),
// et les filtres de l'écran Recettes.
import { readFileSync } from 'node:fs'
import { join } from 'node:path'
import { describe, expect, it } from 'vitest'
import {
  BUDGETS, MAX_THEMES, NO_FILTERS, ORIGINES, REGIMES, THEMES,
  cleanKeys, countFilters, matchesTags, tagWords, sanitizeFilters, filtersFor,
} from '../../src/lib/etiquettes'

const M25 = readFileSync(join(__dirname, '../../supabase/migrations/20261116170000_etiquettes.sql'), 'utf8')

/** Valeurs entre « -- liste: x » et « -- fin » dans la migration 25. */
function listeSQL(nom: string): string[] {
  const m = M25.match(new RegExp(`-- liste: ${nom}\\n([\\s\\S]*?)-- fin`))
  if (!m) throw new Error(`liste ${nom} introuvable dans la migration 25`)
  return [...m[1].matchAll(/'([a-z_]+)'/g)].map((x) => x[1])
}

describe('étiquettes : liste de l\'appli = liste de la base', () => {
  it('régimes', () => expect(listeSQL('diets')).toEqual(REGIMES.map((e) => e.key)))
  it('origines', () => expect(listeSQL('origin')).toEqual(ORIGINES.map((e) => e.key)))
  it('thèmes', () => expect(listeSQL('themes')).toEqual(THEMES.map((e) => e.key)))
  it('5 thèmes au plus et budget 1 à 3 des deux côtés', () => {
    expect(M25).toContain(`cardinality(themes) <= ${MAX_THEMES}`)
    expect(M25).toContain('budget BETWEEN 1 AND 3')
    expect(BUDGETS.map((b) => b.value)).toEqual([1, 2, 3])
  })
  it('clés uniques et libellés non vides', () => {
    for (const l of [REGIMES, ORIGINES, THEMES]) {
      expect(new Set(l.map((e) => e.key)).size).toBe(l.length)
      for (const e of l) expect(e.label.trim()).not.toBe('')
    }
  })
})

describe('filtres de l\'écran Recettes', () => {
  const tarte = { diets: ['vegetarien'], origin: 'france', themes: ['enfants', 'fetes'], budget: 1 }
  const dahl = { diets: ['vegan'], origin: 'inde', themes: ['leger'], budget: 1 }
  const boeuf = { diets: [], origin: 'bourgogne', themes: ['hiver'], budget: 3 }
  const vide = { diets: [], origin: null, themes: [], budget: null }

  it('sans filtre : tout passe', () => {
    for (const r of [tarte, dahl, boeuf, vide]) expect(matchesTags(r, NO_FILTERS)).toBe(true)
    expect(countFilters(NO_FILTERS)).toBe(0)
  })
  it('régimes : tous exigés ; vegan compte comme végétarien', () => {
    const f = { ...NO_FILTERS, diets: ['vegetarien'] }
    expect(matchesTags(tarte, f)).toBe(true)
    expect(matchesTags(dahl, f)).toBe(true)
    expect(matchesTags(boeuf, f)).toBe(false)
    expect(matchesTags(tarte, { ...NO_FILTERS, diets: ['vegetarien', 'vegan'] })).toBe(false)
    expect(dahl.diets).toEqual(['vegan']) // la recette n'est pas modifiée
  })
  it('origine : une parmi celles choisies ; recette sans origine exclue', () => {
    const f = { ...NO_FILTERS, origins: ['inde', 'bourgogne'] }
    expect(matchesTags(dahl, f)).toBe(true)
    expect(matchesTags(boeuf, f)).toBe(true)
    expect(matchesTags(tarte, f)).toBe(false)
    expect(matchesTags(vide, f)).toBe(false)
  })
  it('thèmes : au moins un', () => {
    const f = { ...NO_FILTERS, themes: ['hiver', 'leger'] }
    expect(matchesTags(boeuf, f)).toBe(true)
    expect(matchesTags(dahl, f)).toBe(true)
    expect(matchesTags(tarte, f)).toBe(false)
  })
  it('budget : connu et inférieur ou égal', () => {
    const f = { ...NO_FILTERS, budgetMax: 2 }
    expect(matchesTags(tarte, f)).toBe(true)
    expect(matchesTags(boeuf, f)).toBe(false)
    expect(matchesTags(vide, f)).toBe(false)
    expect(countFilters({ ...f, themes: ['ete'] })).toBe(2)
  })
  it('cleanKeys garde l\'ordre de référence, sans doublon ni inconnu', () => {
    expect(cleanKeys(['vegan', 'pirate', 'vegetarien', 'vegan'], REGIMES)).toEqual(['vegetarien', 'vegan'])
  })
  it('les libellés entrent dans la recherche', () => {
    expect(tagWords(dahl)).toContain('Vegan')
    expect(tagWords(dahl)).toContain('Inde')
    expect(tagWords(vide).trim()).toBe('')
  })
})

describe('recherche dans les étiquettes', async () => {
  const { filterRecipeIndex, searchKey } = await import('../../src/lib/api/recipes')
  const entry = (id: string, title: string, tags: Partial<import('../../src/lib/etiquettes').RecipeTags>) => ({
    id, title, category_id: null, key: searchKey(title), ...tags,
    tagKey: searchKey(tagWords(tags)),
  })
  const index = [
    entry('1', 'Dahl de lentilles corail', { diets: ['vegan'], origin: 'inde', themes: ['enfants'] }),
    entry('2', 'Galettes complètes', { origin: 'bretagne', themes: ['enfants'] }),
    entry('3', 'Bœuf bourguignon', { origin: 'bourgogne' }),
  ]
  const ids = (q: string, f = NO_FILTERS) => filterRecipeIndex(index, q, null, f).map((r) => r.id)

  it('trouve par étiquette (début de mot, sans accent ni majuscule)', () => {
    expect(ids('vegan')).toEqual(['1'])
    expect(ids('bretagne')).toEqual(['2'])
    expect(ids('enfa')).toEqual(['1', '2'])
    expect(ids('enf')).toEqual([]) // moins de 4 lettres : titres seulement
  })
  it('mélange titre et étiquette', () => expect(ids('dahl vegan')).toEqual(['1']))
  it('« les » cherche dans les titres, pas dans « Les enfants adorent »', () => {
    expect(ids('les')).toEqual(['1']) // « lentilles », pas « Les enfants adorent »
    expect(ids('ent')).toEqual(['1']) // lentilles (titre)
  })
  it('les filtres s\'ajoutent à la recherche', () => {
    expect(ids('', { ...NO_FILTERS, origins: ['bretagne', 'bourgogne'] })).toEqual(['2', '3'])
    expect(ids('boeuf', { ...NO_FILTERS, origins: ['bretagne'] })).toEqual([])
  })
})

describe('temps de préparation et filtres relus (v1.99.0)', () => {
  it('filtre « au plus » : temps connu et inférieur ou égal', () => {
    const f = { ...NO_FILTERS, timeMax: 30 }
    expect(matchesTags({ prep_time_min: 20 }, f)).toBe(true)
    expect(matchesTags({ prep_time_min: 30 }, f)).toBe(true)
    expect(matchesTags({ prep_time_min: 45 }, f)).toBe(false)
    expect(matchesTags({ prep_time_min: null }, f)).toBe(false)
    expect(countFilters(f)).toBe(1)
  })

  it('sanitizeFilters ignore les valeurs inconnues', () => {
    const f = sanitizeFilters({ diets: ['vegan', 'pirate', 3], origins: ['inde'], themes: 'x', budgetMax: 9, timeMax: 45 })
    expect(f).toEqual({ diets: ['vegan'], origins: ['inde'], themes: [], budgetMax: null, timeMax: 45 })
    expect(sanitizeFilters(null)).toEqual(NO_FILTERS)
    expect(sanitizeFilters({ timeMax: 20 }).timeMax).toBeNull()
  })

  it('une étiquette touchée sur la fiche ne garde qu’elle', () => {
    expect(filtersFor({ kind: 'diet', key: 'vegan' })).toEqual({ ...NO_FILTERS, diets: ['vegan'] })
    expect(filtersFor({ kind: 'origin', key: 'bretagne' }).origins).toEqual(['bretagne'])
    expect(filtersFor({ kind: 'theme', key: 'films' }).themes).toEqual(['films'])
    expect(filtersFor({ kind: 'budget', value: 2 }).budgetMax).toBe(2)
    expect(filtersFor({ kind: 'diet', key: 'inconnu' })).toEqual(NO_FILTERS)
  })
})
