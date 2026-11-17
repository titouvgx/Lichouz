<script lang="ts">
  import type { CatMood } from '../lib/errorMood'
  // Chat de Lichouz (v2.1.0) : personnage ORIGINAL, dessiné pour l'appli (trait épais
  // « Brutal beurre », couleurs du thème). Une situation de chat ordinaire par type d'erreur ;
  // ne copie aucun mème ni personnage existant. Purement décoratif (aria-hidden) :
  // le message clair est toujours écrit en dessous par ErrorState.
  let { mood, size = 220 }: { mood: CatMood; size?: number } = $props()
</script>

{#snippet sittingCat(x: number, y: number, s: number, look: number, eyes: 'open' | 'wide' | 'closed')}
  <!-- Chat assis, vu de face ; (x, y) = milieu du bas ; look = décalage du regard (-1 à 1) -->
  <g transform="translate({x} {y}) scale({s})">
    <path class="tail-outline" d="M28 -8 C62 -8 66 -46 44 -58" />
    <path class="tail" d="M28 -8 C62 -8 66 -46 44 -58" />
    <path class="fur" d="M-34 0 C-42 -40 -28 -70 0 -70 C28 -70 42 -40 34 0 Z" />
    <path class="belly" d="M-14 -4 C-18 -26 -12 -44 0 -44 C12 -44 18 -26 14 -4 Z" />
    <ellipse class="fur" cx="-15" cy="-2" rx="11" ry="7" />
    <ellipse class="fur" cx="15" cy="-2" rx="11" ry="7" />
    <path class="fur" d="M-31 -92 L-27 -128 L-6 -109 Z" />
    <path class="fur" d="M31 -92 L27 -128 L6 -109 Z" />
    <path class="inner" d="M-26 -101 L-24 -119 L-13 -109 Z" />
    <path class="inner" d="M26 -101 L24 -119 L13 -109 Z" />
    <ellipse class="fur" cx="0" cy="-84" rx="37" ry="30" />
    <path class="stripe" d="M-8 -112 L-6 -102 M0 -114 L0 -103 M8 -112 L6 -102" />
    {#if eyes === 'closed'}
      <path class="stroke" d="M-20 -86 Q-13 -80 -6 -86 M6 -86 Q13 -80 20 -86" />
    {:else if eyes === 'wide'}
      <circle class="eye-white" cx="-13" cy="-87" r="8" />
      <circle class="eye-white" cx="13" cy="-87" r="8" />
      <circle class="pupil" cx={-13 + look * 3} cy="-87" r="3.5" />
      <circle class="pupil" cx={13 + look * 3} cy="-87" r="3.5" />
    {:else}
      <ellipse class="pupil" cx={-13 + look * 3} cy="-86" rx="3.6" ry="5.6" />
      <ellipse class="pupil" cx={13 + look * 3} cy="-86" rx="3.6" ry="5.6" />
    {/if}
    <path class="nose" d="M-4 -77 L4 -77 L0 -72 Z" />
    <path class="stroke thin" d="M-7 -67 Q-3.5 -63 0 -68 Q3.5 -63 7 -67" />
    <path class="stroke thin" d="M-18 -74 L-42 -78 M-18 -70 L-41 -68 M18 -74 L42 -78 M18 -70 L41 -68" />
  </g>
{/snippet}

<svg
  class="cat"
  width={size}
  height={size * 0.75}
  viewBox="0 0 240 180"
  aria-hidden="true"
  fill="none"
  stroke-linejoin="round"
  stroke-linecap="round"
>
  <line class="floor" x1="8" y1="172" x2="232" y2="172" />

  {#if mood === 'hors-ligne'}
    <!-- Endormi en boule sur le câble de la box -->
    <rect class="box" x="18" y="128" width="70" height="40" />
    <path class="stroke" d="M32 128 L26 100 M74 128 L80 100" />
    <circle class="led" cx="34" cy="148" r="4" />
    <circle class="led off" cx="48" cy="148" r="4" />
    <path class="cable" d="M88 158 C110 158 112 168 132 168 C160 168 190 160 230 166" />
    <ellipse class="fur" cx="176" cy="146" rx="50" ry="25" />
    <path class="stripe" d="M168 124 L172 134 M182 122 L184 133 M196 125 L194 135" />
    <path class="tail-outline" d="M220 152 C214 172 160 176 140 166" />
    <path class="tail" d="M220 152 C214 172 160 176 140 166" />
    <path class="fur" d="M120 132 L118 106 L134 118 Z" />
    <path class="fur" d="M150 128 L156 104 L140 116 Z" />
    <ellipse class="fur" cx="136" cy="142" rx="24" ry="21" />
    <path class="stroke" d="M124 142 Q129 147 134 142 M140 142 Q145 147 150 142" />
    <path class="nose" d="M134 150 L140 150 L137 154 Z" />
    <text class="zz" x="164" y="96">z</text>
    <text class="zz small" x="182" y="78">z</text>
    <text class="zz smaller" x="196" y="62">z</text>
  {:else if mood === 'serveur'}
    <!-- Pousse le verre du bord de la table, l'air innocent -->
    <rect class="table" x="14" y="124" width="166" height="12" />
    <path class="stroke" d="M28 136 L28 172 M166 136 L166 172" />
    {@render sittingCat(84, 124, 0.78, 1, 'open')}
    <path class="fur" d="M106 98 C124 92 142 100 150 106 C142 114 122 112 106 108 Z" />
    <ellipse class="fur" cx="152" cy="108" rx="8" ry="6.5" />
    <path class="stroke thin" d="M152 104 L152 112" />
    <g transform="rotate(24 178 124)">
      <path class="glass" d="M160 84 L182 84 L178 124 L164 124 Z" />
      <path class="water" d="M162 100 L180 100 L178 122 L164 122 Z" />
    </g>
    <circle class="drop" cx="196" cy="140" r="4" />
    <circle class="drop" cx="204" cy="156" r="3" />
    <circle class="drop" cx="190" cy="162" r="3" />
  {:else if mood === 'interdit'}
    <!-- Assis bien droit devant une porte fermée, très digne -->
    <rect class="door" x="140" y="20" width="84" height="152" />
    <rect class="panel" x="152" y="34" width="60" height="50" />
    <rect class="panel" x="152" y="98" width="60" height="58" />
    <circle class="knob" cx="148" cy="104" r="5" />
    {@render sittingCat(84, 170, 1, 1, 'open')}
  {:else if mood === 'introuvable'}
    <!-- Seule la queue dépasse d'un carton -->
    <path class="flap" d="M58 104 L36 84 L76 84 L98 104 Z" />
    <path class="flap" d="M182 104 L204 84 L164 84 L142 104 Z" />
    <path class="tail-outline" d="M150 106 C150 70 186 74 178 44 C174 30 160 30 160 40" />
    <path class="tail" d="M150 106 C150 70 186 74 178 44 C174 30 160 30 160 40" />
    <rect class="carton" x="58" y="104" width="124" height="68" />
    <path class="stroke thin" d="M120 104 L120 128" />
    <text class="mark" x="92" y="156">?</text>
  {:else}
    <!-- Emmêlé dans une pelote de laine -->
    {@render sittingCat(96, 170, 1, -1, 'wide')}
    <path class="yarn" d="M60 128 C90 150 110 110 132 140 C150 162 170 150 186 158" />
    <path class="yarn" d="M66 104 C96 120 120 96 128 118" />
    <path class="yarn" d="M70 150 C80 130 108 168 120 148" />
    <circle class="ball" cx="200" cy="150" r="22" />
    <path class="ball-line" d="M182 140 C196 132 212 140 220 150 M184 158 C198 150 212 160 218 164 M196 128 C190 144 196 162 206 172" />
  {/if}
</svg>

<style>
  .cat { display: block; max-width: 100%; height: auto; }
  .stroke, .fur, .belly, .inner, .nose, .box, .table, .door, .panel, .knob, .glass, .carton, .flap, .ball, .led {
    stroke: var(--line);
    stroke-width: 4;
  }
  .stroke { fill: none; }
  .thin { stroke-width: 2.5; }
  .fur { fill: var(--orange); }
  .belly { fill: var(--paper); stroke-width: 0; }
  .inner { fill: var(--accent); stroke-width: 2.5; }
  .stripe { stroke: var(--line); stroke-width: 3.5; fill: none; }
  .nose { fill: var(--accent); stroke-width: 2.5; }
  .pupil { fill: var(--ink); }  /* toujours foncé (yeux lisibles en mode sombre) */
  .eye-white { fill: var(--paper); stroke: var(--line); stroke-width: 3; }
  .tail-outline { stroke: var(--line); stroke-width: 14; fill: none; }
  .tail { stroke: var(--orange); stroke-width: 7; fill: none; }
  .floor { stroke: var(--line); stroke-width: 4; }
  .box, .table, .door { fill: var(--surface); }
  .panel { fill: var(--surface-sunken); stroke-width: 3; }
  .knob { fill: var(--butter); stroke-width: 3; }
  .led { fill: var(--success); stroke-width: 2.5; }
  .led.off { fill: var(--error); }
  .cable { stroke: var(--line); stroke-width: 5; fill: none; }
  .glass { fill: var(--surface); }
  .water { fill: var(--highlight); }
  .drop { fill: var(--highlight); stroke: var(--line); stroke-width: 2.5; }
  .carton, .flap { fill: var(--butter); }
  .flap { stroke-width: 3.5; }
  .ball { fill: var(--accent); }
  .ball-line { stroke: var(--line); stroke-width: 2.5; fill: none; }
  .yarn { stroke: var(--accent); stroke-width: 4; fill: none; }
  .zz, .mark { fill: var(--line); font-family: var(--font-display); font-weight: 800; font-size: 26px; }
  .zz.small { font-size: 20px; }
  .zz.smaller { font-size: 15px; }
  .mark { font-size: 36px; fill: var(--ink); }
</style>
