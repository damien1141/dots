# Tool plugin reference

A tool is a model-facing capability registered on `ctx.tools`; its schema joins system-prompt assembly automatically. This reference is self-contained: write the plugin from here alone. `packages/bash/tool-bash` is the production-grade three-package example.

## The shape

```ts
import { readFile } from 'node:fs/promises'
import type { Context } from 'cordis'
import { defineTool } from '@deepseek-ai/dsh-tools'

export const name = 'my-tool'
export const inject = ['tools']

export function apply(ctx: Context) {
  ctx.tools.register(defineTool({
    name: 'read_file',
    description: 'Read a file from disk.',
    parameters: {
      path: { type: 'string', required: true, description: 'Absolute path' },
      limit: { type: 'number' },
    },
    output: {
      schema: {
        type: 'string',
      },
      render: (_args, value) => [{ type: 'text', text: value }],
    },
    async execute(args, exec) {
      return readFile(args.path, { encoding: 'utf8', signal: exec.signal })
    },
  }))
}
```

Raw JSON-Schema `ToolDefinition`s are also accepted directly (that is how MCP-sourced tools arrive); `defineTool` is the typed helper that validates `arguments` against the unified parameter schema before `execute` runs and types `execute` from it.

## The value schema DSL — rules that bite (read before writing schemas)

The `output.schema` uses a cordis-specific DSL compiled by `@deepseek-ai/dsh-tools`. It is NOT standard JSON Schema. These are the hard rules enforced by the compiler:

### Rule 1 — `additionalProperties: false` is mandatory on every `type: "object"` schema

Every object schema must declare `additionalProperties: false`. This applies at every nesting level.

```ts
// Correct — root object needs it
output: {
  schema: {
    type: 'object',
    additionalProperties: false,    // <-- required
    properties: {
      name: { type: 'string' },
      nested: {
        type: 'object',
        additionalProperties: false,  // <-- also required on nested objects
        properties: { value: { type: 'integer' } },
      },
    },
  },
}

// Wrong — DSL rejects at compile time: "schema.additionalProperties must be explicitly true or false"
output: {
  schema: {
    type: 'object',
    properties: { name: { type: 'string' } },  // missing additionalProperties on root
  },
}
```

### Rule 2 — No union types in `type`; use `oneOf` for nullable

```ts
// Correct — oneOf for nullable
anchor: { oneOf: [{ type: 'null' }, { type: 'string' }] }

// Correct — oneOf for optional object
result: {
  oneOf: [
    { type: 'null' },
    {
      type: 'object',
      additionalProperties: false,
      properties: { id: { type: 'string' } },
    },
  ],
}

// Wrong — causes "type must be string/number/integer/boolean/null/array/object/json, or use oneOf"
anchor: { type: ['string', 'null'] }
```

### Rule 3 — Array schemas take `items`, not `additionalProperties`

```ts
// Correct
errors: { type: 'array', items: { type: 'string' } }

// Wrong — arrays do not accept additionalProperties
errors: { type: 'array', additionalProperties: false, items: { type: 'string' } }
```

### Rule 4 — Only one `type` value per schema

Supported: `'string'`, `'number'`, `'integer'`, `'boolean'`, `'null'`, `'array'`, `'object'`, `'json'`. For unions, wrap in `oneOf`.

### Full working output schema template

```ts
output: {
  schema: {
    type: 'object',
    additionalProperties: false,
    properties: {
      field_a: { type: 'string', required: true },
      field_b: { type: 'integer' },
      field_c: { type: 'boolean' },
      field_d: { type: 'number' },
      field_e: { type: 'null' },
      // nullable: use oneOf
      field_f: { oneOf: [{ type: 'null' }, { type: 'string' }] },
      // optional object via oneOf
      field_g: {
        oneOf: [
          { type: 'null' },
          {
            type: 'object',
            additionalProperties: false,
            properties: { id: { type: 'string', required: true } },
          },
        ],
      },
      // array of scalars
      field_h: { type: 'array', items: { type: 'string' } },
      // array of objects
      field_i: {
        type: 'array',
        items: {
          type: 'object',
          additionalProperties: false,
          properties: {
            file: { type: 'string', required: true },
            line: { type: 'integer', required: true },
          },
        },
      },
      // enum
      status: { type: 'string', enum: ['idle', 'running', 'done'] },
    },
  },
  render: (_args, value) => [{ type: 'text', text: '...' }],
},
```

