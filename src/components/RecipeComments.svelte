<script lang="ts">
  // Commentaires d'une recette (v2.6.0) : lus par toute la famille seulement,
  // même sur une recette du catalogue. Écrire (500 caractères), supprimer le
  // sien, ou ceux de son foyer quand on est admin. Pas de modification.
  import Icon from './Icon.svelte'
  import ConfirmDialog from './ConfirmDialog.svelte'
  import { auth } from '../lib/auth.svelte'
  import { profileState } from '../lib/profile.svelte'
  import { toast } from '../lib/toast.svelte'
  import {
    fetchComments, addComment, deleteComment, commentProblem, COMMENT_MAX, type RecipeComment,
  } from '../lib/api/comments'

  let { recipeId }: { recipeId: string } = $props()

  let comments = $state<RecipeComment[]>([])
  let loading = $state(true)
  let loadError = $state<string | null>(null)
  let text = $state('')
  let sending = $state(false)
  let toDelete = $state<RecipeComment | null>(null)
  let deleting = $state(false)

  const remaining = $derived(COMMENT_MAX - text.trim().length)
  const problem = $derived(commentProblem(text))

  async function load() {
    try {
      comments = await fetchComments(recipeId)
      loadError = null
    } catch (e: any) {
      loadError = e?.message ?? 'Chargement impossible'
    } finally {
      loading = false
    }
  }

  $effect(() => {
    void recipeId
    loading = true
    void load()
  })

  async function send() {
    if (sending || problem) return
    const userId = auth.user?.id
    const sf = profileState.context?.family?.super_family_id ?? profileState.context?.superFamily?.id
    if (!userId || !sf) { toast.error('Profil introuvable'); return }
    sending = true
    try {
      await addComment(recipeId, text, userId, sf)
      text = ''
      await load()
    } catch (e: any) {
      toast.error(e?.message ?? 'Envoi impossible')
    } finally {
      sending = false
    }
  }

  async function confirmDelete() {
    if (!toDelete) return
    deleting = true
    try {
      await deleteComment(toDelete.id)
      comments = comments.filter((c) => c.id !== toDelete!.id)
      toast.success('Commentaire supprimé')
      toDelete = null
    } catch (e: any) {
      toast.error(e?.message ?? 'Suppression impossible')
    } finally {
      deleting = false
    }
  }

  function when(iso: string): string {
    const d = new Date(iso)
    const days = Math.floor((Date.now() - d.getTime()) / 86_400_000)
    if (days < 1) return `aujourd’hui à ${d.toLocaleTimeString('fr-FR', { hour: '2-digit', minute: '2-digit' })}`
    if (days < 2) return 'hier'
    return `le ${d.toLocaleDateString('fr-FR', { day: 'numeric', month: 'short' })}`
  }

  function firstName(c: RecipeComment): string {
    return c.author_name?.trim().split(/\s+/)[0] || c.author_pseudo || 'Quelqu’un'
  }
</script>

