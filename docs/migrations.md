# Migrations — détail

Déplacé de `CLAUDE.md` le 17/11/2026. Fichiers dans `supabase/migrations/` (dans l'ordre), contrôles dans `supabase/tests/controle_NN_*.sql`.

- 1 schema
- 2 rls_functions
- 3 rls_policies
- 4 seed_categories
- 5 shopping_categories_icon
- 6 known_ingredients
- 7 seed_recipes (⚠️ échoue sans 1 compte + 1 famille)
- 8 shared_recipes
- 9 recipe_images
- 10 realtime_publication
- 11 recipe_photos_storage
- 12 security_fixes
- 13 household
- 14 more_ingredients
- 15 photo_paths (`image_url` = chemin `<recette>/<uuid>.webp|jpg` de notre bucket ou Unsplash ; fichier vérifié)
- 16 recettes_v1 (**GÉNÉRÉE** par `npm run recettes`)
- 17 familles_invitations
- 18 recettes_photos (**GÉNÉRÉE**, depuis `supabase/recettes/photos.json`)
- 19 admin_famille (retirer un membre, supprimer une famille vide, gardes)
- 20 admin_stats (statistiques super-admin, uniquement des nombres)
- 21 supprimer_mon_compte (`delete_my_account`, contrôle : `supabase/tests/controle_21_supprimer_mon_compte.sql`)
- 22 archives_limites_liste (v1.4.0 : `recipes.archived_at` + plus de DELETE direct sur recipes ; limites de texte par CHECK + 60 ingrédients / 40 étapes par trigger ; `shopping_list_items.source_recipe_ids` ; `replace_planned_items` SECURITY INVOKER = recalcul de liste en une transaction ; contrôle : `supabase/tests/controle_22_archives_limites_liste.sql`)
- 23 journal_retours (v1.6.0 : tables `app_errors` (journal des erreurs, écrit par soi-même, lu par le super-admin, 30/h, 90 jours) et `feedback` (idées et retours, 10/24 h, statut seul modifiable) ; auteur et famille forcés par la base ; supprimées avec le compte ; contrôle : `supabase/tests/controle_23_journal_retours.sql`)
- 24 invitation_email (v1.7.0 : `invitations.email_hash` + `email_hint`, `create_invitation(…, p_email)` (ancienne signature à 4 arguments supprimée), `invitation_info` renvoie `email_hint`, `consume_invitation` compare l'adresse de `auth.users` ; « coché par » = soi-même en modification ; photos orphelines réservées à leur auteur ; contrôle : `supabase/tests/controle_24_invitation_email.sql`)
- 25 etiquettes (v1.8.0 : `recipes.diets`/`origin`/`themes`/`budget`, **liste fixe** par CHECK (`tags_in_list`, exécutable par tous car appelée par la contrainte), même liste dans `src/lib/etiquettes.ts` (test qui compare) ; 4 types de plat en plus) + 25 bis recettes_etiquettes (**GÉNÉRÉE** depuis `supabase/recettes/etiquettes.json`, ne remplit que les champs vides du catalogue) ; contrôle : `supabase/tests/controle_25_etiquettes.sql`
- 26 planning_plus (v1.99.0 : `meal_slots.course` entree/plat/dessert, unicité jour × repas × plat ; `meal_slots.leftover_of` = restes (même recette, même foyer, plus tard, pas de chaîne, cascade) ; tables `week_templates` + `week_template_slots` (RLS foyer, 20 par famille, auteur forcé) ; `fill_plan_slots` / `copy_week_slots` / `save_week_template` / `apply_week_template` SECURITY INVOKER ; contrôle : `supabase/tests/controle_26_planning_plus.sql`)
- 27 comptes_desactives (v1.99.0 : `private.disabled_accounts` (jamais exposé) ; `user_family_id`, `is_family`, `is_member`, `is_admin`, `my_super_family_id` ignorent un compte désactivé ; politique `profiles_select_self` ; `set_account_disabled` (mêmes droits que `remove_member`), `disabled_members`, `my_account_disabled` ; contrôle : `supabase/tests/controle_27_comptes_desactives.sql`)
- 28 evenements (v1.999.0 : tables `events` (scope `foyer`|`famille`), `event_tasks` (`volunteers uuid[]`, chacun ne s'inscrit / se retire que lui-même, trigger `guard_event_task`), `event_rsvps` (oui / peut_etre / non, une par personne) ; `can_see_event`, `can_edit_event` (auteur ou admin du foyer), `event_people` (prénoms des seules personnes de l'événement), `toggle_event_volunteer` (SECURITY INVOKER, atomique) ; 30 événements par foyer, 30 tâches par événement ; contrôle : `supabase/tests/controle_28_evenements.sql`)
- 29 conformite (v2.0.0 : `profiles.pseudo` unique sans majuscules (index `lower`), format + noms réservés par CHECK `pseudo_is_valid` (même liste dans `src/lib/pseudo.ts`, test qui compare), trigger `guard_profile_pseudo` (soi-même, 30 jours, pas d'effacement) ; table `terms_acceptances` (preuve par version, aucune règle UPDATE/DELETE, version forcée = `current_terms_version()` = `TERMS_VERSION` de `src/lib/legal.ts`) ; `accept_terms` (INVOKER : pseudo + acceptation), moins de 15 ans → `parental_consents` / `confirm_parental_consent` / `revoke_parental_consent` (adulte du même foyer) ; `export_my_data` ; `purge_expired_data` (réservée à postgres) lancée par **pg_cron** `lichouz-purge` à 03:17 UTC ; contrôle : `supabase/tests/controle_29_conformite.sql`)
- 30 etoiles (v2.2.0 : table `recipe_ratings`, votes privés (chacun ne voit que le sien), moyenne via `recipe_rating_stats(uuid[])` (recettes lisibles seulement), inclus dans `export_my_data` ; contrôle : `supabase/tests/controle_30_etoiles.sql`)
- 31 commentaires (v2.6.0 : table `recipe_comments` visible dans la famille de l'auteur seulement (`super_family_id` forcé) et par ceux qui lisent la recette ; insertion soi-même, 500 caractères, 30/h ; suppression par l'auteur ou un admin de son foyer ; pas de modification ; `recipe_comments_list(uuid)` (prénom, pseudo, droits) ; export `commentaires_ecrits` ; **`current_terms_version()` = 2026-11-18** → ré-acceptation ; contrôle : `supabase/tests/controle_31_commentaires.sql`)

## État des bases — détail historique

**État des bases** (à tenir à jour) : migrations 26 et 27 (v1.99.0) exécutées le 16/11/2026 sur `courses-test` puis `lichouz-prod` par le connecteur Supabase avec l'accord de Titouan, contrôles 26 et 27 tout à true sur les deux bases (prod : 17 repas existants devenus « plat ») ; ⚠️ toujours aucun export de sauvegarde de la prod
- `courses-test` : 1 à 25 bis appliquées (20 et 21 constatées présentes le 15/11/2026 ; 22 le 15/11/2026 ; 23, 24, 25 et 25 bis le 16/11/2026 ; contrôles tout à true) ; 1 à 19 vérifiées le 14/11/2026 (513 ingrédients, 50 catalogue dont 49 avec photo, 0 table sans RLS ; contrôle 19 : `supabase/tests/controle_19_admin_famille.sql`, tout à true) ; fonction `accepter-invitation` redéployée (adresse `/accepter-invitation`, Verify JWT désactivé), invitation testée OK
- `lichouz-prod` : créée le 15/11/2026, migrations 1 à 19 via `npm run prod:sql` + migration 20 (admin_stats) exécutée le 15/11/2026 avant la v1.1.0, contrôle 1/1/50/0 OK ; migrations 21 (v1.2.0), 22 (v1.4.0, contrôle tout à true le 15/11/2026) et 23 (v1.6.0), 24 (v1.7.0), 25 et 25 bis (v1.8.0), contrôles tout à true le 16/11/2026, par le connecteur Supabase avec l'accord de l'utilisateur ; Site URL `/Lichouz/` ; fonction `accepter-invitation` OK (invitation d'un compte de test réussie en prod le 15/11/2026) ; variables GitHub branchées sur la prod → le site public utilise la prod depuis la v1.0.0. `courses-test` : essais seulement (se met en pause après 7 jours)
