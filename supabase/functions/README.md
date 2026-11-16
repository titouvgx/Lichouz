# Fonctions serveur Supabase

## `accepter-invitation`

Crée le compte d'une personne invitée par lien, puis la rattache à sa famille
(ou crée sa super-famille et sa famille pour un lien « fondateur »). C'est le
seul endroit où la **clé secrète** est utilisée : elle reste dans Supabase
(variable `SUPABASE_SECRET_KEYS`, fournie automatiquement par la plateforme),
jamais dans le dépôt ni dans le site.

La logique (`traiter`) est testée dans `tests/unit/accepter-invitation.test.ts`
avec un faux Supabase, et le fichier est vérifié par `deno check`.

### Déployer depuis le tableau de bord (sans rien installer)

1. Supabase → ton projet → **Edge Functions** → **Deploy a new function** → **Via Editor**.
2. Nom : `accepter-invitation` (exactement).
3. Remplace tout le code par le contenu de `supabase/functions/accepter-invitation/index.ts`, puis **Deploy**.
4. Dans la page de la fonction → **Details / Settings** : désactive **Verify JWT**
   (« Enforce JWT verification »). La personne n'a pas encore de compte : la
   fonction vérifie elle-même le lien d'invitation.
5. (Facultatif) **Edge Functions → Secrets** : `ALLOWED_ORIGINS` =
   `https://titouvgx.github.io,http://localhost:5173` (adresses autorisées à
   appeler la fonction depuis un navigateur ; ce sont les valeurs par défaut).
6. Prérequis : la migration `20261114100000_familles_invitations.sql` exécutée.

### Mettre à jour une fonction déjà déployée

Edge Functions → `accepter-invitation` → **Code** → remplacer tout le code par le
nouveau `index.ts` → **Deploy**. Vérifier ensuite que **Verify JWT** est toujours désactivé.

**v1.3.0** : la fonction crée le compte **non confirmé** (`email_confirm: false`). Avant de la
redéployer : SMTP personnel (Brevo) branché + modèle « Confirm signup » collé (voir
`supabase/prod/README.md`), sinon les nouveaux comptes ne pourront jamais se connecter.

### Avec la ligne de commande (alternative)

```bash
supabase functions deploy accepter-invitation --no-verify-jwt --use-api
```

### Vérifier

Dans l'appli : Mon compte → Ma famille → « Inviter quelqu'un » → ouvrir le lien
dans une fenêtre privée → créer un compte de test → il apparaît dans la famille.
Logs : Edge Functions → accepter-invitation → **Logs**.

### Piège : le nom affiché n'est pas l'adresse
Dans le tableau de bord, une fonction a un **nom affiché** et une **adresse** (colonne URL,
`…/functions/v1/<adresse>`). Le site appelle `…/functions/v1/accepter-invitation` : c'est
l'**adresse** qui doit valoir `accepter-invitation`. L'éditeur propose une adresse au hasard
(ex. `dynamic-api`) et on ne peut pas la changer ensuite → créer une nouvelle fonction en tapant
`accepter-invitation` dès la création. Vérification : ouvrir l'URL dans un navigateur doit
afficher `{"erreur":"Méthode non autorisée"}` (404 `NOT_FOUND` = mauvaise adresse).

### Si la création de compte échoue
L'écran « Rejoindre » affiche le code renvoyé :
- **401** : « Verify JWT » est encore activé → le désactiver ;
- **404** : fonction absente ou mal nommée → la (re)déployer sous le nom `accepter-invitation` ;
- **500 / 503** : la fonction plante → Logs. Ne jamais remettre d'import dynamique
  (`await import(variable)`) : Supabase n'emballe que les imports statiques.

## `importer-recette` (v1.99.0) — PRÊTE MAIS DÉSACTIVÉE

Lit la page d'une recette sur un site **autorisé** et renvoie seulement ses faits
(titre, ingrédients, étapes, portions, temps), au format standard schema.org/Recipe.
Jamais la photo ni les textes d'auteur. Logique testée dans `tests/unit/importer-recette.test.ts`.

**Décision du 16/11/2026** : rien n'est importé tant que la question juridique (droit
d'auteur, conditions d'utilisation des sites) n'est pas tranchée. Le bouton « Importer
depuis un lien » du formulaire affiche seulement « Bientôt ». **Ne pas déployer avant.**

Pour l'activer un jour (les trois sont nécessaires) :
1. Déployer la fonction (`importer-recette`, **Verify JWT ACTIVÉ** : réservé aux personnes connectées).
   Elle est en deux fichiers (`index.ts` + `lire.ts`) : avec l'éditeur du tableau de bord, créer
   les deux fichiers ; ou `supabase functions deploy importer-recette --use-api`.
2. Secrets de la fonction : `IMPORT_ENABLED` = `true` et `IMPORT_SITES` = domaines autorisés,
   séparés par des virgules (ex. `marmiton.org,cuisineaz.com`). Sans eux, la fonction répond
   « pas encore activé » et ne télécharge rien. (`ALLOWED_ORIGINS` facultatif, comme plus haut.)
3. Dans l'appli : `IMPORT_ENABLED = true` dans `src/lib/importRecipe.ts`, puis une version.

Sécurité : https seulement, domaines de la liste seulement (pas d'IP, pas de port),
redirections suivies seulement vers ces domaines (3 au plus), 8 s et 2 Mo au plus.
