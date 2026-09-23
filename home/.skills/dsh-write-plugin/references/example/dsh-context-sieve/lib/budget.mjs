// budget.mjs — deterministic token accounting with hard per-category caps.
//
// No LLM, no randomness. Usage is chars/4 (stable heuristic). Caps are hard:
// a category at/over cap is flagged and recommended for eviction, never
// silently exceeded.

export const DEFAULT_CAPS = {
  toolResults: 12000,   // cumulative tool output tokens
  assistantText: 8000,  // cumulative assistant prose
  codeBlocks: 16000,    // cumulative fenced code
  commands: 4000,       // cumulative command blocks
}

export function usageRows(usage, caps = DEFAULT_CAPS) {
  return Object.keys(caps).map((cat) => {
    const used = usage[cat] ?? 0
    const limit = caps[cat]
    return { category: cat, used, limit, pct: Math.min(100, Math.round((used / Math.max(1, limit)) * 100)), over: used >= limit }
  })
}

export function overCap(usage, caps = DEFAULT_CAPS) {
  return usageRows(usage, caps).filter((r) => r.over)
}

/**
 * Total retained tokens across all tracked categories.
 */
export function totalTokens(usage) {
  return Object.values(usage).reduce((a, b) => a + (Number(b) || 0), 0)
}

/**
 * Score how "heavy" the current context is: 0 = lean, 1 = maxed out.
 * Used to decide whether a compaction/briefing is warranted.
 */
export function loadFraction(usage, caps = DEFAULT_CAPS) {
  const rows = usageRows(usage, caps)
  if (!rows.length) return 0
  const avg = rows.reduce((a, r) => a + r.used / Math.max(1, r.limit), 0) / rows.length
  return Math.min(1, avg)
}
