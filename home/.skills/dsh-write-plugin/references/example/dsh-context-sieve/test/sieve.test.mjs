// test/sieve.test.mjs — deterministic coverage for the sieve core + seam wiring.
// Run: node --test test/*.test.mjs
import { test } from 'node:test'
import assert from 'node:assert/strict'

import { classify, estTokens, trimSketch } from '../lib/classify.mjs'
import { DEFAULT_CAPS, usageRows, overCap, totalTokens, loadFraction } from '../lib/budget.mjs'
import { createLedger, resetSeq } from '../lib/ledger.mjs'
import { extractEventText } from '../lib/extract.mjs'
import { makeSieve } from '../lib/sieve-core.mjs'

// Drive the real core with an identity defineTool (mirrors dsh-tools.defineTool
// returning the descriptor) so the wiring suite needs no installed package.
const defineTool = (d) => d
const sieve = {
  SECTION_NAME: 'dsh-context-sieve:budget',
  apply: (ctx, config = {}) => makeSieve({ ctx, config, defineTool }),
}

// ── mock harness ctx (mirrors the verified seams) ────────────────────────────

function makeMockCtx() {
  const handlers = new Map()
  const sections = []
  const tools = []
  const effects = []
  const ctx = {
    on: (event, handler) => { handlers.set(event, handler); return () => handlers.delete(event) },
    systemPrompt: { section: (s) => { sections.push(s); return () => {} } },
    tools: { register: (t) => { tools.push(t); return () => {} } },
    effect: (fn, tag) => { effects.push({ tag, fn }); return () => {} },
  }
  return { ctx, handlers, sections, tools, effects }
}

function ev(type, data) { return { type, data } }

// ── classify ────────────────────────────────────────────────────────────────

test('classify keeps code blocks', () => {
  const r = classify('```js\nconst x = 1\n```')
  assert.equal(r.verdict, 'keep')
  assert.equal(r.reason, 'signal')
})

test('classify keeps error/stack lines', () => {
  const r = classify('TypeError: x is not a function\n    at foo.js:4:2')
  assert.equal(r.verdict, 'keep')
})

test('classify keeps paths and commands', () => {
  assert.equal(classify('pnpm install --prod').verdict, 'keep')
  assert.equal(classify('/home/solis/project/src/index.ts').verdict, 'keep')
})

test('classify drops pure whitespace', () => {
  const r = classify('      \n   \n')
  assert.equal(r.verdict, 'drop')
  assert.ok(r.savedTokens > 0)
})

test('classify trims oversized generic blocks', () => {
  const big = Array.from({ length: 200 }, (_, i) => `line ${i} of nothing meaningful`).join('\n')
  const r = classify(big)
  assert.equal(r.verdict, 'trim')
  assert.ok(r.sketch)
  assert.ok(r.savedTokens > 0)
})

test('classify trims repeated-line noise without signal', () => {
  const rep = Array.from({ length: 30 }, () => 'error logging line').join('\n')
  const r = classify(rep)
  assert.equal(r.verdict, 'trim')
})

test('estTokens is stable (~4 chars/token)', () => {
  assert.equal(estTokens('abcd'), 1)
  assert.equal(estTokens('abcdefgh'), 2)
})

// ── budget ──────────────────────────────────────────────────────────────────

test('usageRows reports all categories with over flag', () => {
  const rows = usageRows({ toolResults: 13000, assistantText: 100, codeBlocks: 0, commands: 0 })
  const tr = rows.find((r) => r.category === 'toolResults')
  assert.equal(tr.over, true)
  assert.equal(rows.length, 4)
})

test('overCap lists only over-cap categories', () => {
  const over = overCap({ toolResults: 20000, assistantText: 0, codeBlocks: 0, commands: 0 })
  assert.deepEqual(over.map((o) => o.category), ['toolResults'])
})

test('loadFraction is 0 when empty and 1 when maxed', () => {
  assert.equal(loadFraction({ toolResults: 0, assistantText: 0, codeBlocks: 0, commands: 0 }), 0)
  assert.equal(loadFraction({ toolResults: DEFAULT_CAPS.toolResults, assistantText: DEFAULT_CAPS.assistantText, codeBlocks: DEFAULT_CAPS.codeBlocks, commands: DEFAULT_CAPS.commands }), 1)
})

// ── ledger ──────────────────────────────────────────────────────────────────

test('ledger accounts usage and exposes status', () => {
  const led = createLedger({})
  led.push({ type: 'tool/result', category: 'toolResults', text: '```js\nconst x=1\n```' })
  const s = led.status()
  assert.equal(s.usage.toolResults, estTokens('```js\nconst x=1\n```'))
  assert.equal(s.rows.length, 4)
})

test('ledger.expand restores a trimmed chunk', () => {
  const led = createLedger({ minKeepTokens: 20 })
  const big = Array.from({ length: 20 }, () => 'x'.repeat(20)).join('\n')
  const rec = led.push({ type: 'tool/result', category: 'toolResults', text: big })
  assert.equal(rec.verdict, 'trim')
  const restored = led.expand(rec.id)
  assert.equal(restored.raw, big)
  assert.notEqual(restored.view, big)
})

