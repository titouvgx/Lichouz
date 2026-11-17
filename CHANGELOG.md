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

## [2.7.0] — 2026-11-19

Migration : **32 `succes`** (`supabase/migrations/20261119200000_succes.sql`, contrôle `controle_32_succes.sql`),
à passer sur `courses-test` puis `lichouz-prod` AVANT le code.

### Ajouté
- **Trophées** : 40 (19 évolutifs Bronze / Argent / Or + 21 secrets), **calculés par la base** (`achievement_progress`,
  `refresh_my_achievements` qui renvoie les nouveaux paliers, `my_achievements`, seuils `achievement_tiers` = `src/lib/succes.ts`).
  Raretés (commun 10, rare 25, épique 50, légendaire 100 points) et niveau du compte.
- Toast « Trophée débloqué » (`UnlockToasts.svelte`), page **Mes trophées** (`#/succes`), résumé dans Mon compte, médailles dessinées.
- Tables `user_achievements` (écrite par la base seule), `cook_sessions` (temps en mode « En cuisine », 4 h max),
  `booster_openings` (boosters ouverts et cartes obtenues). Export « Mes données ».
- Banc RLS : 3 tables + 7 scénarios (s'attribuer un trophée, lire ceux des autres, séance trop longue ou ancienne,
  booster inventé, idempotence, export, 40 compteurs).

### Modifié
- **Conditions : version 2026-11-19** (Confidentialité « Tes trophées », durée de conservation) → chacun ré-accepte une fois.

## [2.6.0] — 2026-11-18

Migration : **31 `commentaires`** (`supabase/migrations/20261119100000_commentaires.sql`, contrôle `controle_31_commentaires.sql`),
à passer sur `courses-test` puis `lichouz-prod` AVANT le code.

### Ajouté
- **Commentaires** en bas de chaque fiche recette (`RecipeComments.svelte`, `src/lib/api/comments.ts`) : visibles
  dans la famille de l'auteur seulement (même sur le catalogue), 500 caractères, 30/h, suppression par l'auteur ou
  un admin de son foyer, pas de modification ; prénom + pseudo via `recipe_comments_list`. Export « Mes données ».
- Banc RLS : table `recipe_comments` + 9 scénarios (autre famille, usurpation, longueur, suppression, limite, export).

### Modifié
- **Conditions : version 2026-11-18** (CGU « Ce que tu ajoutes » et « Bien vivre ensemble », Confidentialité
  « La vie du foyer », « Qui voit quoi », durée de conservation) → chacun ré-accepte une fois.

## [2.5.0] — 2026-11-17

Migration : **aucune**.

### Ajouté
- **Boosters à thème** (`#/boosters`, `src/pages/Boosters.svelte`, `src/lib/boosterThemes.ts`) : Express (≤ 20 min),
  Petit budget (€), Tour du monde (une origine « Monde » par carte), Tout vert (végétarien / vegan), Réconfort,
  Les petits, Les fêtes (1er déc. – 6 janv.). Thème affiché s'il a au moins 3 recettes. Une ouverture par thème et
  par jour (clé `lichouz:booster-ouvert:<id>:<thème>`), même tirage que le booster du jour (graine par thème).
- Lien discret « + Boosters à thème » en bas de l'accueil, seulement après l'ouverture du booster du jour.
- Paquets dessinés (`BoosterArt.svelte`) : un dessin et le nom du thème en grand ; le booster du jour a un soleil.

### Modifié
- `pickBooster` : option « un par groupe » ; tirage du booster du jour inchangé.

### Corrigé
- Les cartes d'un booster ne changent plus dans la journée (planifier une carte l'écartait du tirage, une nouvelle
  étoile changeait les chances) : tirage du jour mémorisé sur le téléphone (`lichouz:booster-tirage:<id>:<booster>`).
- Page Stockage : ajout de ce que les boosters gardent sur le téléphone (précision, pas de nouvelle `TERMS_VERSION`).

## [2.4.1] — 2026-11-17

Migration : **aucune**.

### Modifié
- Ouverture du booster : aura plein écran (`BoosterAura.svelte` : halo qui part du paquet, voile léger, 16 étincelles), ~1,4 s,
  sous les fenêtres (z-index 150), jamais en mouvement réduit.

