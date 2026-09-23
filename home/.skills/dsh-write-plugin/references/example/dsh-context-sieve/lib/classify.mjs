// classify.mjs — deterministic keep/trim/drop classifier for context chunks.
//
// Zero dependencies, pure functions. This is the sieve core: it decides, with
// no LLM call, whether a piece of context is high-signal (keep), low-signal
// but salvageable (trim to a bounded sketch), or pure weight (drop).
//
// The verdict is a *recommendation* the ledger/tools act on — a plugin cannot
// rewrite the model's live buffer, so pruning manifests as a pruned view + a
// reversible handle, not a silent edit.

// ── token estimate ──────────────────────────────────────────────────────────

// Rough but stable: ~4 chars/token for English-ish text. Consistent > precise.
export function estTokens(text) {
  if (!text) return 0
  const chars = String(text).length
  return Math.max(1, Math.ceil(chars / 4))
}

// ── keep heuristics ─────────────────────────────────────────────────────────

// A chunk is "keep" when it carries information the model cannot cheaply
// re-derive: code, concrete identifiers, errors/stacks, decisions, commands.
const KEEP_PATTERNS = [
  /```[\s\S]*?```/y,                       // fenced code block
  /(?:^|\s)(?:npm|pnpm|yarn|bun|cargo|pip|git|python|node|rustc|go run|make|ssh|scp|curl|wget|docker|kubectl|systemctl|grep|rg|awk|sed)\b/y, // commands
  /(?:^|\s)(?:Error|TypeError|ReferenceError|SyntaxError|panic|fatal|cannot|undefined is not|no such|not found|permission denied|timeout|ECONN|deadline exceeded)\b/y, // errors
  /\.(?:ts|tsx|js|cjs|mjs|py|go|rs|java|kt|sh|bash|zsh|yml|yaml|json|toml|md|css|html|vue|svelte|rb|php|cs|cpp|cc|c|h)\b/y, // file extensions
  /\/[A-Za-z0-9._/-]{2,}(?:\.[A-Za-z]{2,15})?/, // a path-ish token
  /\b[0-9a-fA-F]{8}(?:-[0-9a-fA-F]+){4}[0-9a-fA-F]\b/, // uuid / long hex
  /(?:^|\n)\s*#{1,6}\s+/y,                  // heading
  /(?:^|\s)(?:DECISION|DECIDED|NOTE|TODO|FIXME|XXX|HACK|WARNING|CAUTION)\b/y, // signal markers
  /(?:^|\s)(?:=>|→|⟶)\s/y,                  // arrow / result marker
]

// ── trim heuristics ─────────────────────────────────────────────────────────

// Collapsible: long whitespace runs, repeated identical lines, over-long
// low-info blocks (keep head + tail + a count marker).
function hasRepeats(text) {
  const lines = text.split('\n')
  if (lines.length < 6) return false
  const seen = new Set()
  for (const line of lines) {
    const k = line.trim()
    if (!k) continue
    if (seen.has(k)) return true
    seen.add(k)
  }
  return false
}

function whitespaceRatio(text) {
  const ws = (text.match(/\s/g) || []).length
  return ws / Math.max(1, text.length)
}

// ── verdict ─────────────────────────────────────────────────────────────────

/**
 * Classify a context chunk.
 * @param {string} text
 * @param {{minKeepTokens?: number}} [opts]
 * @returns {{verdict: 'keep'|'trim'|'drop', reason: string, sketch?: string, savedTokens: number}}
 */
export function classify(text, opts = {}) {
  if (text === undefined || text === null) {
    return { verdict: 'drop', reason: 'empty', savedTokens: 0 }
  }
  const str = String(text)
  const tokens = estTokens(str)

  // Pure weight: blank or whitespace-dominant.
  if (str.trim().length === 0 || whitespaceRatio(str) > 0.92) {
    return { verdict: 'drop', reason: 'whitespace', savedTokens: tokens }
  }

  // High-signal: keep whole.
  for (const re of KEEP_PATTERNS) {
    if (re.test(str)) {
      return { verdict: 'keep', reason: 'signal', savedTokens: 0 }
    }
  }

  // Over-long block of otherwise-generic text: trim to a bounded sketch.
  if (tokens > (opts.minKeepTokens ?? 400) || (str.split('\n').length > 80 && hasRepeats(str))) {
    const sketch = trimSketch(str)
    return { verdict: 'trim', reason: 'oversized', sketch, savedTokens: tokens - estTokens(sketch) }
  }

  // Repeated-line noise without any signal anchor: trim the dupes.
  if (hasRepeats(str) && !/^\s*$/.test(str) && whitespaceRatio(str) < 0.6) {
    const sketch = trimSketch(str)
    return { verdict: 'trim', reason: 'repeats', sketch, savedTokens: tokens - estTokens(sketch) }
  }

  return { verdict: 'keep', reason: 'baseline', savedTokens: 0 }
}

/**
 * Produce a bounded, reversible sketch of an oversized/repeat block.
 * Keeps head + tail lines and a count marker so nothing is truly lost.
 */
export function trimSketch(str, { head = 3, tail = 3, maxLines = 12 } = {}) {
  const lines = str.split('\n')
  if (lines.length <= maxLines) return str
  const kept = [...lines.slice(0, head), `…[${lines.length - head - tail} lines collapsed]…`, ...lines.slice(-tail)]
  return kept.join('\n')
}
