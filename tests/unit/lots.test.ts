// Lots de recettes du catalogue (supabase/recettes/lots/lot-NN.json) : format valide
// et migrations générées à jour (sinon : npm run recettes).
import { existsSync, readFileSync } from 'node:fs'
import { join } from 'node:path'
import { describe, expect, it } from 'vitest'
import { DOSSIER_MIGRATIONS } from '../../scripts/recettes/generer.ts'
import { genererLotPhotosSQL, genererLotSQL, lireLots } from '../../scripts/recettes/lots.ts'

describe('lots de recettes du catalogue', () => {
  const { lots, erreurs } = lireLots()

  it('chaque lot respecte le format, les étiquettes et les photos', () => {
    expect(lots.length).toBeGreaterThan(0)
    expect(erreurs).toEqual([])
  })

  it('les migrations des lots sont à jour (sinon : npm run recettes)', () => {
    for (const lot of lots) {
      const actuel = readFileSync(join(DOSSIER_MIGRATIONS, lot.migration), 'utf8')
      expect(actuel === genererLotSQL(lot), `${lot.migration} différente du JSON`).toBe(true)
      const ph = genererLotPhotosSQL(lot)
      if (ph === null) expect(existsSync(join(DOSSIER_MIGRATIONS, lot.migration_photos)), `${lot.migration_photos} sans photo dans le JSON`).toBe(false)
      else expect(readFileSync(join(DOSSIER_MIGRATIONS, lot.migration_photos), 'utf8') === ph, `${lot.migration_photos} différente du JSON`).toBe(true)
    }
  })

  it('le lot 2 : 10 recettes, 3 cocktails dans « Boisson & cocktail », aucune photo pour l’instant ou toutes vérifiées', () => {
    const l = lots.find((x) => x.nom === 'lot-02')!
    expect(l.recettes).toHaveLength(10)
    expect(l.recettes.filter((r) => r.category === 'Boisson & cocktail')).toHaveLength(3)
  })
})