## [2.4.0] — 2026-11-17

Migration : **aucune**.

### Ajouté
- **Booster du jour** sur l'accueil (`BoosterPack.svelte`, `src/lib/booster.ts`) : paquet qui se déchire, les 5 cartes en
  jaillissent vers leur place ; une ouverture par jour (clé `lichouz:booster-ouvert:<id>` sur le téléphone), « Passer »,
  mouvement réduit → cartes directes. Reflet brillant et inclinaison 3D au doigt ; à l’ouverture, la bande se déchire et le paquet descend pendant que les cartes sortent.

### Modifié
- Tirage des recettes du jour : graine par foyer + date (avant : date seule) ; écarte les recettes du planning du foyer
  de J-14 à J+7 (complète avec elles s'il en manque) ; tirage pondéré par les étoiles (`pickWeightedSeeded`).
- `slotDate` déplacé dans `src/lib/api/meals.ts`.

## [2.3.0] — 2026-11-17

Migration : **aucune**.

### Ajouté
- Onglet **Tendances** (`src/pages/Tendances.svelte`, `src/lib/tendances.ts`) : Top 25 / 50 par étoiles
  (moyenne puis nombre de votes, recettes lisibles et non archivées, via `recipe_rating_stats`),
  plus cuisinées du mois dans le foyer (jours passés, restes exclus), nouvelles recettes des 30 derniers jours (hors catalogue).

### Modifié
- La barre du bas garde 5 onglets : **Tendances remplace Historique**, qui devient « Listes passées » (lien en haut de Courses, retour vers Courses).
- Aide et Nouveautés mises à jour.

## [2.2.0] — 2026-11-17

V2 « fun UX », 1er lot : les étoiles. **Migration 30 nécessaire** (`20261118200000_etoiles.sql`, contrôle `supabase/tests/controle_30_etoiles.sql`).

### Ajouté
- Table `recipe_ratings` (1 à 5 étoiles, une note par personne et par recette, modifiable, supprimée avec le compte) : votes privés (RLS : on ne lit que les siens), note seulement sur une recette lisible (`can_read_recipe`).
- `recipe_rating_stats(uuid[])` : moyenne + nombre de votes, seulement pour les recettes lisibles (50 par appel).
- Fiche recette : moyenne + « Ta note » ; cartes de Recettes : moyenne. Export « Mes données » : notes données.
- Banc RLS : table `recipe_ratings` et attaques de la migration 30.

## [2.1.0] — 2026-11-17

Lot P « Pratique ». **Pas de migration.** Nouvelle dépendance : `qrcode-generator` 2.0.4 (MIT, sans dépendance, version épinglée).

### Ajouté
- QR code d'invitation : « Afficher en QR code » après la création du lien (dessiné sur le téléphone, aucun service extérieur ; conseil d'adresse réservée).
- Page de présentation de Lichouz avant le formulaire d'un lien d'invitation.
- Chat de Lichouz (personnage original) : erreurs illustrées (hors connexion, serveur, interdit, introuvable, autre) avec `ErrorState` + `errorMood` ; page introuvable, fenêtre d'accueil, fiches recette et événement, Mon foyer, Administration, Mes recettes.
- Nouvelle icône et favicon (tête du chat, Brutal beurre) ; logo des écrans de connexion et de bienvenue.

### Changé
- Vocabulaire : « famille » → **foyer**, « super-famille » → **famille** dans l'appli et l'Aide (modèle de données inchangé).

## [2.0.0] — 2026-11-17

Lot C « Conformité ». **Migration 29 nécessaire** (`20261118100000_conformite.sql`, contrôle `supabase/tests/controle_29_conformite.sql`) ; elle installe l'extension `pg_cron` et la tâche de nuit `lichouz-purge`.