test('ledger.evictables only lists over-cap trimmed chunks', () => {
  const led = createLedger({ caps: { ...DEFAULT_CAPS, toolResults: 30 } })
  led.push({ type: 'tool/result', category: 'toolResults', text: Array.from({ length: 15 }, () => 'y'.repeat(20)).join('\n') })
  const ev = led.evictables()
  assert.equal(ev.length, 1)
  assert.equal(ev[0].category, 'toolResults')
})

test('ledger.compact drops raw but keeps handle expandable', () => {
  const led = createLedger({})
  const rec = led.push({ type: 'assistant/message', category: 'assistantText', text: 'hello world repeated\n'.repeat(20) })
  led.compact(0)
  const after = led.expand(rec.id)
  assert.equal(after.raw, null, 'raw evicted')
  assert.equal(after.id, rec.id, 'handle still resolves')
})

test('ledger.clear resets usage and records', () => {
  const led = createLedger({})
  led.push({ type: 'tool/call', category: 'commands', text: 'npm install' })
  assert.ok(led.status().total > 0)
  led.clear()
  assert.equal(led.status().total, 0)
})

// ── extract ─────────────────────────────────────────────────────────────────

test('extractEventText pulls tool result text', () => {
  const t = extractEventText(ev('tool/result', { message: { content: [{ text: 'result body' }] } }))
  assert.equal(t, 'result body')
})

test('extractEventText pulls tool call name+args', () => {
  const t = extractEventText(ev('tool/call', { name: 'bash', arguments: '{"cmd":"ls"}' }))
  assert.equal(t, 'bash {"cmd":"ls"}')
})

// ── apply seam wiring ───────────────────────────────────────────────────────

test('apply registers section, tools, event handler, effect', () => {
  const { ctx, sections, tools, handlers, effects } = makeMockCtx()
  sieve.apply(ctx, {})
  assert.equal(sections.length, 1)
  assert.equal(sections[0].name, 'dsh-context-sieve:budget')
  assert.equal(tools.length, 3)
  assert.equal(tools.map((t) => t.name).sort().join(','), 'context_evict context_report context_expand'.split(' ').sort().join(','))
  assert.ok(handlers.has('session/event'))
  assert.equal(effects.length, 1)
})

test('firehose feeds ledger and section reflects budget', () => {
  const { ctx, sections, handlers } = makeMockCtx()
  sieve.apply(ctx, {})
  const handler = handlers.get('session/event')

  handler({}, ev('tool/result', { message: { content: [{ text: '```python\nprint(1)\n```' }] } }))
  handler({}, ev('assistant/message', { content: [{ text: 'here is the answer' }] }))

  const sectionText = sections[0].text({})
  assert.match(sectionText, /context_budget/)
  assert.match(sectionText, /toolResults/)
  assert.match(sectionText, /assistantText/)
})

test('compaction/end emits briefing and compacts ledger', () => {
  const { ctx, sections, handlers } = makeMockCtx()
  sieve.apply(ctx, { caps: { ...DEFAULT_CAPS, toolResults: 30 } })
  const handler = handlers.get('session/event')

  handler({}, ev('tool/result', { message: { content: [{ text: 'z'.repeat(200) }] } }))
  assert.match(sections[0].text({}), /context_budget/)

  handler({}, ev('compaction/end', {}))
  assert.match(sections[0].text({}), /compaction_briefing/)
})

test('context_report tool returns ok with usage', async () => {
  const { ctx, tools } = makeMockCtx()
  sieve.apply(ctx, {})
  const report = tools.find((t) => t.name === 'context_report')
  const res = await report.execute({ full: false }, {})
  assert.equal(res.ok, true)
  assert.equal(typeof res.toolResults, 'number')
})

test('context_expand tool restores a trimmed chunk end-to-end', async () => {
  const { ctx, tools, handlers } = makeMockCtx()
  sieve.apply(ctx, { minKeepTokens: 20 })
  const expand = tools.find((t) => t.name === 'context_expand')
  const report = tools.find((t) => t.name === 'context_report')
  const handler = handlers.get('session/event')

  // seed the ledger that expand/report share (same ctx → same ledger)
  handler({}, ev('tool/result', { message: { content: [{ text: 'q'.repeat(200) }] } }))

  const handles = (await report.execute({ full: false }, {})).handles
  assert.ok(handles.length >= 1)

  const res = await expand.execute({ handle: handles[0] }, {})
  assert.equal(res.ok, true)
  assert.equal(res.text, 'q'.repeat(200), 'raw text restored through the handle')
})

test('context_expand tool rejects unknown handle', async () => {
  const { ctx, tools } = makeMockCtx()
  sieve.apply(ctx, {})
  const expand = tools.find((t) => t.name === 'context_expand')
  const res = await expand.execute({ handle: 'sieve#nope' }, {})
  assert.equal(res.ok, false)
})

test('context_evict tool frees tokens', async () => {
  const { ctx, tools, handlers } = makeMockCtx()
  sieve.apply(ctx, { caps: { ...DEFAULT_CAPS, toolResults: 20 } })
  const evict = tools.find((t) => t.name === 'context_evict')
  const handler = handlers.get('session/event')
  handler({}, ev('tool/result', { message: { content: [{ text: 'z'.repeat(200) }] } }))
  const res = await evict.execute({}, {})
  assert.equal(res.ok, true)
  assert.equal(typeof res.freedTokens, 'number')
  assert.ok(res.freedTokens > 0, 'evicting a raw chunk must reclaim its tokens')
})