### Verify schema before the harness boots

Schema errors surface immediately at import time via `defineTool`'s constructor. Run this after any schema change:

```sh
node --input-type=module -e "await import('./packages/util/<pkg>/index.mjs')"
```

If the schema is invalid, Node throws before the harness even starts — look for `JsonSchemaError` in the output.

## The execute() contract

- **Args are validated for you.** `defineTool` validates model-generated `arguments` (types, required keys, literal constraints, exact-one unions, and nested values) before `execute` runs, so inside `execute` the args match the inferred type. Still hand-check constraints the DSL does not express: non-empty strings, positive numbers, cross-field rules. Raw JSON-Schema tools registered directly own their input validation.
- **Registration borrows your readonly definition.** Do not mutate the schema or replace callbacks after registration; to hot-swap a tool, dispose its owning effect and register the replacement. Mutable state inside the callback's closure remains ordinary plugin state.
- **Execution identity is protected.** The registry materializes `arguments` as detached lossless JSON, freezes it before policy starts, and assigns an opaque `exec.token`; `callId`, `name`, `arguments`, `agent`, `token`, the required caller-owned `signal`, and an optional enclosing-transport `parent` token stay immutable through dispatch. Treat `args` as readonly input. Only an around-dispatch wrapper receives a mutable view, and it may replace and restore the required `exec.signal` to impose a deadline but cannot remove it.
- **Declare and return one canonical JSON value.** `output.schema` uses a value schema with an object, array, scalar, or null root; `execute` returns only the inferred value; the registry snapshots it as lossless JSON, validates it, freezes it, and passes it to `output.render(args, value)`. Do not return content blocks from the body or make callers parse prose for ids and fields.
- **Throwing or returning an invalid value means `isError`.** The registry catches throws and contains schema, renderer, metadata-projector, and lossless-JSON failures before observers run. Throw for infrastructure failures; represent a successful domain outcome in the canonical value even when its renderer explains a non-ideal state, such as a non-zero process exit.
- **Honor `exec.signal`.** Cancel in-flight work when it fires.
- **Project durable card data with `output.presentationMeta` (optional).** It derives replayable JSON from the same canonical value; the core persists it on `tool/result` and hands it to `presentResult`, so a card that needs result-time facts survives replay without persisting the canonical value.
- **Use `exec.agent` for async notifications.** `agent.inject({ content, source: { kind: 'plugin', plugin: '<name>' } })` appends durable context the NEXT model request sees — it is not a wake-up (an idle agent stays idle). Guard against disposed agents with try/catch.

## Long-running work

Gate `run_in_background` with producer config, then register through `ctx.tasks.start({ kind, label, owner: exec.agent, run })`. The registry rejects a pre-aborted invocation before the producer body; the runtime validates ownership and control-surface availability before `run()` starts work, then supplies the id, session fence, generic control tools, notices, and owner cleanup. A successful background branch returns a typed canonical handle such as `{ kind: 'background', taskId }`; its renderer may keep human prose, but Code Mode must never parse that prose to recover the id. The producer supplies synchronous `cancel`, non-rejecting `done` that settles after resource cleanup, and optional consuming `readOutput` with bounded-output formatting. Once `ctx.tasks.start()` publishes the id, use a task-owned cancellation signal rather than `exec.signal`: later outer-call cancellation stops waiting for the call but does not kill published work; `task_kill`, owner disposal, and service teardown own that lifetime. Foreground work remains coupled to `exec.signal`.

