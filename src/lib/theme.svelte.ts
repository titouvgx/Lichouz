// Thème de l'appli (v1.99.3) : « Classique » (Brutal beurre) ou « Noël ».
//
// Choix de la personne, gardé sur ce téléphone (réglage d'affichage, comme la taille
// du texte : pas besoin de la base). « Automatique » = Noël pendant les fêtes
// (du 1er décembre au 6 janvier, heure du téléphone), Classique le reste de l'année.
// Le mode clair / sombre suit toujours le téléphone, dans les deux thèmes.

export type ThemeChoice = 'auto' | 'classique' | 'noel'
export type ThemeName = 'classique' | 'noel'

export const THEME_CHOICES: readonly { value: ThemeChoice; label: string; hint: string }[] = [
  { value: 'auto', label: 'Automatique', hint: 'Noël du 1er décembre au 6 janvier, Classique le reste de l’année' },
  { value: 'classique', label: 'Classique', hint: 'Beurre, encre et orange, toute l’année' },
  { value: 'noel', label: 'Noël', hint: 'Crème, sapin, rouge et or, tout de suite' },
]

const KEY = 'lichouz:theme'

/** Période des fêtes : du 1er décembre au 6 janvier inclus. */
export function isHolidaySeason(d: Date = new Date()): boolean {
  const m = d.getMonth() // 0 = janvier
  return m === 11 || (m === 0 && d.getDate() <= 6)
}

export function resolveTheme(choice: ThemeChoice, d: Date = new Date()): ThemeName {
  if (choice === 'auto') return isHolidaySeason(d) ? 'noel' : 'classique'
  return choice
}

function readChoice(): ThemeChoice {
  try {
    const v = localStorage.getItem(KEY)
    if (v === 'auto' || v === 'classique' || v === 'noel') return v
  } catch { /* stockage indisponible : réglage par défaut */ }
  return 'auto'
}

export const theme = $state<{ choice: ThemeChoice; name: ThemeName }>({
  choice: 'auto',
  name: 'classique',
})

/** Couleurs de la barre du navigateur (doivent suivre --page, clair et sombre). */
const BAR_COLORS: Record<ThemeName, { light: string; dark: string }> = {
  classique: { light: '#FFE9A8', dark: '#1A1A1A' },
  noel: { light: '#FBEFE3', dark: '#0E2318' },
}

function apply() {
  theme.name = resolveTheme(theme.choice)
  const root = document.documentElement
  if (theme.name === 'classique') delete root.dataset.theme
  else root.dataset.theme = theme.name
  const colors = BAR_COLORS[theme.name]
  for (const meta of document.querySelectorAll<HTMLMetaElement>('meta[name="theme-color"]')) {
    meta.content = meta.media.includes('dark') ? colors.dark : colors.light
  }
}

/** À appeler une fois au démarrage, avant le montage (pas d'éclair de l'autre thème). */
export function initTheme() {
  theme.choice = readChoice()
  apply()
  // L'appli peut rester ouverte des jours : on revérifie la date au retour sur l'écran
  document.addEventListener('visibilitychange', () => {
    if (document.visibilityState === 'visible' && theme.choice === 'auto') apply()
  })
}

export function setTheme(choice: ThemeChoice) {
  theme.choice = choice
  try {
    if (choice === 'auto') localStorage.removeItem(KEY)
    else localStorage.setItem(KEY, choice)
  } catch { /* tant pis : le choix vaut jusqu'à la fermeture */ }
  apply()
}
