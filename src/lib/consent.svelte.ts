// État de l'acceptation des conditions (v2.0.0). La fenêtre d'accueil (ConsentGate)
// bloque l'appli tant que l'état n'est pas « ok ».
// Hors connexion : si ce téléphone a déjà vu « ok » pour cette personne et cette
// version, on ne bloque pas (sinon l'appli serait inutilisable sans réseau).
import { fetchConsentStatus, type ConsentStatus } from './api/conformite'
import { TERMS_VERSION } from './legal'

const cacheKey = (userId: string) => `lichouz:conditions:${userId}`

export const consent = $state<{ userId: string | null; status: ConsentStatus | 'chargement' | 'erreur' }>({
  userId: null,
  status: 'chargement',
})

function cachedOk(userId: string): boolean {
  try {
    return localStorage.getItem(cacheKey(userId)) === TERMS_VERSION
  } catch {
    return false
  }
}

export function setConsentStatus(userId: string, status: ConsentStatus): void {
  consent.userId = userId
  consent.status = status
  try {
    if (status === 'ok') localStorage.setItem(cacheKey(userId), TERMS_VERSION)
    else localStorage.removeItem(cacheKey(userId))
  } catch {
    // stockage indisponible : sans conséquence
  }
}

export async function loadConsent(userId: string): Promise<void> {
  if (consent.userId !== userId) {
    consent.userId = userId
    consent.status = cachedOk(userId) ? 'ok' : 'chargement'
  }
  try {
    setConsentStatus(userId, await fetchConsentStatus(userId))
  } catch (e) {
    console.error('Conditions : état illisible', e)
    if (!cachedOk(userId)) consent.status = 'erreur'
  }
}

export function clearConsent(): void {
  consent.userId = null
  consent.status = 'chargement'
}
