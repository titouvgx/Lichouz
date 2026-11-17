<script lang="ts">
  // Documents légaux (v2.0.0, lot C) : CGU, politique de confidentialité, stockage.
  // Pages publiques plein écran : lisibles sans être connecté et depuis la fenêtre
  // d'accueil. ⚠️ Changer le fond de ces textes = nouvelle version (src/lib/legal.ts).
  import Icon from '../components/Icon.svelte'
  import { navigate, href } from '../lib/router.svelte'
  import { auth } from '../lib/auth.svelte'
  import { TERMS_DATE_LABEL, CONTROLLER, PROCESSORS, RETENTION } from '../lib/legal'

  let { doc }: { doc: 'cgu' | 'confidentialite' | 'stockage' } = $props()

  const TITLES = {
    cgu: 'Conditions d’utilisation',
    confidentialite: 'Confidentialité',
    stockage: 'Stockage sur ton téléphone',
  } as const

  function back() {
    if (history.length > 1) history.back()
    else navigate(auth.user ? 'vie-privee' : 'login')
  }
</script>

<main class="legal">
  <div class="content">
    <button class="back" onclick={back}><Icon name="arrow-left" size={18} /> Retour</button>
    <header>
      <h1>{TITLES[doc]}</h1>
      <p class="version">Version du {TERMS_DATE_LABEL}</p>
    </header>

    <nav class="tabs" aria-label="Documents">
      <a href={href('cgu')} aria-current={doc === 'cgu' ? 'page' : undefined}>Conditions</a>
      <a href={href('confidentialite')} aria-current={doc === 'confidentialite' ? 'page' : undefined}>Confidentialité</a>
      <a href={href('stockage')} aria-current={doc === 'stockage' ? 'page' : undefined}>Stockage</a>
    </nav>

    {#if doc === 'cgu'}
      <section class="card">
        <h2>En bref</h2>
        <p>Lichouz est une appli <strong>familiale, privée et gratuite</strong>, sans publicité. On y entre seulement sur invitation. Tu y gardes tes recettes, tu prépares la semaine et la liste de courses avec ton foyer.</p>
      </section>

      <section class="card">
        <h2>1. Qui peut l’utiliser</h2>
        <p>Les personnes invitées par un membre de leur famille ou de leur foyer. À partir de 15 ans, tu peux accepter ces conditions toi-même. <strong>Avant 15 ans</strong>, il faut en plus l’accord d’un parent : il le donne depuis son propre compte, dans le même foyer (Mon compte → Vie privée). Il peut le retirer à tout moment.</p>
      </section>

      <section class="card">
        <h2>2. Ton compte et ton pseudo</h2>
        <ul>
          <li>Ton mot de passe est personnel : ne le donne à personne.</li>
          <li>Ton <strong>pseudo</strong> est unique. Il doit rester correct : pas d’insulte, pas de nom qui fait croire que tu es quelqu’un d’autre (ou l’équipe de l’appli). Tu peux le changer une fois tous les 30 jours.</li>
          <li>Ton prénom est visible par ton foyer (et par ta famille sur ce que tu partages).</li>
        </ul>
      </section>

      <section class="card">
        <h2>3. Ce que tu ajoutes</h2>
        <ul>
          <li>Tes recettes, photos, textes et commentaires restent à toi. En les ajoutant, tu permets aux personnes qui peuvent les voir (ton foyer, ou toute la famille si tu les partages) de les lire et de s’en servir dans l’appli.</li>
          <li>N’ajoute que ce que tu as le droit d’utiliser : pas de photo prise sur internet sans autorisation, pas de texte recopié mot pour mot d’un livre ou d’un site.</li>
          <li>Si tu supprimes ton compte, tes recettes restent dans ton foyer, sans ton nom.</li>
        </ul>
      </section>

      <section class="card">
        <h2>4. Bien vivre ensemble</h2>
        <p>Pas de contenu illégal, blessant ou gênant pour les autres, y compris dans les commentaires : ils sont lus par toute ta famille, enfants compris. Un admin de ton foyer peut supprimer un commentaire écrit dans son foyer, mettre un compte en pause ou le retirer.</p>
      </section>

      <section class="card">
        <h2>5. Le service</h2>
        <ul>
          <li>Lichouz est fait sur le temps libre de {CONTROLLER.name}, {CONTROLLER.role}. Il est fourni tel quel, sans garantie qu’il marche à tout moment.</li>
          <li>Il n’y a pas de sauvegarde automatique garantie : pour tes recettes importantes, garde une copie (Vie privée → Télécharger mes données).</li>
          <li>L’appli peut évoluer, ou s’arrêter : dans ce cas, tu seras prévenu à l’avance pour récupérer tes données.</li>
        </ul>
      </section>

      <section class="card">
        <h2>6. Changements et fin</h2>
        <p>Si ces conditions changent de façon importante, l’appli te les montre à la prochaine ouverture et te demande de les accepter. Tu peux arrêter quand tu veux : <strong>Mon compte → Supprimer mon compte</strong>.</p>
        <p>Ces conditions sont soumises au droit français. Une question : {CONTROLLER.contact}.</p>
      </section>
    {:else if doc === 'confidentialite'}
      <section class="card">
        <h2>En bref</h2>
        <ul>
          <li>On garde seulement ce qu’il faut pour que l’appli marche.</li>
          <li><strong>Aucune publicité, aucun traceur, aucune revente</strong>, aucun profil commercial.</li>
          <li>Tes données sont stockées dans l’Union européenne (Irlande).</li>
          <li>Tu peux les télécharger ou les effacer depuis l’appli.</li>
        </ul>
      </section>

      <section class="card">
        <h2>Qui est responsable</h2>
        <p>{CONTROLLER.name}, {CONTROLLER.role}. Contact : {CONTROLLER.contact}.</p>
      </section>

      <section class="card">
        <h2>Ce qui est gardé, et pourquoi</h2>
        <dl>
          <dt>Ton compte</dt>
          <dd>Adresse e-mail et mot de passe (gardé chiffré, personne ne peut le lire) : pour te connecter et te prévenir (confirmation d’adresse, mot de passe oublié).</dd>
          <dt>Ton profil</dt>
          <dd>Prénom, pseudo, foyer, rôle (admin ou membre) : pour que les tiens te reconnaissent.</dd>
          <dt>Ton âge (tranche seulement)</dt>
          <dd>18 ans ou plus, 15 à 17 ans, ou moins de 15 ans, avec la date d’acceptation des conditions et, avant 15 ans, l’accord du parent : c’est la preuve demandée par la loi.</dd>
          <dt>La vie du foyer</dt>
          <dd>Recettes, photos, planning, « qui cuisine », listes de courses (et qui a coché quoi), placard, événements et réponses, étoiles données aux recettes (ta note reste privée, seule la moyenne est visible), commentaires sur les recettes : c’est l’appli elle-même.</dd>
          <dt>Tes messages</dt>
          <dd>Les idées et retours que tu envoies.</dd>
          <dt>Le journal des erreurs</dt>
          <dd>Quand l’appli plante : la page, la version, le navigateur et un message nettoyé (sans e-mail ni mot de passe), pour réparer.</dd>
        </dl>
        <p>Pourquoi on a le droit : pour te fournir le service que tu as demandé en acceptant les conditions ; pour la sécurité et les erreurs, parce que l’appli doit pouvoir être réparée ; avant 15 ans, avec l’accord d’un parent.</p>
      </section>

      <section class="card">
        <h2>Qui voit quoi</h2>
        <ul>
          <li><strong>Ton foyer</strong> voit ton prénom, ton pseudo, et la vie du foyer.</li>
          <li><strong>Ta famille</strong> (les autres foyers) voit seulement ce que tu partages avec elle (recettes partagées, événements « famille ») et tes <strong>commentaires</strong> sur les recettes, avec ton prénom et ton pseudo. Personne en dehors de ta famille ne les voit, même sur les recettes du catalogue.</li>
          <li><strong>{CONTROLLER.name}</strong>, qui administre l’appli, peut techniquement accéder à la base. Il ne s’en sert que pour faire marcher et réparer l’appli (statistiques en nombres, journal des erreurs, retours).</li>
          <li>Personne d’autre, sauf les prestataires ci-dessous, pour l’hébergement.</li>
        </ul>
      </section>

      <section class="card">
        <h2>Prestataires</h2>
        <ul>
          {#each PROCESSORS as p (p.name)}
            <li><strong>{p.name}</strong> : {p.what}. Lieu : {p.where}.</li>
          {/each}
        </ul>
      </section>

      <section class="card">
        <h2>Combien de temps</h2>
        <ul>
          {#each RETENTION as r (r.what)}
            <li><strong>{r.what}</strong> : {r.how}.</li>
          {/each}
        </ul>
        <p>Le ménage se fait tout seul, chaque nuit.</p>
      </section>

      <section class="card">
        <h2>Tes droits</h2>
        <ul>
          <li><strong>Voir et récupérer</strong> tes données : Vie privée → Télécharger mes données.</li>
          <li><strong>Corriger</strong> : ton prénom et ton pseudo dans Mon compte ; tes recettes dans Mes recettes.</li>
          <li><strong>Effacer</strong> : Mon compte → Supprimer mon compte.</li>
          <li><strong>Retirer un accord parental</strong> : le parent, depuis Vie privée.</li>
          <li>Pour t’opposer à un usage ou poser une question : {CONTROLLER.contact}.</li>
          <li>Si tu n’es pas satisfait, tu peux te plaindre à la CNIL (cnil.fr).</li>
        </ul>
      </section>

      <section class="card">
        <h2>Sécurité</h2>
        <p>Connexion chiffrée, mots de passe jamais lisibles, et des règles dans la base qui empêchent un foyer de lire les données d’un autre (vérifiées par plus de mille tests automatiques à chaque version).</p>
      </section>
    {:else}
      <section class="card">
        <h2>En bref</h2>
        <p>Lichouz ne dépose <strong>aucun cookie de publicité ou de mesure d’audience</strong>. Il garde seulement sur ton téléphone ce qui sert à te connecter, à marcher sans réseau et à retenir tes réglages. C’est pour ça qu’il n’y a pas de bandeau « cookies » : la loi n’en demande pas pour ce stockage-là.</p>
      </section>

      <section class="card">
        <h2>Ce qui est gardé sur ce téléphone</h2>
        <dl>
          <dt>Ta connexion</dt>
          <dd>Le jeton de session Supabase, pour ne pas te redemander ton mot de passe à chaque ouverture.</dd>
          <dt>L’appli hors connexion</dt>
          <dd>Les fichiers de l’appli et les photos déjà vues (cache du navigateur), la dernière liste de courses, ton profil et tes cochages en attente de réseau.</dd>
          <dt>Tes réglages</dt>
          <dd>Le thème choisi, les filtres de recettes (effacés en fermant l’appli), « écran de bienvenue vu », « nouveautés vues », « conditions acceptées ».</dd>
          <dt>Les boosters</dt>
          <dd>Le jour où tu as ouvert chaque booster et les recettes tirées ce jour-là, pour retrouver les mêmes cartes jusqu’à minuit (remplacées le lendemain).</dd>
          <dt>Sécurité</dt>
          <dd>Un repère pendant un changement de mot de passe, effacé ensuite.</dd>
        </dl>
      </section>

      <section class="card">
        <h2>Tout effacer</h2>
        <p>Se déconnecter efface ta session, ton profil, la liste et les cochages gardés sur le téléphone ; seuls tes réglages restent (thème, écrans déjà vus). Tu peux aussi vider la liste sans te déconnecter : Mon compte → Ce téléphone. Pour tout effacer, efface les données du site dans les réglages de ton navigateur. Rien de tout ça n’est envoyé ailleurs ni utilisé pour te suivre.</p>
      </section>
    {/if}
  </div>
</main>

<style>
  .legal {
    min-height: 100dvh;
    display: flex;
    justify-content: center;
    padding: calc(var(--sp-4) + env(safe-area-inset-top, 0px)) var(--gutter) calc(var(--sp-6) + env(safe-area-inset-bottom, 0px));
  }
  .content {
    width: 100%;
    max-width: 640px;
    display: grid;
    gap: var(--sp-4);
    align-content: start;
  }
  .back {
    justify-self: start;
    min-height: 44px;
    display: inline-flex;
    align-items: center;
    gap: var(--sp-2);
    padding: 0 var(--sp-3);
    background: var(--surface);
    border: var(--line-w) solid var(--line);
    box-shadow: var(--shadow-sm);
    color: var(--text);
    font: inherit;
    font-weight: var(--fw-bold);
    cursor: pointer;
    touch-action: manipulation;
  }
  .back:active { transform: translate(2px, 2px); box-shadow: none; }
  h1 { font-size: var(--fs-2xl); line-height: 1.05; }
  .version { color: var(--text-secondary); font-size: var(--fs-sm); margin-top: var(--sp-1); }
  .tabs { display: flex; flex-wrap: wrap; gap: var(--sp-2); }
  .tabs a {
    min-height: 44px;
    display: inline-flex;
    align-items: center;
    padding: 0 var(--sp-3);
    border: var(--line-w) solid var(--line);
    background: var(--surface);
    color: var(--text);
    font-weight: var(--fw-bold);
    font-size: var(--fs-sm);
    text-decoration: none;
  }
  .tabs a[aria-current='page'] { background: var(--accent); color: var(--on-accent); box-shadow: var(--shadow-sm); }
  section { padding: var(--sp-4); display: grid; gap: var(--sp-3); line-height: 1.5; }
  h2 { font-size: var(--fs-lg); }
  ul { margin: 0; padding-left: 20px; display: grid; gap: var(--sp-2); }
  dl { margin: 0; display: grid; gap: var(--sp-1); }
  dt { font-weight: var(--fw-bold); margin-top: var(--sp-2); }
  dt:first-child { margin-top: 0; }
  dd { margin: 0; color: var(--text-secondary); }
  p { color: var(--text); }

  @media (hover: hover) and (pointer: fine) {
    .back:hover, .tabs a:hover { background: var(--highlight); }
  }
</style>