## Policy and observation

Prefer not to build deployment policy into the tool. Selection rule: `tools/pre-execute` for extensible allow/deny/ask policy (return a typed decision; `ask` resolves through `ctx.approval` as a one-shot prompt, and an absent or unanswerable approval denies), `ctx.tools.guard()` for a final monotonic deny that later listeners cannot undo, `tools/execute` to wrap dispatch with a deadline, retry, or metrics collection, `tools/post-execute` to replace presentation content or the returned value, block the result, or attach model-facing context, and `tools/result` to observe the immutable normalized outcome. A content replacement leaves programmatic access to the canonical `value` intact; confidentiality policy blocks or replaces the value. Order of execution: `tools/pre-execute` waterfall first, monotonic guards next, then the `tools/execute` and `tools/post-execute` waterfalls; definition-owned `finalizeContent` and `tools/result` run afterward.

## UI rendering

UI cards are a separate concern from the model result, declared through pure presentation projections: `presentCall(args)` returns the pending card and `presentResult(args, { content, isError, meta? })` the completed card. A tool with no UI presentation falls back to a generic card (title = tool name, raw args as input). Card kinds:

- `{ card: 'generic', title, kind?, rawInput?, content?, locations? }` — the default. Set `kind` for an icon (`read`/`search`/...); set `locations: [{ path, line? }]` for any file the tool touches so an editor can follow along.
- `{ card: 'terminal', title, description?, cwd? }` — the call IS a shell command; `title` is the command.
- `{ card: 'diff', title, diffs, locations? }` — the call creates or modifies a file; `diffs: [{ path, oldText, newText }]` with `oldText: null` for a new file renders as an inline diff.
- `search` — a completed discovery result reconstructed from persisted `result.meta`: grouped-by-file matches (`shape: 'matches'`) or a flat path list (`shape: 'paths'`), plus `truncated`/`total` so a UI never presents a capped result as complete. There is no `search` call view; a discovery call's pending state stays a generic card.
- `web` — a completed web retrieval, discriminated by `kind: 'search' | 'fetch'`, derived from `result.meta`; it carries no body copy.

Hard rules (they bite if broken):

- **Purity.** These run on live streaming AND on session-log REPLAY, so they must be pure functions of `args` (+ the result) — NO I/O, NO reading session state, NO clock/random. A diff is derived from the args; the UI adapter, not the tool, supplies session context.
- **UI-only formatting stays out of the model result.** A fenced `console` block, a diff, a relativized path — none of these belongs in the canonical value or Native content merely to serve a UI. `output.render` owns model-facing prose; `presentationMeta` plus the card presenters own replayable UI state.
- **`defineTool` soft-validates the display path.** Malformed or older logged arguments make the wrapper return `undefined` (a generic fallback) rather than throw — display must never crash a replay.

The neutral vocabulary lives in `dsh-tools`; tools never import a UI or transport type. `dsh-tool-fs` (generic/diff) and `dsh-tool-bash` (terminal) are the reference implementations.

## Code Mode

In Code Mode, every visible registered tool is available as `await tools.<name>(args)` without extra integration. The generated `ToolArgsMap` and `ToolOutputMap` derive exact argument and canonical-return types from the same schemas, and calls re-enter the normal execution pipeline. A successful call resolves to the final canonical JSON value after policy, not to rendered Native content; a failed call rejects with the real `ToolCallError`, whose programs may inspect only `name`, `toolName`, and human-readable `message`. Design `output.schema` as a useful programmatic API: return handles and fields directly, allow scalar/array/null roots when they are the honest value, and keep human explanation in `output.render`.

## Verification

Unit tests for the execute and render logic; a REAL-composition test that boots the plugin through `cordis.yml` for a product-visible tool; the per-file 100% coverage gate for the package source; a keyless snapshot in the same change when the tool changes model-visible behavior (prompt schema, tool output) or UI-visible behavior (cards).
