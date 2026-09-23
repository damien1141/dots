// test/core.test.mjs — pure-coverage: classifier, budget, ledger, extractor.
// No harness deps. Run: node --test test/*.test.mjs
import { test } from 'node:test'
import assert from 'node:assert/strict'

import { classify, estTokens, trimSketch } from '../lib/classify.mjs'
import { DEFAULT_CAPS, usageRows, overCap, totalTokens, loadFraction } from '../lib/budget.mjs'
import { createLedger } from '../lib/ledger.mjs'
import { extractEventText } from '../lib/extract.mjs'

function ev(type, data) { return { type, data } }

// ── classify ────────────────────────────────────────────────────────────────

test('classify keeps code blocks', () => {
  const r = classify('```js\nconst x = 1\n```')
  assert.equal(r.verdict, 'keep')
  assert.equal(r.reason, 'signal')
})

test('classify keeps error/stack lines', () => {
  assert.equal(classify('TypeError: x is not a function\n    at foo.js:4:2').verdict, 'keep')
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
  assert.equal(classify(rep).verdict, 'trim')
})

test('estTokens is stable (~4 chars/token)', () => {
  assert.equal(estTokens('abcd'), 1)
  assert.equal(estTokens('abcdefgh'), 2)
})

test('trimSketch keeps head+tail+collapse marker', () => {
  const lines = Array.from({ length: 50 }, (_, i) => `l${i}`).join('\n')
  const s = trimSketch(lines)
  assert.match(s, /l0/)
  assert.match(s, /\[\d+ lines collapsed\]/)
  assert.match(s, /l49/)
})

// ── budget ──────────────────────────────────────────────────────────────────

test('usageRows reports all categories with over flag', () => {
  const rows = usageRows({ toolResults: 13000, assistantText: 100, codeBlocks: 0, commands: 0 })
  const tr = rows.find((r) => r.category === 'toolResults')
  assert.equal(tr.over, true)
  assert.equal(rows.length, 4)
})

test('overCap lists only over-cap categories', () => {
  assert.deepEqual(overCap({ toolResults: 20000, assistantText: 0, codeBlocks: 0, commands: 0 }).map((o) => o.category), ['toolResults'])
})

test('loadFraction bounds 0..1', () => {
  assert.equal(loadFraction({ toolResults: 0, assistantText: 0, codeBlocks: 0, commands: 0 }), 0)
  assert.equal(loadFraction({ toolResults: DEFAULT_CAPS.toolResults, assistantText: DEFAULT_CAPS.assistantText, codeBlocks: DEFAULT_CAPS.codeBlocks, commands: DEFAULT_CAPS.commands }), 1)
})

test('totalTokens sums categories', () => {
  assert.equal(totalTokens({ toolResults: 10, assistantText: 20, codeBlocks: 30, commands: 40 }), 100)
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
  assert.equal(led.evictables().length, 1)
})

test('ledger.compact drops raw but keeps handle expandable', () => {
  const led = createLedger({})
  const rec = led.push({ type: 'assistant/message', category: 'assistantText', text: 'hello world\n'.repeat(20) })
  led.compact(0)
  const after = led.expand(rec.id)
  assert.equal(after.raw, null)
  assert.equal(after.id, rec.id)
})

test('ledger.clear resets usage and records', () => {
  const led = createLedger({})
  led.push({ type: 'tool/call', category: 'commands', text: 'npm install' })
  assert.ok(led.status().total > 0)
  led.clear()
  assert.equal(led.status().total, 0)
})

test('ledger.snapshot returns ordered retained records', () => {
  const led = createLedger({})
  led.push({ type: 'tool/call', category: 'commands', text: 'a' })
  led.push({ type: 'tool/result', category: 'toolResults', text: 'b' })
  assert.equal(led.snapshot().length, 2)
})

// ── extract ─────────────────────────────────────────────────────────────────

test('extractEventText pulls tool result text', () => {
  assert.equal(extractEventText(ev('tool/result', { message: { content: [{ text: 'result body' }] } })), 'result body')
})

test('extractEventText pulls tool call name+args', () => {
  assert.equal(extractEventText(ev('tool/call', { name: 'bash', arguments: '{"cmd":"ls"}' })), 'bash {"cmd":"ls"}')
})

test('extractEventText pulls assistant content', () => {
  assert.equal(extractEventText(ev('assistant/message', { content: [{ text: 'the answer' }] })), 'the answer')
})

test('extractEventText returns "" for unknown shapes', () => {
  assert.equal(extractEventText({ type: 'weird' }), '')
  assert.equal(extractEventText(null), '')
})
