// index.mjs — dsh-context-sieve: deterministic, reversible context-budget
// manager for DeepSeek Harness. Thin entry: resolve the real defineTool and
// delegate all wiring to the harness-independent core.
//
// Not another warehouse. It watches the session firehose, classifies every
// chunk with zero LLM calls, keeps a reversible ledger (trimmed/evicted chunks
// stay expandable via a handle), and injects a live budget + post-compaction
// briefing into the system prompt. Compaction summarization burns tokens to
// save tokens; the sieve evicts by rule, so it costs ~nothing to run.
//
// Seams: session (session/event firehose), systemPrompt (section), tools
// (register), lifecycle (effect).

import { defineTool } from '@deepseek-ai/dsh-tools'
import { makeSieve } from './lib/sieve-core.mjs'

export const name = 'sieve'

export const inject = ['systemPrompt', 'tools']

export function apply(ctx, config = {}) {
  makeSieve({ ctx, config, defineTool })
}