### Ajouté
- Conditions d'utilisation, politique de confidentialité et page « Stockage » (pages publiques `#/cgu`, `#/confidentialite`, `#/stockage`, liens sur la connexion et l'invitation).
- Fenêtre d'accueil obligatoire : pseudo + tranche d'âge + acceptation, en une fois (`accept_terms`) ; preuve gardée par version dans `terms_acceptances` (non modifiable).
- Pseudo unique (sans tenir compte des majuscules), 3-20 caractères, noms réservés, changement au plus tous les 30 jours, seulement par soi-même (trigger `guard_profile_pseudo`).
- Moins de 15 ans : accord d'un parent adulte du même foyer (`confirm_parental_consent`, `revoke_parental_consent`, `parental_consents`), sinon l'appli reste bloquée.
- Mon compte → Vie privée : pseudo, téléchargement de toutes mes données en JSON (`export_my_data`), accords parentaux, documents.
- Durées de conservation et purge automatique chaque nuit (`purge_expired_data`, pg_cron) : erreurs 90 jours, invitations terminées 90 jours, événements 1 an, listes terminées et plannings 2 ans, retours 2 ans.
- Banc RLS : table `terms_acceptances` et attaques de la migration 29.


## [1.999.0] — 2026-11-17

**Migration 28 à exécuter AVANT la mise en ligne** : `supabase/migrations/20261117120000_evenements.sql`,
puis la requête de contrôle `supabase/tests/controle_28_evenements.sql` (tout à `true`).
L'ancien site reste compatible (nouvelles tables seulement).

