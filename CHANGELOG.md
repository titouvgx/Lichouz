# Journal des versions

Toutes les évolutions notables de Lichouz (anciennement « Courses en famille »).
Format inspiré de [Keep a Changelog](https://keepachangelog.com/fr/1.1.0/),
numérotation [SemVer](https://semver.org/lang/fr/) : **MAJEUR.MINEUR.CORRECTIF**.

## Règle de numérotation

| Changement | Exemple | Numéro |
|---|---|---|
| Correction de bug, texte, réglage visuel | une quantité mal arrondie | `1.0.0` → `1.0.1` |
| Nouvelle fonction qui ne casse rien | minuteurs en cuisine | `1.0.1` → `1.1.0` |
| Changement qui casse l'existant (modèle de données, droits) | familles multiples (V2) | `1.4.2` → `2.0.0` |

- **Source unique** : le champ `version` de `package.json`. Elle s'affiche dans l'appli
  (Mon compte et page de connexion) avec le commit court : `v1.0.0 · a1b2c3d`.
- Entre deux versions, chaque déploiement garde le même numéro ; le commit court les distingue.
- Chaque version indique les **migrations Supabase nécessaires**. À exécuter dans la base
  **avant** de pousser le code qui en dépend.
- Procédure de sortie : voir « Sortir une version » dans `CLAUDE.md`.

## [Non publié]

## [1.3.0] — 2026-11-15

Pas de migration. **Réglages Supabase AVANT la mise en ligne** (voir `supabase/prod/README.md`) :
SMTP personnel (Brevo) + modèle « Confirm signup » (`supabase/emails/confirm-signup.html`).
**Puis** redéployer la fonction `accepter-invitation` (l'ordre site / fonction n'a pas d'importance).

### Ajouté
- **Confirmation de l'adresse e-mail à la création du compte** : après l'invitation, la personne reçoit
  « Confirme ton adresse pour Lichouz » et ne peut pas se connecter avant d'avoir cliqué le lien
  (prouve que l'adresse est à elle, évite les fautes de frappe).
- Écran « Vérifie ta boîte mail » après la création du compte, avec « Renvoyer l'e-mail » (une fois par minute).
- Page `#/confirmer-email` : le lien confirme l'adresse, ouvre la session et mène à l'accueil.
- Connexion : si l'adresse n'est pas confirmée, bouton « Renvoyer l'e-mail de confirmation ».
- Aide : question « Je n'arrive pas à me connecter juste après avoir créé mon compte ».

### Modifié
- Fonction `accepter-invitation` : compte créé non confirmé (`email_confirm: false`). Les comptes existants
  restent confirmés.

## [1.2.0] — 2026-11-15

Migration nécessaire : **21** (`20261115140000_supprimer_mon_compte.sql`), à exécuter AVANT le déploiement,
puis la requête de contrôle `supabase/tests/controle_21_supprimer_mon_compte.sql` (tout à true).

### Ajouté
- Mon compte : **Supprimer mon compte**, tout en bas. Confirmation en tapant « SUPPRIMER » **et** son
  mot de passe (vérifié par la base, pas seulement par l'appli). Après suppression, l'appli efface ce
  qu'elle gardait sur le téléphone et revient à l'écran de connexion.
- Fonction `delete_my_account` : refuse le super-admin, le fondateur, et le dernier admin d'une famille
  qui a encore d'autres membres. Les recettes de la personne restent (auteur vide), comme pour « Retirer ».
  Une personne seule dans sa famille peut partir : la famille reste, vide (le fondateur la supprime ensuite).
- Anti-devinette : 5 mots de passe faux en 15 minutes → suppression bloquée 15 minutes
  (table cachée `private.account_deletion_attempts`, jamais exposée par l'API).
- Aide : question « Je veux supprimer mon compte ».
- Banc RLS : 10 attaques et 6 contrôles positifs de plus (880 attaques bloquées, 198 contrôles).

## [1.1.0] — 2026-11-15

Migration nécessaire : **20** (`20261115120000_admin_stats.sql`), à exécuter AVANT le déploiement.

### Ajouté
- Administration : section **Statistiques** (super-admin) : recettes privées / partagées / catalogue,
  ajoutées sur 7 et 30 jours, avec photo ; repas prévus et familles qui planifient cette semaine ;
  listes de courses en cours et terminées sur 30 jours ; comptes, nouveaux comptes, liens en attente.
  Calculées par la base (`admin_stats()`) : uniquement des nombres, aucun contenu privé ne sort.

### Technique
- `@types/node` 26.6.6 (Dependabot). TypeScript 7 refusé pour l'instant (svelte-check ne le
  prend pas encore en charge) : Dependabot ignore désormais les versions majeures de TypeScript.

## [1.0.0] — 2026-11-15 — Première version en production (base `lichouz-prod`)

Installation d'une base neuve : migrations **1 à 19** via `npm run prod:sql` (guide `supabase/prod/README.md`),
contrôle 1 / 1 / 50 / 0 validé le 15/11/2026. Depuis la 0.9.0 (base existante) : migrations **17** (`20261114100000_familles_invitations.sql`), **18**
(`20261114110000_recettes_photos.sql`), **19** (`20261114120000_admin_famille.sql`) + fonction serveur
`accepter-invitation` déployée + réglages Auth (voir `CLAUDE.md`, « Supabase : réglages… »).

### Ajouté
- Fichier `LICENSE` : tous droits réservés (Titouan Perivier--Vigouroux) ; éléments de tiers sous leur propre licence.
- **Invitations par lien** : le super-admin invite des fondateurs ; un fondateur crée son compte
  puis sa famille, peut créer jusqu'à 3 familles et y inviter ; l'admin d'une famille invite
  (rôle membre ou admin). Lien à usage unique, valable 7 jours, annulable, partageable en un geste.
- Pages **Ma famille** (membres, rôles, invitations, familles du fondateur) et **Administration**.
- **Mot de passe oublié** depuis la connexion (lien par e-mail, nouveau mot de passe).
- **Qui voit la recette** : « Ma famille seulement » (par défaut) ou « Toutes nos familles » ;
  les 50 recettes livrées forment un **catalogue commun** en lecture seule.
- **Retirer quelqu'un d'une famille** (Ma famille, icône corbeille) : son compte est supprimé, il ne
  peut plus se connecter ; ses recettes restent ; il peut être réinvité avec le même e-mail.
  Admin : dans sa famille ; fondateur : dans toutes ses familles ; jamais soi-même ni le fondateur.
- **Fondateur** : voit les membres de ses autres familles (« Membres (n) »), change leur rôle,
  les retire, et **supprime une famille vide** (0 membre, 0 lien en attente).

- **Aide** (Mon compte → Aide) : à quoi sert Lichouz, chaque onglet expliqué, « Ma famille » selon
  ton rôle, questions fréquentes. **Écran de bienvenue** plein écran à chaque ouverture, avec
  « Ne plus afficher » pour le fermer définitivement sur ce téléphone.

### Modifié
- **L'appli s'appelle désormais Lichouz** (onglet, écran d'accueil du téléphone, connexion,
  invitation, Mon compte). Nouvelle adresse `https://titouvgx.github.io/Lichouz/` (L majuscule
  obligatoire) : réinstaller l'appli, mettre à jour Site URL / Redirect URLs dans Supabase
  (`docs/renommage-lichouz.md`).

### Corrigé
- **Création de compte par lien** : la fonction serveur `accepter-invitation` chargeait `supabase-js`
  par un import dynamique, absent du paquet déployé par Supabase → elle plantait. Import statique,
  en-têtes CORS alignés sur `supabase-js`. **À redéployer** (copier-coller `index.ts`).
- Si la création de compte échoue, l'écran donne le code d'erreur et un indice (Verify JWT,
  fonction non déployée, fonction plantée).

### Sécurité
- Migration 19 : retrait et suppression uniquement par les fonctions `remove_member` et
  `delete_family`, qui vérifient les droits ; plus aucun `DELETE` direct sur les familles et les
  profils, même super-admin. La famille du catalogue ne peut pas être supprimée, ni une famille
  dont une recette est au planning d'une autre. Corrigé : un admin pouvait renommer les autres
  membres, et faire passer le fondateur « membre ». Banc : 861 attaques bloquées, 191 contrôles.
- Règles d'accès réécrites et banc d'attaque étendu (familles, super-familles, invitations,
  visibilité). Comptes créés uniquement par la fonction serveur (clé secrète jamais dans le site).
- Corrigé : une liste ne peut plus être rattachée au planning d'un autre foyer ; l'auteur d'une
  recette et « coché par » ne peuvent plus désigner quelqu'un d'une autre famille.

## [0.9.0] — 2026-11-13 — Candidate V1 (base `courses-test`)

Migrations nécessaires : **1 à 16** (`supabase/migrations/`, dans l'ordre).
⚠️ La migration 15 (`photo_paths`) s'exécute **juste après** le déploiement de cette version.

### Fonctions (V1)
- Connexion par e-mail et mot de passe (inscriptions fermées, comptes créés par le super-admin).
- Accueil : 5 recettes du jour qui flottent, tirage identique pour tous, renouvelé à minuit.
- Recettes partagées entre les foyers : recherche sans accents ni ordre des mots, filtres,
  photos (compressées, sans GPS), portions ajustables, mode « En cuisine ».
- Semaine : planning midi et soir, temps réel entre les membres du foyer, « Qui cuisine ? ».
- Courses : liste générée par rayon, temps réel, hors connexion, mise à jour sans perte,
  achats habituels, placard (« Sûrement déjà à la maison », « Il en manque »).
- « Qu'est-ce qu'on mange ? » : recettes classées selon ce qu'il y a dans le frigo.
- Historique des listes terminées. Mon compte. Appli installable (PWA).

### Ajouté (préparation de la V1)
- Numéro de version affiché dans l'appli, journal des versions (ce fichier).
- Migration 14 : environ 200 ingrédients de plus pour l'autocomplétion (rayon rempli automatiquement).
- Tests automatiques dans le dépôt : calculs de quantités et banc d'attaque RLS entre foyers
  (rejoue toutes les migrations dans une base PostgreSQL locale).
- Vérification automatique de chaque proposition de modification (types, tests, build, secrets).

### Recettes
- Les 20 recettes de démo corrigées : temps réalistes (repos et marinade indiqués à part),
  quantités (bourguignon, blanquette, gratin, hachis, lasagnes…), repère de cuisson du poulet
  (75 °C à cœur), avertissement œufs crus (mousse, carbonara), ingrédients manquants ajoutés,
  rayons et unités harmonisés. Une recette déjà modifiée dans l'appli n'est pas touchée.
- 30 nouvelles recettes familiales : pot-au-feu, chili, curry, couscous, risotto, pizza,
  moules, dahl, tomates farcies, taboulé, œufs mimosa, purée, riz pilaf, gâteau au yaourt,
  clafoutis, crumble, cookies…
- Recettes tenues dans `supabase/recettes/*.json`, migration générée et vérifiée par les tests.

### Sécurité
- **Faille corrigée (migration 15)** : une recette pouvait afficher une image hébergée sur le stockage
  de n'importe quel projet Supabase (« pixel espion »). Les photos sont désormais enregistrées par
  chemin dans notre stockage (le fichier doit exister) ; seule autre origine : Unsplash. L'appli
  n'affiche jamais une image d'une autre origine.
- Politique de sécurité du contenu (CSP) : seuls les scripts du site s'exécutent ; seuls
  Supabase et Unsplash peuvent être contactés.
- Polices hébergées avec le site : plus aucun appel à Google Fonts.
- Le build refuse toute clé secrète Supabase, dans n'importe quelle variable `VITE_…`
  et dans les fichiers produits.
- Actions GitHub épinglées par empreinte, permissions minimales, mises à jour surveillées (Dependabot).

### Modifié
- Service worker : nom de cache propre à chaque déploiement (l'ancien cache est effacé),
  pas de rechargement automatique pendant la saisie d'une recette, cache limité au site,
  à Supabase (`*.supabase.co`) et à Unsplash.
