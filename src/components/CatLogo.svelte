<script lang="ts">
  // Logo de Lichouz (v2.1.0) : la tête du chat de l'appli, même dessin que l'icône
  // installée (public/icon-512.png) et le favicon. Couleurs du thème.
  let { size = 44 }: { size?: number } = $props()
</script>

<svg width={size} height={size} viewBox="96 96 320 320" aria-hidden="true" stroke-linejoin="round" stroke-linecap="round">
  <g class="shadow" transform="translate(16 16)">
    <path d="M150 236 L160 112 L238 178 Z" /><path d="M362 236 L352 112 L274 178 Z" /><ellipse cx="256" cy="282" rx="138" ry="112" />
  </g>
  <g class="head">
    <path d="M150 236 L160 112 L238 178 Z" /><path d="M362 236 L352 112 L274 178 Z" /><ellipse cx="256" cy="282" rx="138" ry="112" />
  </g>
  <path class="ink" d="M232 182 L236 208 M256 178 L256 206 M280 182 L276 208" stroke-width="12" />
  <ellipse class="fill" cx="206" cy="276" rx="16" ry="24" /><ellipse class="fill" cx="306" cy="276" rx="16" ry="24" />
  <path class="fill" d="M240 314 L272 314 L256 332 Z" />
  <path class="ink" d="M226 346 Q241 362 256 346 Q271 362 286 346" stroke-width="10" fill="none" />
</svg>

<style>
  svg { display: block; overflow: visible; }
  .shadow { fill: var(--ink); stroke: var(--ink); stroke-width: 18; }
  .head { fill: var(--orange); stroke: var(--ink); stroke-width: 18; }
  .ink { stroke: var(--ink); fill: none; }
  .fill { fill: var(--ink); }
</style>
