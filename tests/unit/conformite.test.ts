// Conformité (v2.0.0) : règles du pseudo et version des conditions = celles de la base
// (migration 29), et durées de conservation affichées = durées de la purge.
import { readFileSync, readdirSync } from 'node:fs'
import { join } from 'node:path'
import { describe, expect, it } from 'vitest'
import { RESERVED_PSEUDOS, pseudoProblem, suggestPseudo } from '../../src/lib/pseudo'
import { TERMS_VERSION, RETENTION } from '../../src/lib/legal'

const M29 = readFileSync(join(__dirname, '../../supabase/migrations/20261118100000_conformite.sql'), 'utf8')

describe('conformité : l\'appli et la base disent la même chose', () => {
  it('liste des pseudos réservés identique', () => {
    const m = M29.match(/ANY \(ARRAY\[([\s\S]*?)\]\)/)
    expect(m).not.toBeNull()
    const sql = [...m![1].matchAll(/'([a-z_]+)'/g)].map((x) => x[1])
    expect([...RESERVED_PSEUDOS].sort()).toEqual(sql.sort())
  })
  it('version des conditions identique (dernière migration qui la définit)', () => {
    const dir = join(__dirname, '../../supabase/migrations')
    const last = readdirSync(dir).filter((f) => f.endsWith('.sql')).sort()
      .map((f) => readFileSync(join(dir, f), 'utf8'))
      .filter((sql) => sql.includes('FUNCTION public.current_terms_version()'))
      .pop()!
    expect(last).toContain(`SELECT '${TERMS_VERSION}'::text`)
  })
  it('durées de conservation : la purge efface bien ce que la page annonce', () => {
    expect(M29).toMatch(/app_errors WHERE created_at < now\(\) - interval '90 days'/)
    expect(M29).toMatch(/events WHERE starts_on < current_date - interval '1 year'/)
    expect(M29).toMatch(/feedback WHERE created_at < now\(\) - interval '2 years'/)
    expect(M29).toMatch(/shopping_lists WHERE status = 'completed' AND completed_at < now\(\) - interval '2 years'/)
    expect(M29).toMatch(/meal_plans WHERE week_start < current_date - interval '2 years'/)
    const txt = RETENTION.map((r) => `${r.what} ${r.how}`).join(' | ')
    for (const d of ['90 jours', '1 an', '2 ans']) expect(txt).toContain(d)
  })
})

describe('pseudo : règles', () => {
  it.each(['Margot.92', 'chef_a', 'abc', 'A'.repeat(20), 'petit.a'])('accepte %s', (p) => {
    expect(pseudoProblem(p)).toBeNull()
  })
  it.each(['ab', 'A'.repeat(21), 'é_lodie', 'a b', '.debut', 'fin_', 'deux..points', 'admin', 'Admin_du_site', 'LichouzTeam', 'support'])(
    'refuse %s',
    (p) => {
      expect(pseudoProblem(p)).not.toBeNull()
    },
  )
  it('propose un pseudo à partir du prénom', () => {
    expect(suggestPseudo('Élodie')).toBe('Elodie')
    expect(suggestPseudo('Jean Marc')).toBe('Jean_Marc')
    expect(suggestPseudo('Al')).toBe('') // trop court : rien de proposé
  })
})
