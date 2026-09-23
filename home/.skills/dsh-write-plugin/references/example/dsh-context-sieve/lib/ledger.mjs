// ledger.mjs — in-memory record of context events with pruned views and
// reversible handles. This is what makes pruning lossless: every trimmed or
// evicted chunk keeps a handle so it can be expanded on demand.

let seq = 0
const nextId = () => `sieve#${++seq}`

export function resetSeq() { seq = 0 }

/**
 * @param {{maxEvents?: number, caps?: object}} [opts]
 */
export function createLedger(opts = {}) {
  const maxEvents = opts.maxEvents ?? 500
  const caps = { ...DEFAULT_CAPS_FROM(opts.caps) }
  const events = new Map() // id -> record
  const order = [] // ids, insertion order
  const usage = { toolResults: 0, assistantText: 0, codeBlocks: 0, commands: 0 }

  return {
    /**
     * Record one context event. `text` is classified and stored as both the
     * raw view and a pruned view; the delta is accounted to a budget category.
     */
    push({ type, category, text, meta = {} }) {
      const id = nextId()
      const { verdict, reason, sketch, savedTokens } = classify(text, {
        minKeepTokens: opts.minKeepTokens,
      })
      const rawTokens = estTokens(text)
      const kept = verdict === 'keep' ? text : (sketch ?? text)
      const rec = {
        id, type, category,
        raw: text,
        view: kept,
        verdict, reason,
        rawTokens, prunedTokens: estTokens(kept), savedTokens,
        meta,
        ts: Date.now(),
      }
      events.set(id, rec)
      order.push(id)
      usage[category] = (usage[category] ?? 0) + rec.prunedTokens
      return rec
    },

    /** Expand a pruned/evicted chunk back to raw via its handle. */
    expand(id) {
      return events.get(id) ?? null
    },

    /** Full ordered snapshot of retained records (for the report's detailed view). */
    snapshot() {
      return order.map((id) => events.get(id)).filter(Boolean)
    },

    /** Current per-category usage rows + overload flags. */
    status() {
      const rows = usageRows(usage, caps)
      return { usage, caps, rows, total: totalTokens(usage), load: loadFraction(usage) }
    },

    /** Ids flagged for eviction (over cap) — reversible handles retained. */
    evictables() {
      const over = new Set(overCap(usage, caps).map((r) => r.category))
      const candidates = []
      for (const id of order) {
        const rec = events.get(id)
        if (rec && rec.verdict === 'trim' && over.has(rec.category)) candidates.push(rec)
      }
      return candidates
    },

    /**
     * Evict raw views past `keepRetained` while preserving the handle index so
     * expansion still works. This is the token savings: raw bytes leave RAM,
     * the reversible pointer stays.
     */
    compact(keepRetained = 1) {
      let evicted = 0
      let freedTokens = 0
      const live = order.filter((id) => events.has(id))
      const stale = live.slice(0, Math.max(0, live.length - keepRetained))
      for (const id of stale) {
        const rec = events.get(id)
        if (rec) { freedTokens += rec.rawTokens; rec.raw = null; rec.rawTokens = 0; evicted += 1 }
      }
      return { evicted, freedTokens }
    },

    clear() {
      events.clear()
      order.length = 0
      for (const k of Object.keys(usage)) usage[k] = 0
    },
  }
}

// small helpers pulled in to avoid a second import line at call sites
import { classify, estTokens } from './classify.mjs'
import { DEFAULT_CAPS, usageRows, overCap, totalTokens, loadFraction } from './budget.mjs'

function DEFAULT_CAPS_FROM(caps) {
  return caps ? { ...DEFAULT_CAPS, ...caps } : DEFAULT_CAPS
}
