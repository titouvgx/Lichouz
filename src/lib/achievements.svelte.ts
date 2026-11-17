// Vérification des trophées (v2.7.0) : demande à la base les paliers nouvellement
// atteints et les met en file pour le toast « Trophée débloqué ». Appelée à
// l'ouverture, au retour sur l'appli, en changeant de page et après les actions
// qui comptent ; au plus une fois toutes les 15 s (sauf `force`).
import { refreshAchievements } from './api/succes'
import { BY_KEY, type Achievement } from './succes'

export interface UnlockToast {
  id: number
  achievement: Achievement
  tier: number
}

export const unlockQueue = $state<{ items: UnlockToast[] }>({ items: [] })

let last = 0
let running = false
let nextId = 1
const MIN_GAP_MS = 15_000

export async function checkAchievements(force = false): Promise<void> {
  const now = Date.now()
  if (running || (!force && now - last < MIN_GAP_MS)) return
  running = true
  last = now
  try {
    const fresh = await refreshAchievements()
    // Un seul toast par trophée : le plus haut palier obtenu d'un coup
    const best = new Map<string, number>()
    for (const u of fresh) best.set(u.achievement, Math.max(best.get(u.achievement) ?? 0, u.tier))
    for (const [key, tier] of best) {
      const a = BY_KEY.get(key)
      if (a) unlockQueue.items = [...unlockQueue.items, { id: nextId++, achievement: a, tier }]
    }
  } catch {
    /* hors connexion ou base sans la migration 32 : on réessaiera plus tard */
  } finally {
    running = false
  }
}

export function dismissUnlock(id: number): void {
  unlockQueue.items = unlockQueue.items.filter((t) => t.id !== id)
}