### Ajouté
- Thème Noël : décorations par endroits (neige posée sur la barre d'onglets, « Ajouter un article », « Qu'est-ce qu'on mange ? » et la fiche d'un événement ; boules de sapin suspendues sur Courses et Recettes). Rien en thème classique ; boules immobiles si « réduire les animations ».
- **Événements** (lot N) : modèles Noël, anniversaire, fête, autre (titre, date et pôles proposés) ;
  date, heure, chez qui, thème, lien de playlist (https seulement), infos ; visible par le foyer ou
  par toute la famille élargie (choix à la création). Pages `#/evenements` (à venir / passés,
  « éphémère » : reste en avant jusqu'à 3 jours après) et `#/evenement/<id>`.
- Réponses oui / peut-être / non (une par personne) ; « Qui fait quoi » : pôles proposés + tâches
  libres, chacun s'inscrit ou se retire lui-même (`toggle_event_volunteer`, atomique).
- Tables `events`, `event_tasks`, `event_rsvps` (RLS ; création par tout membre ; modification et
  suppression par l'auteur ou un admin du foyer) ; gardes : auteur forcé, 30 événements par foyer,
  30 tâches par événement, inscription de soi-même seulement ; `event_people` ne renvoie que les
  prénoms des personnes de l'événement ; compte supprimé → retiré des « qui fait quoi ».
- Accueil : bandeau du prochain événement (60 jours) ou « Organiser Noël » en thème Noël ;
  lien « Événements » dans Mon compte.
- Thème Noël : cheminée agrandie (guirlande, lueur), place réservée sous le bonjour.
- Banc RLS : 3 tables de plus (24), attaques sur la visibilité foyer / famille, les inscriptions,
  les réponses, les droits d'auteur.

## [1.99.3] — 2026-11-17

**Aucune migration.**

### Ajouté
- **Thème « Noël »** (lot N) : même direction artistique, palette crème / vert sapin / rouge / or,
  clair et sombre (contrastes AA vérifiés, détail dans `app.css`) ; pluie de flocons, sapins,
  cadeaux… à la place des aliments ; cheminée animée sur l'Accueil (flammes en transform/opacity,
  fixes si « mouvement réduit », pause hors écran). Activé par `<html data-theme="noel">`.
- **Mon compte → Affichage** : Automatique (Noël du 1er décembre au 6 janvier) · Classique · Noël ;
  choix gardé sur le téléphone (`lichouz:theme`), barre du navigateur assortie (`src/lib/theme.svelte.ts`).

### Corrigé
- **Mot de passe oublié** : après le nouveau mot de passe, déconnexion de tous les appareils et
  retour à la connexion (avant : l'utilisateur restait connecté). La session ouverte par le lien
  est fermée si on quitte la page sans enregistrer de mot de passe (`lichouz:recuperation-en-cours`).

## [1.99.2] — 2026-11-17

**Aucune migration.**

### Modifié
- Liste de courses plus légère : les recettes d'origine (« pour … ») sont en simple texte gris,
  sans cadre jaune ; l'étiquette « ajouté » n'est plus remplie de jaune.

## [1.99.1] — 2026-11-16

**Aucune migration.**

### Corrigé
- Changement de page ou d'onglet : l'écran précédent restait visible une fraction de seconde
  par-dessus le nouveau (effet « glitch »). L'ancien écran disparaît maintenant d'un coup,
  le nouveau arrive en glissant.

## [1.99.0] — 2026-11-16

**Dernière version de la V1** (décision du 16/11/2026 : tout livré d'un coup).

**Migrations 26 et 27 à exécuter AVANT la mise en ligne**, dans l'ordre :
`supabase/migrations/20261116200000_planning_plus.sql` puis
`supabase/migrations/20261116210000_comptes_desactives.sql`, puis les requêtes de contrôle
`supabase/tests/controle_26_planning_plus.sql` et `controle_27_comptes_desactives.sql` (tout à `true`).
L'ancien site reste compatible avec ces migrations (les repas existants deviennent des « plats »).

### Ajouté
- **Mieux planifier (V1-4)** : entrée + plat + dessert sur un même repas (`meal_slots.course`) ;
  restes planifiés (`meal_slots.leftover_of` : même recette, même foyer, repas plus tard ;
  les courses comptent les deux repas) ; recopier la semaine d'avant ; semaines types
  (tables `week_templates`, `week_template_slots`, 20 par famille) ; fonctions en une transaction
  `copy_week_slots`, `save_week_template`, `apply_week_template` (SECURITY INVOKER) ;
  minuteurs dans le mode En cuisine (durées repérées dans le texte des étapes, `src/lib/timers.ts`).
- **Restes des étiquettes (V1-2)** : filtre par temps de préparation ; étiquettes sur les cartes ;
  une étiquette touchée sur une fiche ouvre Recettes filtré sur elle.
- **Admin + (V1-9)** : désactiver / réactiver un compte (`set_account_disabled`, drapeau rangé dans
  `private.disabled_accounts`, jamais exposé ; un compte désactivé ne voit plus rien et voit un écran
  « Compte désactivé ») ; le super-admin gère le catalogue dans l'appli (choix « Catalogue commun »
  dans le formulaire, carte dans Administration).
- **Import par lien (V1-3), PRÊT MAIS DÉSACTIVÉ** : fonction serveur `importer-recette`
  (schema.org/Recipe, sites autorisés seulement, sans photo) et bouton « Importer depuis un lien »
  qui affiche « Bientôt ». Rien n'est importé tant que la question juridique n'est pas tranchée.

### Corrigé
- Modifier une recette du catalogue (super-admin) la faisait repasser en « Ma famille seulement ».
- L'accueil montre le plat principal du jour quand un repas a aussi une entrée ou un dessert.

### Sécurité
- Banc RLS : 2 tables de plus (21) ; attaques sur les restes, la copie de semaines, les semaines
  types, les comptes désactivés et le catalogue.

### Pas fait (à décider)
- Tests de parcours Playwright dans le dépôt (ajout de la dépendance refusé dans la session de travail).
- Site de test en ligne branché sur `preprod`.

## [1.9.0] — 2026-11-16

**Aucune migration.** Refonte graphique complète (direction artistique n° 6 « Brutal beurre ») :
mêmes écrans, mêmes fonctions, mêmes textes.

### Modifié
- Nouveau design system « Brutal beurre » (`src/app.css`, règles dans `docs/design.md`) : fond beurre, encre noire,
  orange pour les actions, zéro arrondi, bordures 2 px, ombres franches, police unique Bricolage Grotesque (OFL,
  hébergée avec le site ; remplace Outfit et DM Sans). Tous les réglages (couleurs, tailles, espacements,
  ombres, mouvements) sont centralisés en variables.
- Mode sombre automatique (suit le téléphone), contrastes AA vérifiés.
- Pièces communes globales : boutons qui s'enfoncent sur leur ombre, champs, puces, cartes, bandeaux,
  case à cocher, fenêtres (voile opaque, fenêtre qui monte du bas, fenêtre centrée), bouton +.
- Barre d'onglets : bloc orange qui glisse d'un onglet à l'autre (64 px de haut).
- Couleurs des catégories de recettes recalculées dans l'appli (`src/lib/categoryColors.ts`), texte noir dessus ;
  la couleur stockée en base n'est plus affichée.
- Icônes au trait carré ; couleur de la barre du navigateur et du manifeste en beurre (noir en sombre).

### Ajouté
- Fond animé « pluie lente » d'aliments au trait (`AppBackdrop.svelte`, `src/lib/motifs.ts`) : transform seulement,
  pause en arrière-plan, immobile si « réduire les animations ».

### Retiré
- Photo de mer de fond (`public/bg/mer-640.webp`, `mer-1280.webp`) et ses voiles.

## [1.8.0] — 2026-11-16

**Migrations 25 et 25 bis à exécuter AVANT la mise en ligne**, dans l'ordre :
`supabase/migrations/20261116170000_etiquettes.sql` puis
`supabase/migrations/20261116170100_recettes_etiquettes.sql` (générée par `npm run recettes`),
puis la requête de contrôle `supabase/tests/controle_25_etiquettes.sql` (une ligne, tout à `true`).
L'ancien site reste compatible (colonnes nouvelles avec valeurs par défaut).

### Ajouté
- Étiquettes des recettes (lot V1-2), **liste fixe** vérifiée par la base : régimes (végétarien,
  vegan, sans gluten, sans lactose, sans porc), origine (région de France ou pays), thèmes
  (5 au plus, dont « Inspirées de films »), budget € / €€ / €€€. Mêmes droits que modifier la recette.
- Écran Recettes : bouton « Filtres » (fenêtre du bas), filtres actifs retirables d'un appui,
  gardés pendant la session ; la recherche trouve aussi les étiquettes (début de mot, 4 lettres).
- Fiche recette : étiquettes affichées sous les infos.
- 50 recettes du catalogue étiquetées (`supabase/recettes/etiquettes.json`, régimes prudents :
  bouillon en cube et fromages à présure animale exclus de « végétarien » / « sans gluten »).
- Types de plat : Apéritif, Sauce, Petit-déj & goûter, Boisson & cocktail (nouvel ordre).
- Banc RLS : 15 attaques, 4 contrôles et 2 vérifications de structure en plus (valeurs hors liste, doublons, budget, droits ; 933 / 212 / 21).

## [1.7.0] — 2026-11-16

**Migration 24 à exécuter AVANT la mise en ligne** :
`supabase/migrations/20261116140000_invitation_email.sql`, puis la requête de contrôle
`supabase/tests/controle_24_invitation_email.sql` (une ligne, tout à `true`).
La fonction serveur `accepter-invitation` n'a **pas** besoin d'être redéployée. L'ancien site
reste compatible avec la migration (création de lien à 4 arguments acceptée).

### Ajouté
- **Invitation liée à une adresse e-mail** (facultatif) : seule cette adresse peut créer le compte
  avec le lien. La base ne garde que l'empreinte (sha256) et un indice « m•••@gmail.com » ; un refus
  laisse le lien valable pour la bonne personne. L'indice est affiché dans Ma famille, Administration
  et sur la page « Rejoindre » (qui prévient avant l'envoi si l'adresse ne correspond pas).
  Les liens déjà envoyés restent valables jusqu'à leur expiration.

### Sécurité
- « Coché par » : en modification, on ne coche plus qu'à son propre nom (avant : au nom de
  n'importe quel membre du foyer).
- Photos « orphelines » (dossier d'une recette inexistante) : visibles et supprimables seulement
  par leur auteur ou le super-admin (avant : par n'importe quel membre de n'importe quelle famille).
- Banc RLS : 918 attaques bloquées, 208 contrôles, 19 de structure ; vérifié que les nouvelles
  attaques échouent si les règles sont affaiblies.

## [1.6.0] — 2026-11-16

**Migration 23 à exécuter AVANT la mise en ligne** :
`supabase/migrations/20261116120000_journal_retours.sql`, puis la requête de contrôle
`supabase/tests/controle_23_journal_retours.sql` (une ligne, tout à `true`).

### Ajouté
- **Idées et retours** (Mon compte) : envoyer une idée, un bug ou une remarque ; lus dans
  Administration (statuts « nouveau », « lu », « fait »). 10 envois par jour et par personne.
- **Nouveautés** : une fenêtre une fois par version (pas pour une première ouverture), et la page
  Mon compte → Nouveautés (`src/lib/nouveautes.ts`, à compléter à chaque version visible).
- **Journal des erreurs** : les erreurs non rattrapées sont envoyées à la base (nettoyées : ni
  e-mail, ni jeton, ni paramètres d'adresse, ni détails d'erreur de la base ; page réduite à son
  nom) ; lisibles et purgeables dans Administration ; 30 par heure et par personne ; gardées 90 jours.
- **Guide de sauvegarde manuelle** de la prod : `docs/sauvegardes.md` (+ `.gitignore` protège les exports).

### Sécurité
- Tables `app_errors` et `feedback` : RLS (écriture pour soi-même, lecture du journal par le
  super-admin seul, statut seul modifiable), auteur et famille forcés par la base, limites de débit,
  suppression avec le compte. Banc RLS : 913 attaques bloquées, 202 contrôles, 18 de structure.

## [1.5.0] — 2026-11-16

Pas de migration, aucun réglage Supabase.

### Ajouté
- **Mes recettes** (Mon compte) : les recettes que j'ai créées, rangées en « Toutes nos familles »,
  « Ma famille seulement » et « Archivées ». Modifier, partager / garder pour ma famille, archiver /
  restaurer (admin de la famille). Le catalogue n'y apparaît pas.
- Aide mise à jour.

## [1.4.0] — 2026-11-15

**Migration 22 à exécuter AVANT la mise en ligne** :
`supabase/migrations/20261116100000_archives_limites_liste.sql`, puis la requête de contrôle
`supabase/tests/controle_22_archives_limites_liste.sql` (une ligne, tout à `true`).
Aucun réglage Supabase. Appliquée et contrôlée sur `courses-test` le 15/11/2026.

### Ajouté
- **Liste de courses** : sous chaque article, les recettes qui en ont besoin
  (« pour Gratin de courgettes · Spaghetti à la tomate »).
- **Partager la liste** (WhatsApp, SMS, note…) : ce qui reste à prendre, par rayon, via le menu
  de partage du téléphone (copie dans le presse-papiers si le téléphone ne sait pas partager).
- **Recettes archivées** : « Supprimer » devient « Archiver » (admin de la famille, ou super-admin).
  La recette disparaît des listes, de la recherche et des recettes du jour, mais reste dans les
  plannings, l'historique et les listes. « Recettes archivées » (bas de la page Recettes) pour la
  retrouver et la **restaurer**.

### Modifié
- Ce qui se compte à la pièce est **arrondi au-dessus** dans la liste (pas de « 1,5 œuf »),
  après l'addition des recettes. Les g, cl, cuillères, pincées ne sont pas arrondis.
- « Œufs » et « oeufs » sont reconnus comme le même article.
- Petit texte sous les boutons de la liste : elle ne change pas toute seule tant qu'on ne la met
  pas à jour (elle était déjà « figée » : l'idée « figer la liste » est donc abandonnée).
- Aide mise à jour.

### Corrigé
- « Mettre à jour depuis le planning » est maintenant **tout ou rien** (une seule transaction dans
  la base) : une coupure réseau ne peut plus laisser une liste vidée à moitié.
- « Beurre de cacahuète » n'est plus pris pour du « beurre » (ni « lait de coco » pour du lait)
  dans le placard et le frigo ; « huile d'olive » reste de l'huile.

### Sécurité
- **Limites de longueur** des recettes, appliquées par la base ET le formulaire : titre 120,
  ingrédient 80, unité 20, étape 1 000 caractères, 60 ingrédients et 40 étapes par recette ;
  article de liste 80 (quantité 120).
- Plus aucune suppression directe de recette par l'API : avant, supprimer une recette effaçait
  ses créneaux dans le planning de toutes les familles.
- Une recette citée comme « origine » d'un article doit être lisible par la famille.
- Banc RLS : 892 attaques bloquées, 199 contrôles positifs, 17 contrôles de structure.

## [1.3.1] — 2026-11-15

Pas de migration, aucun réglage Supabase.

### Modifié
- Fenêtre « Quand la cuisiner ? » (depuis une recette, l'Accueil ou « Qu'est-ce qu'on mange ? ») :
  les jours déjà passés de la semaine en cours sont proposés, repliés sous « Jours déjà passés (n) »
  (aujourd'hui reste en haut). Permet de noter après coup ce qu'on a mangé (Historique juste).
  Semaines précédentes : toujours par l'onglet Semaine.

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
