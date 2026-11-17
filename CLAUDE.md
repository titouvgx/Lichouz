# Lichouz — Contexte projet

**Lichouz** : PWA familiale (recettes, planning de la semaine, liste de courses partagée en temps réel).
- **Site** : https://titouvgx.github.io/Lichouz/ — **Repo** : https://github.com/titouvgx/Lichouz (public). ⚠️ **L majuscule obligatoire** (`/lichouz/` = 404). Ne pas renommer le dépôt. Site URL / Redirect URLs Supabase = `/Lichouz/`
- **À lire seulement si besoin** : `docs/migrations.md` (détail des migrations), `docs/historique.md` (versions passées, reprises, anciennes décisions), `docs/architecture.md` (Realtime, photos, hors connexion, fichiers), `docs/design.md` (design « Brutal beurre », règles UI mobile), `supabase/prod/README.md`, `tests/rls/README.md`, `docs/sauvegardes.md`

## Règles de travail (Titouan)
- Tutoiement, explications simples (il doit pouvoir les raconter). Séparer vérifié / supposé, fiabilité en %, vérifier en ligne ce qui peut changer, signaler risques et angles morts, poser les questions si l'attendu n'est pas clair
- **Économe en tokens** : pas de sous-agent, 1 capture max par écran modifié (aucune s'il teste lui-même), sorties de commandes filtrées, réponses courtes
- **Chaque version** : branche de travail → `preprod` → `main` (= déploiement, seulement après son « go »). Avant `main` : `npm run check`, `npm test`, `npm run build`, capture 393×852. `preprod` ne déploie rien ; Titouan la teste en local (`git checkout preprod && git pull && npm ci && npm run dev -- --host`, base `courses-test`). Jamais « Run workflow » du déploiement hors `main`
- **Étiquettes `vX.Y.Z` (v minuscule) et Releases : créées par Titouan** (lui donner un texte court en Markdown)
- Boîte à idées : rien sans feu vert explicite

## Stack
Svelte 5 (runes : `$state`, `$derived`, `$effect`, `$props`) + TypeScript + Vite 8 · Supabase (Postgres + RLS, Auth, Realtime, Storage, fonctions Deno, pg_cron) · GitHub Pages (routeur hash `#/route`) · service worker `pwa/sw.js` · Vitest (`tests/unit`, `tests/rls` dans PGlite)

**Pièges Svelte** : `{@const}` enfant DIRECT d'un `{#each}`/`{#if}` ; la variable du canal Realtime ne doit PAS être en `$state` (boucle infinie).

## Routes (`src/lib/router.svelte.ts`)
Tab bar (5) : Accueil | Recettes | Semaine | Courses | Tendances. Autres : `historique` (« Listes passées », depuis Courses), `nouvelle-recette`, `recette/<id>`, `editer-recette/<id>`, `compte`, `frigo`, `famille`, `mes-recettes`, `avis`, `nouveautes` (**`src/lib/nouveautes.ts` à compléter à chaque version visible**), `evenements`, `evenement/<id>`, `vie-privee`, `admin`, `aide` (**l'aide décrit l'appli : la mettre à jour quand une fonction change**). Publiques : `login`, `rejoindre/<jeton>`, `mot-de-passe-oublie`, `nouveau-mot-de-passe`, `confirmer-email` (paramètres `?token_hash=…&type=…` AVANT le `#`), `cgu`, `confidentialite`, `stockage` (`Legal.svelte`).
- **Fenêtre d'accueil obligatoire** `ConsentGate.svelte` tant que `consent.status !== 'ok'` (`src/lib/consent.svelte.ts`). **Changer le fond des textes légaux = nouvelle `TERMS_VERSION` (`src/lib/legal.ts`) + migration qui change `current_terms_version()`** → tout le monde ré-accepte
- Écran de bienvenue `Bienvenue.svelte` jusqu'à « Ne plus afficher » (clé `lichouz:bienvenue-vue:<id>`)

## Modèle (migration 17 et suivantes)
- **Vocabulaire appli** : **foyer** = table `families` ; **famille** = table `super_families` (le code et la base gardent family / super_family)
- Une personne = un foyer (`profiles.family_id`, rôle `admin`/`member`, `profiles.pseudo` obligatoire et unique) ; un foyer = une famille (`families.super_family_id`)
- **Super-admin** (`super_admins`) : voit tout. **Fondateur** (`super_families.founder_id`) : jusqu'à 3 foyers, gère dans tous. **Admin de foyer** : invite, change les rôles (pas le sien ni le fondateur), renomme, retire / désactive un membre
- Retirer = supprimer le compte (recettes gardées, auteur NULL). Pas de `DELETE` direct sur `families`, `profiles`, `recipes` : fonctions SQL (`remove_member`, `delete_family`, `delete_my_account`, `set_account_disabled`…)
- **Invitations** : lien unique 7 jours, seul `sha256(jeton)` stocké, réservable à un e-mail (empreinte + indice), compte créé par la fonction `accepter-invitation` (non confirmé → e-mail « Confirm signup »)
- **Recettes** : archivées, jamais supprimées ; `visibility` = `famille` (= foyer, défaut) | `super_famille` | `catalogue` (50 livrées, JSON dans `supabase/recettes/`, lecture seule sauf super-admin) ; étiquettes = liste fixe (CHECK + `src/lib/etiquettes.ts`, test qui compare). Planning, listes, habituels, placard, semaines types, événements : par foyer (`is_family`)
- **Étoiles** (`recipe_ratings`) : vote privé, moyenne via `recipe_rating_stats(uuid[])`
- **Commentaires** (`recipe_comments`, migration 31) : visibles dans la famille de l’auteur seulement, lecture par `recipe_comments_list(uuid)`, pas de modification
- Conformité : `terms_acceptances`, accord parental < 15 ans (`parental_consents`), `export_my_data`, purge de nuit `purge_expired_data` (pg_cron `lichouz-purge`, 03:17 UTC — **efface pour de bon**)
- API front : `src/lib/api/*.ts` ; contexte (`family`, `superFamily`, `isFounder`, `isSuperAdmin`) dans `src/lib/profile.svelte.ts`

## Migrations et bases
- Détail : `docs/migrations.md`. Contrôles : `supabase/tests/controle_NN_*.sql`. Migrations GÉNÉRÉES (16, 18, 25 bis) jamais éditées à la main (`npm run recettes`)
- **État des bases (à tenir à jour)** : `courses-test` (id `oczyjyehltrizhbuttad`, essais libres, pause après 7 j) et `lichouz-prod` (id `kfdtybskxobqfmpetzgc`) **à jour jusqu’à la migration 31** (17/11/2026, par le connecteur Supabase avec l’accord de Titouan, contrôles tout à true sur les deux). ⚠️ **Aucun export de sauvegarde de la prod** (guide `docs/sauvegardes.md`)
- **Règle** : d'abord `courses-test`, puis `lichouz-prod` **seulement avec l'accord de Titouan** (il valide la fenêtre Supabase dans les 2 minutes) ; requête de contrôle AVANT de pousser le code qui en dépend. Nouvelle table = RLS + attaques ajoutées dans `tests/rls`. Jamais les vraies recettes de la famille dans le dépôt public

## Sécurité (OBLIGATOIRE)
- **Jamais de clé secrète** (`sb_secret_…` / service_role) ni mot de passe base dans le dépôt, `.env.local` ou variables GitHub : clé **publishable** seulement (garde-fous `vite.config.ts`, `src/lib/supabase.ts`)
- **RLS jamais désactivé**. RLS = lignes ; limiter des colonnes → trigger. Viser `anon` explicitement dans les `REVOKE`
- E-mail de l'utilisateur privé. Pas de `npm audit fix --force`. Pas de ressource tierce (polices hébergées avec le site)
- **CSP** (`index.html`) : `*.supabase.co` et Unsplash seulement ; toute nouvelle source → l'ajouter
- Actions GitHub épinglées par SHA, permissions minimales
- Droits appli = droits base ; une suppression filtrée par RLS (0 ligne) est signalée, jamais affichée comme réussie
- En place : `security-check.yml`, `verifications.yml`, banc RLS (1 586 tests en v2.6.0, 28 tables), journal des erreurs `src/lib/errorReport.ts` (texte nettoyé ; insérer SANS `.select()`)

## Pièges connus
- `signIn()` ne touche PAS `auth.loading`
- Service worker : chaque déploiement recharge l'appli (différé pendant le formulaire recette) ; enregistré seulement en build
- `body` transparent (fond `AppBackdrop`) ; fenêtres `.ui-overlay` en `z-index: 200` (tab bar 100) ; aucune couleur/ombre/arrondi en dur : variables de `app.css`. Thème Noël auto du 1er décembre au 6 janvier (`src/lib/theme.svelte.ts`)
- Icônes : `Icon.svelte` (émojis seulement pour rayons et 🥕). Animer seulement `transform`/`opacity`, `prefers-reduced-motion` respecté, taps ≥ 44 px, `:hover` souris seulement
- Limites connues : la fenêtre d'accueil bloque l'appli, pas la base ; textes légaux sans juriste ; e-mails Supabase via Brevo ; import par lien prêt mais désactivé (`IMPORT_ENABLED = false`) ; **exception d’audit** GHSA-fc5q-39xc-vjpf (picomatch, outils de build) dans `verifications.yml` depuis le 17/11/2026 : à retirer dès qu’un correctif sort

## Versions
- SemVer, source unique `package.json`. **Dernier chiffre = correctifs ; fonctions nouvelles = chiffre du milieu.** Chaque changement notable → `CHANGELOG.md` `[Non publié]` (avec migrations)
- Sortir X.Y.Z : bases à jour → `npm version X.Y.Z --no-git-tag-version` → CHANGELOG daté → check + test + build + capture → `preprod` → go de Titouan → `main` → vérifier site et Actions → Titouan crée l'étiquette et la Release
- Réglages Supabase (invitations, mot de passe oublié, SMTP Brevo) : `supabase/functions/README.md`, `supabase/prod/README.md`

## État et suite (17/11/2026)
- **En ligne : v2.6.0** (17/11/2026, migration 31) : commentaires des recettes (famille seulement), conditions version 2026-11-18. Avant : 2.5.0 boosters à thème, 2.4.x booster du jour + aura, 2.3.0 Tendances
- Boosters = **petit plus, jamais central** (décision de Titouan). Album, cartes rares, boosters bonus : avec le lot Succès (une seule ré-acceptation)
- **Todo si l’appli devient publique** (décision de Titouan) : les commentaires deviendront **publics pour tout le monde** → modération (signaler, masquer, page de modération), CGU, moins de 15 ans
- **v2.7.0 Trophées** : branche `v2-7-succes`, migration 32 (40 trophées calculés en base, `TERMS_VERSION` 2026-11-19). Visibles par soi seul ; classement famille, album de cartes, cartes rares, boosters bonus : plus tard
- **Todo, NE PAS FAIRE avant feu vert** : **bibliothèque des recettes obtenues** dans les boosters (garder pour de bon les cartes sorties ; table en base + RLS + Confidentialité ; à voir avec l’album du lot Succès)
- En attente : export de sauvegarde de la prod ; relecture des textes légaux avec Titouan ; contacter Marmiton (Titouan) ; page Genèse reportée ; tests sur téléphone (QR, icône, étoiles, accord parental, fenêtre d'accueil)

## Commandes
`npm run dev` · `npm run build` · `npm run check` · `npm test` (unitaires + banc RLS) · `npm run test:unit` · `npm run test:rls` · `npm run recettes` (migrations 16 et 18) · `npm run prod:sql`
