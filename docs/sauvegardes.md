# Sauvegarder la base de prod (`lichouz-prod`)

**Pourquoi** : l'offre gratuite de Supabase ne fait pas de sauvegarde automatique pour toi. Supabase
recommande aux projets gratuits d'exporter régulièrement leurs données avec la commande
`supabase db dump` et de garder une copie ailleurs (vérifié le 16/11/2026 dans la documentation
Supabase « Database Backups »).

**Quand** : une fois par semaine, et toujours **avant une migration** sur la prod.

**Décision du 16/11/2026** : export **manuel**, lancé par Titouan. Aucun mot de passe de base n'est
stocké dans le dépôt ni sur GitHub. (Plus tard : Raspberry avec une copie automatique chiffrée.)

---

## 1. Une seule fois : préparer l'ordinateur

1. Installer **Node.js** (déjà fait si tu peux lancer `npm`).
2. Installer **Docker Desktop** et le lancer : la commande `supabase db dump` s'en sert pour faire
   tourner l'outil d'export de Postgres. *(Supposé d'après le fonctionnement habituel de la CLI ;
   si la commande se plaint de Docker, c'est lui qu'il manque.)*
3. Créer un dossier **en dehors du dépôt**, par exemple `Documents/Lichouz-sauvegardes/`.
   ⚠️ Jamais dans le dossier du dépôt : il est public.

## 2. À chaque sauvegarde

1. Supabase → projet **lichouz-prod** → bouton **Connect** → copier la chaîne de connexion
   **Session pooler** (elle contient `[YOUR-PASSWORD]` : remplace-le par le mot de passe de la base,
   que tu gardes dans ton gestionnaire de mots de passe). Ne la colle **nulle part** ailleurs que
   dans ton terminal.
2. Dans le terminal, depuis ton dossier de sauvegardes :

   ```bash
   # Colle ta chaîne de connexion « Session pooler » entre les guillemets
   # (elle commence par postgresql:// et contient ton mot de passe : jamais dans un fichier)
   export DB_URL="COLLE_ICI_LA_CHAINE_DE_CONNEXION"
   DATE=$(date +%Y-%m-%d)
   npx supabase db dump --db-url "$DB_URL" -f "$DATE-roles.sql" --role-only
   npx supabase db dump --db-url "$DB_URL" -f "$DATE-schema.sql"
   npx supabase db dump --db-url "$DB_URL" -f "$DATE-data.sql" --use-copy --data-only
   unset DB_URL
   ```

   Sous Windows (PowerShell) : `$env:DB_URL = "…"` au lieu de `export`, et
   `$DATE = Get-Date -Format yyyy-MM-dd` au lieu de la ligne `DATE=…`.
3. Vérifier que les trois fichiers ne sont pas vides (le fichier `data` doit contenir des lignes
   `COPY public.recipes`).
4. **Chiffrer** les trois fichiers ensemble (par exemple une archive 7-Zip avec mot de passe, en
   AES-256) puis supprimer les `.sql` en clair. Ils contiennent des données personnelles : les
   adresses e-mail des comptes, les recettes et listes de la famille.
5. Garder l'archive à **deux endroits** (ton ordinateur + un disque externe ou un cloud personnel).
   Garder les 8 dernières, supprimer les plus anciennes.

## 3. Ce que la sauvegarde ne contient PAS

- **Les photos des recettes** (Storage). Supabase le précise : les sauvegardes de la base ne
  contiennent pas les fichiers du Storage, seulement leurs informations. Pour les photos :
  Supabase → Storage → bucket des photos → télécharger le dossier, de temps en temps.
- Les **réglages** du projet (Site URL, modèles d'e-mails, SMTP Brevo, fonction
  `accepter-invitation`) : ils sont décrits dans `supabase/prod/README.md` et `CLAUDE.md`.

## 4. Restaurer (en cas de problème)

Ne pas le faire seul la première fois : demande-moi. Le principe documenté par Supabase : sur un
projet **vide**, rejouer les trois fichiers dans l'ordre avec `psql` :

```bash
psql --single-transaction --variable ON_ERROR_STOP=1 \
  --file roles.sql --file schema.sql \
  --command 'SET session_replication_role = replica' \
  --file data.sql --dbname "$NOUVELLE_DB_URL"
```

Puis refaire les réglages du projet (section 3) et remettre les photos.

Sources : documentation Supabase « Database Backups » et « Backup and Restore using the CLI ».