<section class="comments card" aria-labelledby="h-comments">
  <h2 id="h-comments" class="band">Commentaires {#if comments.length}<span class="count">{comments.length}</span>{/if}</h2>
  <p class="scope"><Icon name="users" size={14} /> Lus par ta famille seulement.</p>

  {#if loading}
    <p class="muted pad" aria-busy="true">Chargement…</p>
  {:else if loadError}
    <p class="muted pad">Commentaires indisponibles pour l’instant.</p>
  {:else if comments.length === 0}
    <p class="muted pad">Pas encore de commentaire. Une astuce, une variante, un « on a adoré » ?</p>
  {:else}
    <ul>
      {#each comments as c (c.id)}
        <li class="comment" class:mine={c.mine}>
          <div class="meta">
            <strong>{c.mine ? 'Toi' : firstName(c)}</strong>
            {#if c.author_pseudo && !c.mine}<span class="pseudo">@{c.author_pseudo}</span>{/if}
            <span class="when">{when(c.created_at)}</span>
            {#if c.can_delete}
              <button class="del" onclick={() => (toDelete = c)} aria-label="Supprimer ce commentaire">
                <Icon name="trash" size={16} />
              </button>
            {/if}
          </div>
          <p class="body">{c.body}</p>
        </li>
      {/each}
    </ul>
  {/if}

  <form class="write" onsubmit={(e) => { e.preventDefault(); void send() }}>
    <label class="sr-only" for="comment-text">Ton commentaire</label>
    <textarea
      id="comment-text"
      bind:value={text}
      rows="2"
      maxlength={COMMENT_MAX + 50}
      placeholder="Ton commentaire…"
    ></textarea>
    <div class="write-foot">
      <span class="left" class:over={remaining < 0}>{remaining < 0 ? `${-remaining} de trop` : `${remaining} caractères`}</span>
      <button class="btn btn-primary send" type="submit" disabled={!!problem || sending}>
        {sending ? 'Envoi…' : 'Publier'}
      </button>
    </div>
  </form>
</section>

{#if toDelete}
  <ConfirmDialog
    title="Supprimer ce commentaire ?"
    confirmLabel="Supprimer"
    danger
    busy={deleting}
    onconfirm={confirmDelete}
    oncancel={() => { if (!deleting) toDelete = null }}
  >
    Il disparaîtra pour toute la famille. On ne peut pas le récupérer.
  </ConfirmDialog>
{/if}

<style>
  .comments { padding: 0 0 var(--sp-3); }
  .comments h2.band { font-size: 13px; letter-spacing: var(--tracking-caps); justify-content: flex-start; }
  .count {
    display: inline-grid; place-items: center;
    min-width: 22px; height: 22px; padding: 0 4px;
    background: var(--text-on-band); color: var(--band);
    font-size: 12px; font-weight: var(--fw-bold);
  }
  .scope {
    display: flex; align-items: center; gap: 6px;
    margin: var(--sp-2) var(--sp-3) 0;
    font-size: 12px; color: var(--text-secondary);
  }
  .muted { color: var(--text-secondary); }
  .pad { padding: var(--sp-2) var(--sp-3); }
  ul { list-style: none; margin: var(--sp-2) 0 0; padding: 0; }
  .comment {
    padding: var(--sp-2) var(--sp-3);
    border-top: var(--line-thin, 1px) solid var(--line);
  }
  .comment:first-child { border-top: none; }
  .comment.mine { background: var(--surface-hover, var(--surface)); }
  .meta { display: flex; align-items: center; gap: 6px; min-height: 28px; font-size: 13px; }
  .pseudo, .when { color: var(--text-secondary); }
  .del {
    margin-left: auto;
    display: grid; place-items: center;
    width: 44px; height: 44px; margin-top: -8px; margin-bottom: -8px; margin-right: -10px;
    border: none; background: none; color: var(--text);
    cursor: pointer; touch-action: manipulation;
  }
  .body { margin-top: 2px; white-space: pre-line; overflow-wrap: anywhere; line-height: 1.4; }

  .write { display: flex; flex-direction: column; gap: var(--sp-2); padding: var(--sp-3) var(--sp-3) 0; }
  textarea {
    width: 100%;
    min-height: 64px;
    padding: var(--sp-2);
    border: var(--line-w) solid var(--line);
    background: var(--surface);
    color: var(--text);
    font: inherit;
    resize: vertical;
  }
  textarea:focus-visible { outline: 3px solid var(--accent); outline-offset: 1px; }
  .write-foot { display: flex; align-items: center; justify-content: space-between; gap: var(--sp-2); }
  .left { font-size: 12px; color: var(--text-secondary); white-space: nowrap; }
  .left.over { color: var(--error, var(--text)); font-weight: var(--fw-bold); }
  .send { flex: none; width: auto; min-height: 44px; padding: 0 var(--sp-4, 20px); }
</style>
