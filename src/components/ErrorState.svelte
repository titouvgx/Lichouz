<script lang="ts">
  // Erreur avec le chat de Lichouz (v2.1.0) : dessin + titre + message clair + bouton.
  // Le type est deviné depuis l'erreur (errorMood) si on ne le donne pas.
  import ErrorCat from './ErrorCat.svelte'
  import Icon from './Icon.svelte'
  import { errorMood, isTechnical, MOOD_TEXT, type CatMood } from '../lib/errorMood'

  interface Props {
    /** L'erreur reçue (pour deviner le type), ou rien. */
    error?: unknown
    /** Forcer le type (ex. 'introuvable' pour une adresse inconnue). */
    mood?: CatMood
    /** Titre et message à la place des textes par défaut du type. */
    title?: string
    message?: string
    /** Bouton « Réessayer » (ou autre libellé) ; absent = pas de bouton. */
    onretry?: () => void
    retryLabel?: string
    busy?: boolean
    compact?: boolean
  }
  let { error, mood, title, message, onretry, retryLabel = 'Réessayer', busy = false, compact = false }: Props = $props()

  const kind = $derived<CatMood>(mood ?? errorMood(error))
</script>

<div class="error-state" class:compact role="alert">
  <ErrorCat mood={kind} size={compact ? 170 : 230} />
  <h2>{title ?? MOOD_TEXT[kind].title}</h2>
  <p>{message && !isTechnical(message) ? message : MOOD_TEXT[kind].message}</p>
  {#if onretry}
    <button class="btn btn-primary" onclick={onretry} disabled={busy} aria-busy={busy}>
      <Icon name="refresh" size={18} /> {busy ? 'Un instant…' : retryLabel}
    </button>
  {/if}
</div>

<style>
  .error-state {
    display: grid;
    justify-items: center;
    gap: var(--sp-3);
    text-align: center;
    padding: var(--sp-4) var(--sp-3);
  }
  h2 { font-size: var(--fs-xl); line-height: 1.1; }
  p { color: var(--text-secondary); line-height: 1.45; max-width: 34ch; }
  .btn { min-height: 48px; min-width: 200px; gap: var(--sp-2); }
  .compact { padding: var(--sp-3) var(--sp-2); }
  .compact h2 { font-size: var(--fs-lg); }
</style>
