import { describe, it, expect } from 'vitest'
import { readFileSync } from 'node:fs'
import { join } from 'node:path'
import { commentProblem, COMMENT_MAX } from '../../src/lib/api/comments'

const M31 = readFileSync(join(__dirname, '../../supabase/migrations/20261119100000_commentaires.sql'), 'utf8')

describe('Commentaires : mêmes règles que la base', () => {
  it('longueur maximale identique', () => {
    expect(M31).toContain(`BETWEEN 1 AND ${COMMENT_MAX}`)
  })
  it('vide refusé, espaces ignorés, trop long refusé', () => {
    expect(commentProblem('   ')).not.toBeNull()
    expect(commentProblem('  ok  ')).toBeNull()
    expect(commentProblem('x'.repeat(COMMENT_MAX))).toBeNull()
    expect(commentProblem('x'.repeat(COMMENT_MAX + 1))).not.toBeNull()
  })
})
