// sieve-core.mjs — harness-independent wiring for dsh-context-sieve.
//
// All seam logic lives here, parameterized by an injectable `defineTool` so the
// pure core is unit-testable without @deepseek-ai/dsh-tools installed. The thin
// index.mjs entry just resolves the real defineTool and calls makeSieve.

import { createLedger } from './ledger.mjs'
import { DEFAULT_CAPS, usageRows, overCap, loadFraction } from './budget.mjs'
import { extractEventText } from './extract.mjs'

export const SECTION_NAME = 'dsh-context-sieve:budget'
export const SECTION_ORDER = 1000

const CATEGORY_BY_EVENT = {
  'tool/call': 'commands',
  'tool/result': 'toolResults',
  'assistant/message': 'assistantText',
}

/**
 * @param {{ctx:object, config?:object, defineTool?:function}} opts
 */
export function makeSieve({ ctx, config = {}, defineTool }) {
  if (config.enabled === false) return

  const caps = { ...DEFAULT_CAPS, ...(config.caps ?? {}) }
  const ledger = createLedger({ caps, maxEvents: config.maxEvents, minKeepTokens: config.minKeepTokens })

  let briefing = ''
  let revision = 0
  const bump = () => { revision += 1 }

  // ── firehose ───────────────────────────────────────────────────────────────
  ctx.on('session/event', (session, event) => {
    if (!session || !event || typeof event !== 'object') return
    const type = event.type
    if (type === 'compaction/end') {
      briefing = buildBriefing(ledger)
      ledger.compact()
      bump()
      return
    }
    const category = CATEGORY_BY_EVENT[type]
    if (!category) return
    const text = extractEventText(event)
    if (!text) return
    const rec = ledger.push({ type, category, text })
    if (rec.verdict !== 'keep') bump()
  })

  // ── systemPrompt section ───────────────────────────────────────────────────
  ctx.systemPrompt.section({
    name: SECTION_NAME,
    order: SECTION_ORDER,
    text: () => renderSection(ledger, briefing, revision),
  })

  // ── tools ──────────────────────────────────────────────────────────────────
  ctx.tools.register(defineTool(makeReportTool(ledger)))
  ctx.tools.register(defineTool(makeExpandTool(ledger)))
  ctx.tools.register(defineTool(makeEvictTool(ledger, caps)))

  // ── lifecycle ──────────────────────────────────────────────────────────────
  ctx.effect(() => () => ledger.clear(), 'dsh-context-sieve.dispose')
}

// ── render ──────────────────────────────────────────────────────────────────

function renderSection(ledger, briefing, revision) {
  const status = ledger.status()
  const over = overCap(status.usage, status.caps)
  const rows = usageRows(status.usage, status.caps)
  const lines = []
  lines.push(`<context_budget>`)
  lines.push(`context load ${Math.round(status.load * 100)}% · ${status.total} tokens retained · ${rows.length} categories`)
  for (const r of rows) {
    const flag = r.over ? ' ⚠️ over cap' : ''
    lines.push(`- ${r.category}: ${r.used}/${r.limit} tokens (${r.pct}%${flag})`)
  }
  if (over.length) {
    lines.push(`> bloat detected in: ${over.map((o) => o.category).join(', ')} — run context_report or context_evict`)
  }
  if (briefing) {
    lines.push('')
    lines.push(briefing)
  }
  lines.push(`</context_budget>`)
  // digest the revision so hot-reload churn does not keep bloat the prompt
  return `${lines.join('\n')} ::rev=${revision}`
}

function buildBriefing(ledger) {
  const status = ledger.status()
  if (status.total === 0) return ''
  return `<compaction_briefing>post-compaction context: ${status.total} tokens across ${status.rows.length} categories. Run context_report for the retained view or context_expand <handle> to restore a pruned chunk.</compaction_briefing>`
}

// ── tool definitions ─────────────────────────────────────────────────────────

