# Design System « Brutal beurre » et règles UI mobile

> Depuis la v1.9.0 (refonte du 16/11/2026, DA n° 6 du canevas « Lichouz — 10 DA pour la liste de courses »).
> Remplace le design « Mer » (photo de mer floutée, bleu nuit, cartes arrondies translucides).
> À lire avant de toucher à l'interface.

## L'idée
Fond beurre, encre noire, une seule couleur d'action (orange). **Zéro arrondi**, bordures noires de 2 px,
**ombres franches** décalées (jamais floues), titres en majuscules très gras. Brut mais propre :
pas de dégradés, pas de verre dépoli, pas de lueurs, pas de « pastilles » rondes.

## Où sont les réglages
Tout est dans **`src/app.css`** (variables CSS sur `:root`, version sombre dans `@media (prefers-color-scheme: dark)`).
Un écran ne doit **jamais** écrire une couleur, une ombre, un arrondi ou une durée en dur : il utilise les variables.

### Couleurs (rôles)
| Variable | Clair | Sombre | Usage |
|---|---|---|---|
| `--page` | beurre `#FFE9A8` | noir `#1A1A1A` | fond de l'appli |
| `--surface` / `--bg` | blanc | anthracite `#262626` | cartes, listes, fenêtres, champs |
| `--surface-hover` | `#FFF6D6` | `#303030` | survol souris, ligne appuyée |
| `--surface-sunken` | `#FFF2C7` | `#1F1F1F` | zone en creux, chargement |
| `--text` | noir | crème `#F2EDE4` | texte |
| `--text-secondary` | `#4D4A42` | `#B8B2A6` | texte secondaire (≥ 7:1) |
| `--text-placeholder` | `#6B675C` | `#A39D90` | indications des champs |
| `--line` | noir | crème | toutes les bordures (`--line-w` 2 px, `--line-thin` 1 px) |
| `--band` / `--text-on-band` | noir / beurre | beurre / noir | bandeaux (en-têtes de rayon, de jour, de rubrique) |
| `--accent` / `--on-accent` | orange `#F06A3B` / **noir** | idem | action principale, onglet actif, case cochée, choix sélectionné |
| `--highlight` | `#FFD966` | `#5A4A12` | surlignage (aujourd'hui, filtre actif) |
| `--success`, `--success-bg`, `--error`, `--error-bg` | | | états |
| `--overlay` | noir 86 % | noir 82 % | voile derrière les fenêtres |

⚠️ **Jamais de texte blanc sur l'orange** (3,1:1, illisible) : toujours `--on-accent` (noir, 5,7:1).
Anciens noms gardés pour compatibilité : `--border`, `--border-strong` (= `--line`), `--primary` (= encre), `--radius-*` (= 0).

### Couleurs des catégories de recettes
`src/lib/categoryColors.ts` → `categoryColor(nom)` : aplats vifs, **texte toujours noir** (≥ 7,5:1) en clair comme en sombre.
La couleur stockée en base (`recipe_categories.color`) n'est plus affichée.

### Typographie
Police unique **Bricolage Grotesque** (OFL, `@fontsource-variable/bricolage-grotesque/opsz.css`, importée dans `main.ts`, hébergée avec le site).
Tailles : `--fs-xs` 12 · `--fs-sm` 14 · `--fs-base` 16 · `--fs-lg` 18 · `--fs-xl` 22 · `--fs-2xl` 28 · `--fs-3xl` 38.
Graisses : `--fw-regular` 450 · `--fw-medium` 600 · `--fw-bold` 800. `h1` = titre d'écran, **majuscules** automatiques.
Petites étiquettes et en-têtes de rubrique : majuscules + `--tracking-caps`.

### Formes, ombres, espaces
- Arrondis : **aucun** (`border-radius` interdit, sauf cercle d'une icône dessinée).
- Ombres : `--shadow-sm` 3 px · `--shadow-md` 4 px · `--shadow-lg` 6 px (décalées, sans flou). Couleur `--shadow-color` (noir, ocre en sombre).
- Espaces : `--sp-1` 4 · `--sp-2` 8 · `--sp-3` 12 · `--sp-4` 16 · `--sp-5` 24 · `--sp-6` 32 ; marge d'écran `--gutter` 18 px.
- Zones de tap : `--tap` 48 px (minimum absolu 44 px).

### Mouvement
`--dur-fast` 90 ms (appui) · `--dur-base` 180 ms · `--dur-sheet` 260 ms (fenêtre, onglet) · `--dur-page` 260 ms.
Courbes : `--ease-out` (glissements), `--ease-snap` (petit claquement : case, onglet, chute), `--ease-in`.
Style : **sec et net**, jamais mou ni rebondi. Animer seulement `transform` et `opacity`.

## Pièces communes (classes globales de `app.css`)
| Classe | Rôle |
|---|---|
| `.btn` + `.btn-primary` / `.btn-outline` / `.btn-ghost` / `.btn-danger` / `.btn-sm` / `.btn-icon` | boutons ; appuyé, il **s'enfonce sur son ombre** (`translate(--press)` + ombre retirée) |
| `.input`, `.label` | champs et libellés |
| `.card`, `.band`, `.row` | carte blanche bordée + ombre, bandeau noir, ligne de liste |
| `.chip` (+ `.active` / `aria-pressed`) | puces de filtre/catégorie |
| `.tag` | petite étiquette (« pour le gratin », « Ajouté ») |
| `.check` | case à cocher carrée, coche qui claque |
| `.ui-overlay` (+ `.center`), `.ui-sheet`, `.ui-dialog`, `.ui-head` | fenêtres : voile opaque, fenêtre qui monte du bas, fenêtre centrée |
| `.fab` | bouton + flottant |
| `.sr-only` | texte pour lecteurs d'écran |
Animations globales : `page-in`, `fade-up` (liste échelonnée avec `--i`), `snap-in`, `slide-in-right`, `pulse-soft`, `ui-fade`, `ui-sheet-up`, `ui-drop`.

Modèles à copier : `src/pages/Accueil.svelte`, `src/pages/Recettes.svelte`, `src/components/FiltersDialog.svelte`, `src/components/ConfirmDialog.svelte`.

## Fond : pluie lente d'aliments
`AppBackdrop.svelte` (monté une fois dans `App.svelte`) + `src/lib/motifs.ts` : 12 aliments au trait (dessinés pour Lichouz, pas des émojis),
tirés au hasard à chaque ouverture, un par couloir vertical, qui tombent en 18 à 32 s. Réglages : `--motif-color`, `--motif-opacity`, `--motif-accent-opacity`.
Fluidité : un calque GPU par aliment, `transform` seulement, pause quand l'appli est en arrière-plan, immobiles si « réduire les animations ».
- `html` a la couleur de fond, **`body` doit rester transparent** (sinon il masque le fond animé).

## Icônes et émojis
- **Émojis uniquement pour les rayons** (`shopping_categories.icon`) **et l'ingrédient** (🥕 du formulaire).
- Partout ailleurs : `Icon.svelte` (trait carré, angles vifs, `currentColor`).
- Recette sans photo : grande **initiale noire** sur l'aplat de sa catégorie.

## Fenêtres et superpositions
- Fenêtres : `z-index: 200` (confirmation 210), barre d'onglets 100, bouton + 90. Pas de `backdrop-filter`.
- Barre d'onglets : 64 px + zone sûre ; les écrans réservent ~84 px en bas.

## Transitions entre écrans
View Transitions (`router.svelte.ts`) : la nouvelle page arrive en glissant franchement, l'ancienne s'efface vite.
Seul `.app-shell` reçoit `view-transition-name: page`, et seulement pendant la navigation (`html[data-nav]`).
Repli : `page-in`. Barre d'onglets et avatar immobiles.

## Règles UI mobile-first
- Écran de référence 393 × 852, 60 images/s sur un téléphone moyen.
- `:hover` seulement dans `@media (hover: hover) and (pointer: fine)` ; parallaxe souris seulement.
- Hauteurs d'écran en `svh`. `touch-action: manipulation` sur ce qui se touche.
- `prefers-reduced-motion` respecté (règle globale dans `app.css`).
- Contrastes WCAG AA minimum (4,5:1 texte, 3:1 grands titres et contours d'éléments).

## Mode sombre
Suit le réglage du téléphone. Même style, couleurs inversées (voir tableau). Tout passe par les variables : un écran qui n'écrit aucune couleur en dur est automatiquement correct en sombre.
