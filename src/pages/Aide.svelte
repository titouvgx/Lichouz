<script lang="ts">
  // Aide : à quoi sert Lichouz et comment s'en servir, onglet par onglet,
  // + « Ma famille » expliqué selon le rôle de la personne, + FAQ.
  // Sections dépliables (<details>) : lisibles au clavier et au lecteur d'écran.
  import Icon from '../components/Icon.svelte'
  import type { IconName } from '../components/Icon.svelte'
  import { profileState } from '../lib/profile.svelte'
  import { href } from '../lib/router.svelte'

  const ctx = $derived(profileState.context)
  const myRole = $derived(
    ctx?.isSuperAdmin ? 'super-admin'
      : ctx?.isFounder ? 'fondateur'
      : profileState.profile?.role === 'admin' ? 'admin'
      : 'membre',
  )

  interface Section { id: string; icon: IconName; title: string }
  const sections: Section[] = [
    { id: 'accueil', icon: 'home', title: 'Accueil' },
    { id: 'recettes', icon: 'book', title: 'Recettes' },
    { id: 'semaine', icon: 'calendar', title: 'Semaine' },
    { id: 'courses', icon: 'cart', title: 'Courses' },
    { id: 'tendances', icon: 'star', title: 'Tendances' },
    { id: 'historique', icon: 'archive', title: 'Listes passées' },
    { id: 'frigo', icon: 'chef', title: 'Qu’est-ce qu’on mange ?' },
    { id: 'trophees', icon: 'star', title: 'Trophées et niveau' },
    { id: 'famille', icon: 'users', title: 'Mon foyer, ma famille et les rôles' },
    { id: 'telephone', icon: 'settings', title: 'Sur ton téléphone' },
  ]
</script>