function makeReportTool(ledger) {
  return {
    name: 'context_report',
    description:
      'Report current context budget and bloat. Shows per-category token usage vs hard caps, ' +
      'which chunks were trimmed/evicted, and recommended evictions. Read-only; no model call.',
    parameters: {
      full: {
        type: 'boolean',
        description: 'When true, list every retained chunk with its handle and tokens. Default false (summary only).',
      },
    },
    output: {
      schema: {
        type: 'object',
        properties: {
          ok: { type: 'boolean' },
          toolResults: { type: 'number' },
          assistantText: { type: 'number' },
          codeBlocks: { type: 'number' },
          commands: { type: 'number' },
          total: { type: 'number' },
          evictables: { type: 'number' },
          handles: { type: 'array', items: { type: 'string' } },
        },
        additionalProperties: true,
      },
      render: (_args, value) => [{ type: 'text', text: JSON.stringify(value) }],
    },
    execute: async (args) => {
      const status = ledger.status()
      const evictables = ledger.evictables()
      const out = []
      out.push(`# context_report`)
      out.push(`Load ${Math.round(status.load * 100)}% · ${status.total} tokens retained · ${status.rows.length} categories`)
      for (const r of status.rows) {
        const flag = r.over ? ' ⚠️ over cap' : ''
        out.push(`- ${r.category}: ${r.used}/${r.limit} (${r.pct}%${flag})`)
      }
      out.push('')
      if (evictables.length === 0) {
        out.push('Bloat: none over any cap.')
      } else {
        out.push(`Bloat: ${evictables.length} chunk(s) over cap — eligible for reversible eviction:`)
        for (const rec of evictables.slice(0, 12)) {
          out.push(`- [${rec.id}] ${rec.category} · ${rec.rawTokens} tok · ${rec.reason}`)
        }
        if (evictables.length > 12) out.push(`- …${evictables.length - 12} more`)
      }
      if (args.full) {
        out.push('')
        out.push(`## full retained view (${status.total} tokens)`)
        for (const rec of ledger.snapshot()) {
          out.push(`- [${rec.id}] ${rec.type} ${rec.category} · ${rec.prunedTokens} tok · ${rec.verdict}`)
        }
      }
      return { ok: true, ...status.usage, total: status.total, evictables: evictables.length, handles: ledger.snapshot().map((r) => r.id) }
    },
  }
}

function makeExpandTool(ledger) {
  return {
    name: 'context_expand',
    description:
      'Restore a pruned or evicted context chunk by its handle (e.g. sieve#7). ' +
      'Handles are emitted by context_report and the budget line. Reverses a prune; nothing is ever truly lost.',
    parameters: {
      handle: { type: 'string', required: true, description: 'The sieve handle to expand, e.g. sieve#7.' },
    },
    output: {
      schema: {
        type: 'object',
        properties: {
          ok: { type: 'boolean' },
          handle: { type: 'string' },
          verdict: { type: 'string' },
          reason: { type: 'string' },
          text: { type: 'string' },
          error: { type: 'string' },
        },
        additionalProperties: true,
      },
      render: (_args, value) => [{ type: 'text', text: value.ok ? value.text : `error: ${value.error}` }],
    },
    execute: async (args) => {
      const rec = ledger.expand(args.handle)
      if (!rec) return { ok: false, error: `no such handle: ${args.handle}` }
      return { ok: true, handle: rec.id, verdict: rec.verdict, reason: rec.reason, text: rec.raw }
    },
  }
}

function makeEvictTool(ledger, caps) {
  return {
    name: 'context_evict',
    description:
      'Flush the retained context ledger: drops the raw bytes of every retained chunk but keeps the ' +
      'reversible handles so context_expand still works. Returns how many chunks were evicted and how ' +
      'many tokens freed. RAM reclaim, reversible and lossless.',
    parameters: {},
    output: {
      schema: {
        type: 'object',
        properties: {
          ok: { type: 'boolean' },
          evicted: { type: 'number' },
          freedTokens: { type: 'number' },
        },
        additionalProperties: true,
      },
      render: (_args, value) => [{ type: 'text', text: JSON.stringify(value) }],
    },
    execute: async () => {
      const { evicted, freedTokens } = ledger.compact(0)
      return { ok: true, evicted, freedTokens }
    },
  }
}