<div class="page">
  <header class="head">
    <h1>Aide</h1>
    <p class="head-sub">Lichouz en quelques minutes.</p>
  </header>

  <section class="card intro" aria-labelledby="intro-title">
    <h2 id="intro-title" class="section-title">Lichouz, c’est quoi ?</h2>
    <p>
      L’appli des repas et des courses de la maison. Tout ce que tu fais est visible
      tout de suite par les autres membres de ton <strong>foyer</strong> (les personnes qui vivent avec toi), et seulement par eux.
      Les foyers d’une même <strong>famille</strong> (ex. famille Martin) peuvent en plus partager des recettes et des événements.
    </p>
    <ol class="cycle">
      <li><strong>Recettes</strong> : on garde nos recettes et on pioche dans le catalogue.</li>
      <li><strong>Semaine</strong> : on place les recettes sur les repas de la semaine.</li>
      <li><strong>Courses</strong> : la liste se calcule depuis la semaine ; on coche ensemble, en direct.</li>
      <li><strong>Tendances</strong> : les recettes les mieux notées, les plus cuisinées du mois et les nouvelles.</li>
    </ol>
  </section>

  <div class="sections">
    {#each sections as s, i (s.id)}
      <details class="card fold" id={`aide-${s.id}`} style="--i: {Math.min(i, 8)}">
        <summary>
          <span class="section-icon"><Icon name={s.icon} size={18} /></span>
          <span class="fold-title">{s.title}</span>
          <span class="chev"><Icon name="chevron-down" size={18} /></span>
        </summary>
        <div class="fold-body">
          {#if s.id === 'accueil'}
            <p>Chaque jour, un <strong>booster</strong> de 5 recettes à ouvrir (une fois par jour) : touche le paquet, les cartes en sortent. « Passer » les montre directement. Touche une carte pour voir la recette, ou son calendrier pour la mettre dans ta semaine.</p>
            <p>Le tirage est le même pour tout ton foyer ; il évite ce que vous avez cuisiné ces 2 dernières semaines ou déjà prévu, et favorise les recettes les mieux notées.</p>
            <p>Une fois le booster du jour ouvert, le lien <strong>+ Boosters à thème</strong> (en bas de l’accueil) propose des petits paquets en plus : Express, Petit budget, Tour du monde, Tout vert, Réconfort, Les petits (et Les fêtes en décembre). Chacun s’ouvre une fois par jour.</p>
            <p>Si un repas est prévu aujourd’hui, l’accueil l’affiche (« Ce soir : … ») avec la personne qui cuisine.</p>
          {:else if s.id === 'recettes'}
            <ul>
              <li><strong>Chercher</strong> : tape quelques lettres, peu importe les accents et l’ordre des mots ; filtre par catégorie. La recherche trouve aussi les étiquettes (« vegan », « Bretagne »…).</li>
              <li><strong>Filtres</strong> : à côté de la recherche, trie par régime (toutes les cases cochées), budget (au plus), temps de préparation (au plus), thème (au moins un) ou origine. Touche une étiquette sous la recherche pour la retirer. Sur une fiche, touche une étiquette (« Vegan », « Bretagne »…) pour voir toutes les recettes qui l’ont.</li>
              <li><strong>Étiquettes</strong> : dans le formulaire d’une recette (régime, origine, budget, jusqu’à 5 thèmes). Qui peut modifier la recette peut changer ses étiquettes ; une recette partagée a les mêmes étiquettes pour toutes les familles. Les régimes sont <strong>indicatifs</strong> : en cas d’allergie, vérifie toujours les emballages.</li>
              <li><strong>Ajouter une recette</strong> : bouton « + », avec ingrédients, étapes et photo prise depuis la galerie. (« Importer depuis un lien » arrive bientôt.)</li>
              <li><strong>Qui la voit ?</strong> « Mon foyer seulement » (par défaut), ou « Toute la famille » pour la partager avec les autres foyers de ta famille. Les recettes du <strong>catalogue commun</strong> sont fournies avec l’appli : on peut les utiliser, pas les modifier.</li>
              <li><strong>Commentaires</strong> : en bas de chaque fiche recette. Ils sont lus par <strong>ta famille seulement</strong> (tous ses foyers), même sur les recettes du catalogue. Tu peux supprimer les tiens ; un admin du foyer peut supprimer ceux de son foyer. 500 caractères au plus.</li>
              <li><strong>Mes recettes</strong> (dans <a href={href('mes-recettes')}>Mon compte</a>) : les recettes que tu as créées, pour les modifier, les partager avec toute la famille ou les garder pour ton foyer, et les archiver.</li>
              <li><strong>Publier en public</strong> : dans Mon compte → Mes recettes, « Publier en public » envoie ta recette à l’administrateur, qui la lit avant de la rendre visible de tous (réponse en général sous 24 h, 3 demandes en attente au plus). Si elle est refusée, tu vois le motif. Tu peux retirer ta demande ou dépublier à tout moment (les copies déjà faites restent). Si tu modifies une recette publique, elle repart en validation. « Mon foyer » et « Toute la famille » n’ont aucune validation.</li>
              <li><strong>Archiver</strong> (admin du foyer) : la recette disparaît des listes et de la recherche, mais reste dans les plannings et l’historique. « Recettes archivées », en bas de la page Recettes, permet de la retrouver et de la <strong>restaurer</strong>.</li>
              <li><strong>En cuisine</strong> : une étape à la fois, en très gros, écran gardé allumé. Quand une étape parle d’une durée (« cuire 25 min »), le bouton <strong>Minuteur</strong> lance un compte à rebours qui sonne (et vibre sur Android). Garde le mode En cuisine ouvert : le fermer arrête les minuteurs.</li>
              <li>Limites : titre de 120 caractères, 60 ingrédients, 40 étapes de 1 000 caractères chacune.</li>
              <li>Depuis une recette : <strong>Ajouter à ma semaine</strong>, ou <strong>Juste les ingrédients</strong> pour les mettre dans la liste sans la planifier. Oublié de noter un repas ? « Jours déjà passés » permet de remplir les jours précédents de la semaine en cours.</li>
            </ul>
          {:else if s.id === 'semaine'}
            <ul>
              <li>Chaque jour a un repas du midi et du soir : touche un repas pour choisir la recette.</li>
              <li><strong>Entrée, plat, dessert</strong> : sous un repas, « + Entrée » ou « + Dessert » ajoute un autre plat au même repas. Depuis une recette, une entrée ou un dessert se range tout seul à sa place.</li>
              <li><strong>Restes</strong> : en choisissant un repas, « Utiliser des restes » reprend un repas cuisiné plus tôt. La liste de courses compte les deux : tu achètes de quoi cuisiner une seule fois en plus grande quantité. Supprimer le repas cuisiné supprime aussi ses restes.</li>
              <li><strong>Recopier, semaines types</strong> : recopie la semaine d’avant, enregistre une semaine qui revient souvent (20 au plus) et applique-la sur une autre. Coche « Remplacer » pour vider d’abord la semaine ; sinon seules les cases vides sont remplies.</li>
              <li><strong>Qui cuisine ?</strong> : la pastille sur un repas ; le filtre <strong>Mes repas</strong> ne montre que les tiens.</li>
              <li>Flèches en haut : semaine précédente ou suivante. Les changements apparaissent chez les autres en direct.</li>
            </ul>
          {:else if s.id === 'courses'}
            <ul>
              <li><strong>Mettre à jour depuis le planning</strong> recalcule la liste en additionnant les ingrédients ; ce qui est déjà coché et ce que tu as ajouté à la main sont gardés. Sans ce bouton, la liste ne change pas, même si une recette est modifiée.</li>
              <li>Sous chaque article : <strong>les recettes qui en ont besoin</strong>. Ce qui se compte à la pièce est arrondi au-dessus (pas de « 1,5 œuf »).</li>
              <li><strong>Partager la liste</strong> : envoie ce qui reste à prendre, par rayon, dans WhatsApp, un SMS ou une note.</li>
              <li>Touche un article pour le mettre dans le chariot : tout le monde le voit coché aussitôt. Ça marche aussi sans réseau (envoyé au retour du réseau).</li>
              <li><strong>Ajouter un article</strong> hors recette (« papier toilette »…).</li>
              <li><strong>Habituels</strong> : ce que tu achètes souvent, ajouté en un geste.</li>
              <li><strong>Placard</strong> : ce que tu as toujours à la maison (sel, huile…) ; ces articles vont dans « Sûrement déjà à la maison ». S’il en manque, touche « Il en manque ».</li>
              <li>À la fin : <strong>Terminer les courses</strong> range la liste dans les <strong>Listes passées</strong> (bouton en haut de Courses).</li>
            </ul>
          {:else if s.id === 'tendances'}
            <ul>
              <li><strong>Les mieux notées</strong> : Top 25 ou Top 50 des recettes que tu peux voir, classées par moyenne des étoiles (à égalité : celle qui a le plus de votes passe devant).</li>
              <li><strong>Chez nous ce mois-ci</strong> : les recettes de la Semaine de ton foyer dont le jour est passé (les restes ne comptent pas).</li>
              <li><strong>Nouvelles recettes</strong> : ajoutées ces 30 derniers jours par ton foyer ou ta famille.</li>
            </ul>
          {:else if s.id === 'historique'}
            <p>Les listes de courses terminées, pour retrouver ce qu’on a acheté et quand. On y va depuis Courses → <strong>Listes passées</strong>.</p>
          {:else if s.id === 'frigo'}
            <p>
              Depuis l’accueil : tape ce qu’il te reste (« courgettes, œufs… »), Lichouz classe les recettes qui
              l’utilisent le mieux (le placard est compté comme disponible). Le calcul se fait dans ton téléphone.
            </p>
          {:else if s.id === 'trophees'}
            <ul>
              <li><strong>40 trophées</strong> dans Mon compte → <a href={href('succes')}>Mes trophées</a> : 19 <strong>évolutifs</strong> (Bronze, Argent, Or, avec une barre de progression) et 21 <strong>secrets</strong> (on découvre ce qu’il fallait faire une fois obtenus).</li>
              <li>Un trophée obtenu s’affiche en haut de l’écran. Chaque trophée rapporte des points selon sa rareté (Commun 10, Rare 25, Épique 50, Légendaire 100) ; les points font monter ton <strong>niveau</strong>.</li>
              <li>Tout est calculé par Lichouz avec ce que tu fais : un repas compte comme cuisiné quand son jour est passé et que « Qui cuisine ? » c’est toi. Le temps en mode « En cuisine » compte aussi (4 h max par séance).</li>
              <li>Tes trophées ne sont visibles que par toi.</li>
            </ul>
          {:else if s.id === 'famille'}
            <p class="you">Ton rôle : <strong>{myRole}</strong>{ctx?.family ? ` · foyer « ${ctx.family.name} »` : ''}</p>
            <ul>
              <li><strong>Membre</strong> : utilise tout (recettes, semaine, courses) et voit la liste du foyer.</li>
              <li><strong>Admin</strong> : en plus, invite des personnes avec un lien, passe quelqu’un admin ou membre, renomme le foyer, peut <strong>désactiver</strong> un compte (la personne ne voit plus rien mais garde tout ; on peut la réactiver) ou retirer quelqu’un (son compte est supprimé).</li>
              <li><strong>Fondateur</strong> : a créé la famille ; il peut y créer jusqu’à 3 foyers et gérer chacun (membres, invitations, suppression d’un foyer vide).</li>
            </ul>
            <p>
              <strong>Inviter</strong> : dans <a href={href('famille')}>Mon foyer</a>, crée un lien et envoie-le
              (SMS, WhatsApp…). Il sert <strong>une seule fois</strong> et expire au bout de <strong>7 jours</strong>.
              Tu peux aussi indiquer l’<strong>adresse e-mail</strong> de la personne (facultatif) : seule cette adresse
              pourra alors créer le compte, même si le lien circule.
            </p>
            <p>
              <strong>Retirer quelqu’un</strong> supprime son compte : il ne peut plus se connecter, ses recettes
              restent dans le foyer. On peut le réinviter plus tard avec un nouveau lien.
            </p>
          {:else if s.id === 'telephone'}
            <ul>
              <li><strong>Installer l’appli</strong> : sur iPhone, dans Safari, bouton Partager puis « Sur l’écran d’accueil ». Sur Android, dans Chrome, menu ⋮ puis « Installer l’application » (ou « Ajouter à l’écran d’accueil »).</li>
              <li>L’appli se met à jour toute seule : elle se recharge quand une nouvelle version sort.</li>
              <li>Sans réseau, la dernière liste de courses reste consultable et les cochages sont envoyés plus tard.</li>
            </ul>
          {/if}
        </div>
      </details>
    {/each}
  </div>

  <section class="card faq" aria-labelledby="faq-title">
    <h2 id="faq-title" class="section-title">Questions fréquentes</h2>
    <dl>
      <dt>J’ai oublié mon mot de passe.</dt>
      <dd>Sur l’écran de connexion, « Mot de passe oublié ? » : tu reçois un e-mail pour en choisir un nouveau. Une fois enregistré, tu es déconnecté de tous tes appareils : reconnecte-toi avec le nouveau mot de passe.</dd>
      <dt>À quoi sert le pseudo ? Comment le changer ?</dt>
      <dd>C’est ton nom unique dans toute l’appli (il servira au quiz et aux classements). Tu le choisis à la première ouverture ; ensuite <a href={href('vie-privee')}>Vie privée</a> → Mon pseudo, une fois tous les 30 jours (les majuscules, quand tu veux).</dd>
      <dt>Que fait Lichouz de mes données ? Comment les récupérer ?</dt>
      <dd>Pas de publicité, pas de traceur, pas de revente ; les données sont en Europe. Tout est expliqué dans <a href={href('confidentialite')}>Confidentialité</a>. <a href={href('vie-privee')}>Vie privée</a> → « Télécharger mes données » te donne un fichier avec tout ce qui te concerne.</dd>
      <dt>Mon enfant a moins de 15 ans : que faut-il faire ?</dt>
      <dd>À sa première ouverture, il indique son âge, puis attend ton accord. Sur <strong>ton</strong> téléphone : <a href={href('vie-privee')}>Vie privée</a> → Accords parentaux → « Je donne mon accord ». Tu peux le retirer au même endroit. Il faut que tu sois dans le même foyer et que tu aies indiqué 18 ans ou plus.</dd>
      <dt>Qui voit mes étoiles ?</dt>
      <dd>Personne ne voit <strong>ta</strong> note : seulement toi. Tout le monde voit la <strong>moyenne</strong> et le nombre de votes des recettes qu’il peut lire (pour le catalogue, c’est toute l’appli). Touche à nouveau ta note pour la retirer.</dd>
      <dt>Comment inviter quelqu’un qui est à côté de moi ?</dt>
      <dd><a href={href('famille')}>Mon foyer</a> → Inviter → « Créer le lien », puis « Afficher en QR code » : la personne le scanne avec l’appareil photo de son téléphone. Le QR ne s’affiche qu’à ce moment-là ; réserve le lien à son adresse e-mail pour plus de sécurité.</dd>
      <dt>Foyer, famille : quelle différence ?</dt>
      <dd>Ton <strong>foyer</strong>, ce sont les personnes qui vivent avec toi : vous partagez le planning, la liste de courses et le placard. Ta <strong>famille</strong>, ce sont plusieurs foyers réunis (ex. famille Martin) : ils peuvent partager des recettes et des événements.</dd>
      <dt>Comment organiser Noël ou un anniversaire ?</dt>
      <dd><a href={href('evenements')}>Événements</a> (depuis l’Accueil ou Mon compte) → « Créer un événement » : choisis un modèle, la date, chez qui, et si toute la famille le voit ou seulement ton foyer. Chacun répond s’il vient et s’inscrit dans « Qui fait quoi ». Seuls l’auteur et les admins du foyer modifient ou suppriment l’événement.</dd>
      <dt>Comment changer les couleurs (thème de Noël) ?</dt>
      <dd><a href={href('compte')}>Mon compte</a> → Affichage : Automatique (Noël du 1er décembre au 6 janvier), Classique ou Noël. Le mode clair ou sombre suit ton téléphone ; le choix est gardé sur ce téléphone.</dd>
      <dt>Le lien d’invitation ne marche pas.</dt>
      <dd>
        Il a déjà servi, a été annulé ou a plus de 7 jours. Ou bien il est réservé à une autre adresse e-mail : la page
        l’indique (« réservé à m•••@… »), utilise celle-là. Sinon, demande un nouveau lien à l’admin de ton foyer.
      </dd>
      <dt>Je ne vois pas une recette qu’un proche a créée.</dt>
      <dd>Elle est sans doute réservée à son foyer. Il peut la passer en « Toute la famille » si vos foyers sont dans la même famille.</dd>
      <dt>La liste ne bouge plus chez moi.</dt>
      <dd>Vérifie le réseau, puis ferme et rouvre l’appli : tout se resynchronise.</dd>
      <dt>Je n’arrive pas à me connecter juste après avoir créé mon compte.</dt>
      <dd>
        Il faut d’abord confirmer ton adresse : ouvre le lien de l’e-mail « Confirme ton adresse pour Lichouz »
        (regarde aussi dans les spams). Le lien est valable 1 heure. Rien reçu ou lien expiré ? Essaie de te
        connecter : l’appli te propose « Renvoyer l’e-mail de confirmation ».
      </dd>
      <dt>Je veux supprimer mon compte.</dt>
      <dd>
        Tout en bas de <a href={href('compte')}>Mon compte</a> : « Supprimer mon compte », puis tape SUPPRIMER
        et ton mot de passe. C’est définitif. Tes recettes restent dans ton foyer, sans ton nom. Si tu es le
        dernier admin d’un foyer qui a d’autres membres, nomme d’abord un autre admin ; un fondateur doit d’abord
        demander au super-admin de transmettre son rôle.
      </dd>
      <dt>J’ai une idée, ou j’ai trouvé un bug.</dt>
      <dd>
        <a href={href('avis')}>Mon compte → Idées et retours</a> : écris-le, Titouan le lit (10 envois par jour au
        maximum). Ce qui a changé récemment est dans <a href={href('nouveautes')}>Mon compte → Nouveautés</a>.
      </dd>
      <dt>Qui voit mes données ?</dt>
      <dd>
        Seulement les membres de ton foyer (et les autres foyers de ta famille pour ce que tu partages). Ton e-mail n’est montré
        à personne. Si l’appli plante, l’erreur est envoyée à Titouan avec ton prénom, la page, la version de l’appli et le type de
        navigateur, mais sans e-mail ni contenu de tes recettes ; elle est effacée après 90 jours. Tes idées et retours, eux, ne sont
        lus que par Titouan. Supprimer ton compte efface aussi tes retours et ces erreurs.
      </dd>
    </dl>
  </section>

  <p class="back"><a href={href('compte')}><Icon name="arrow-left" size={16} /> Retour à Mon compte</a></p>
</div>

<style>
  /* Même mise en page que « Mon compte » */
  .page {
    padding: var(--gutter);
    padding-top: calc(var(--gutter) + env(safe-area-inset-top, 0px));
    max-width: 560px;
    margin: 0 auto;
    padding-bottom: calc(84px + env(safe-area-inset-bottom, 0px));
    display: flex;
    flex-direction: column;
    gap: var(--sp-4);
  }
  @media (min-width: 900px) {
    .page { padding-top: calc(32px + env(safe-area-inset-top, 0px)); }
  }
  .head h1 { padding-right: 56px; }
  .head-sub { margin-top: var(--sp-1); font-size: 15px; font-weight: var(--fw-medium); color: var(--text-secondary); }

  .card { padding: var(--sp-4); }
  .section-title {
    font-size: var(--fs-lg);
    text-transform: uppercase;
    margin-bottom: var(--sp-2);
  }
  .intro p, .fold-body p, .faq dd { font-size: 15px; line-height: 1.5; color: var(--text-secondary); }
  .intro strong, .fold-body strong { color: var(--text); }
  .cycle { margin: var(--sp-3) 0 0; padding-left: 20px; display: grid; gap: 6px; font-size: 15px; line-height: 1.45; color: var(--text-secondary); }
  .cycle li::marker { font-weight: var(--fw-bold); color: var(--text); }

  .sections { display: grid; gap: var(--sp-3); }
  .fold { padding: 0; animation: fade-up var(--dur-sheet) var(--ease-out) calc(var(--i, 0) * 45ms) backwards; }
  .fold summary {
    display: flex;
    align-items: center;
    gap: var(--sp-3);
    min-height: 56px;
    padding: 8px var(--sp-3);
    cursor: pointer;
    list-style: none;
    touch-action: manipulation;
  }
  .fold summary::-webkit-details-marker { display: none; }
  .fold summary:focus-visible { outline: 3px solid var(--accent); outline-offset: -3px; }
  .fold-title { flex: 1; font-weight: var(--fw-bold); }
  .chev { display: inline-flex; color: var(--text); transition: transform var(--dur-base) var(--ease-out); }
  .fold[open] .chev { transform: rotate(180deg); }
  .fold[open] summary { background: var(--highlight); border-bottom: var(--line-w) solid var(--line); }
  .fold-body { padding: var(--sp-4) var(--sp-4) var(--sp-4) 60px; display: grid; gap: 10px; }
  .fold-body ul { margin: 0; padding-left: 18px; display: grid; gap: 8px; font-size: 15px; line-height: 1.5; color: var(--text-secondary); }
  .fold-body a, .faq a, .back a {
    color: var(--text);
    font-weight: var(--fw-bold);
    text-decoration: underline;
    text-decoration-thickness: 2px;
    text-underline-offset: 3px;
  }
  .you { padding: var(--sp-2) var(--sp-3); background: var(--highlight); border: var(--line-w) solid var(--line); color: var(--text); }
  .you strong { color: var(--text); }

  /* Icône dans un petit carré bordé */
  .section-icon {
    width: 34px;
    height: 34px;
    display: inline-flex;
    align-items: center;
    justify-content: center;
    border: var(--line-w) solid var(--line);
    background: var(--surface);
    color: var(--text);
    flex-shrink: 0;
  }

  .faq dl { margin: 0; display: grid; gap: 4px; }
  .faq dt { font-weight: var(--fw-bold); margin-top: var(--sp-3); }
  .faq dt:first-child { margin-top: 0; }
  .faq dd { margin: 0; }

  .back { text-align: center; padding: var(--sp-2) 0 var(--sp-1); }
  .back a { display: inline-flex; align-items: center; gap: 6px; min-height: 44px; }
</style>
