---
name: dsh-write-plugin
description: Use when asked to create a plugin or workspace package in the deepseek-harness repo, from scaffolding through verification, or to decide which plugin shape fits a requested capability. Routes tool, LLM adapter, hook, service, and config shapes to their reference files.
---

# Writing a DeepSeek Harness Plugin

Create one plugin as one workspace package under `packages/<group>/<pkg>`. Classify the shape first, read its reference file, walk the package checklist below, then verify with the smallest gates that cover the change. This skill is self-contained: every rule it needs is written here or in its reference files.

## Classify the plugin shape first

| Requested capability | Shape | Reference file |
|---|---|---|
| A model-facing tool: read/write files, run commands, search the web | Tool plugin | `references/tool-plugin.md` |
| A new model provider | LLM adapter plugin | `references/llm-adapter-plugin.md` |
| Intercept requests, tools, or turns: permission, policy, metrics, telemetry | Hook plugin | `references/hook-plugin.md` |
| A capability other plugins consume through `ctx` | Service plugin | `references/service-plugin.md` |
| User-configurable behavior through `cordis.yml` | Config plugin | `references/config-plugin.md` |

A plugin combines shapes freely (a tool plugin with Config, a service that also registers a tool); each shape's contracts still apply. When the request matches none of the five shapes, map it to an extension point and write a plugin that registers there; never change the agent loop itself.

| Goal | Mechanism |
|---|---|
| Add a model-facing capability | register on `ctx.tools` |
| Add a model provider | register an adapter on `ctx.llm` |
| Give one session a different capability set | compose it in an agent preset |
| Add shell execution | implement and register a `ctx.bash` backend |
| Add persistent terminal execution | register a `ctx.pty` backend plus `dsh-tool-pty` |
| Add a human command | register on `ctx.commands` |
| Add background work | register on `ctx.tasks` |
| Add filesystem access or policy | implement a `ctx.fs` provider or listen to `fs/*` policy events |
| Confine spawned processes | use a `ctx.sandbox` backend |
| Intercept a request, tool, or turn | use `agent/*` or `tools/*` events; `agent/turn-stopping` is the event that stops a turn |
| Add model-facing context | call `agent.inject()` |
| Add UI or editor integration | drive `ctx.agents` and render from `session/event` |
| Web Client Chat node | register a `ConversationNodeDefinition` plus a keyed renderer |
| Add durable session state | extend `SessionEventMap`; render and replay from the log |
| Fork a live session | call `ctx.sessions.fork(source, boundary?, childSessionId?)` |
| Scope a registration to one agent | use its `agent.ctx` |

## The package checklist

There are two supported development paths:

**A. Repository packages** (published, versioned with the harness):

1. **Create the package** — `packages/<group>/<pkg>/` with `package.json`, `tsconfig.json`, `src/index.ts`, and `README.md`. Copy `package.json` from `packages/core/tools` and adjust name, description, and dependencies; keep its invariants: `private: true`, a `version` matching root, `type: module`, `main: "lib/index.js"`, `types: "lib/types/index.d.ts"`, `exports["."]` with `types` and `default` pointing into `lib`, `cordis` in both peer and dev dependencies with the same range, every dsh peer dependency mirrored in dev, `schemastery` in `dependencies` (it is a runtime validator), and a `files` list containing exactly `lib/index.js`, `lib/invariant.js`, `lib/types/**/*.d.ts`, and package-specific runtime artifacts; a CLI app package with a `bin` includes `lib/bin.js` immediately after `lib/index.js`. Do not publish `src`, declaration maps, JS maps, or stale root declaration files. In-package relative imports use explicit `.ts` specifiers in source (the compiler rewrites them to `.js` in emitted JS). Pick an existing group when one matches the role (`core`, `llm`, `bash`, `compact`, `subagent`, `todo`, `session-persistence`, `ui`, `util`, `support`); a new group is allowed but is a pure container — no `package.json`, no source files, and packages sit exactly one level below it.

**B. Local profile plugins** (unpublished, live under `~/.dsh/profiles/<profile>/packages/`):

1. **Create the package directory** — `~/.dsh/profiles/<profile>/packages/<group>/<pkg>/`.
2. **`package.json`** — use the memento pattern (plain JS, no build step):
   ```json
   {
     "name": "@local/dsh-util-<pkg>",
     "version": "0.0.0",
     "private": true,
     "type": "module",
     "main": "index.mjs"
   }
   ```
3. **Source file** — write `index.mjs` (plain ESM, not TypeScript). No `tsconfig.json`, no `src/`, no `lib/`. The file must export:
   ```js
   export const name = 'util-<pkg>';
   export const inject = ['tools'];        // or ['tools', 'fs'] etc.
   export function apply(ctx) { ... }
   ```
4. **`inject`** must name every cordis service the plugin uses. Common values: `['tools']`, `['tools', 'fs']`, `['tools', 'llm']`. Omitting a required service causes silent failure — the service won't be available in `ctx`.
5. **Register in `cordis.patch.yml`** — add an entry under the top-level `packages:` array:
   ```yaml
   packages:
     - path: ./packages/<group>/<pkg>
       id: util-<pkg>
   ```
6. **Run `pnpm install`** in the profile root to register the workspace.
7. **Verify the schema** before booting:
   ```sh
   node --input-type=module -e "await import('@local/dsh-util-<pkg>')" 2>&1
   ```
   A schema error surfaces immediately on import via `defineTool`'s constructor — before the harness boots.

2. **Register it in the root configs** — add `{ "path": "./packages/<group>/<pkg>" }` to the `references` of `tsconfig.host.json` (Host package) or `tsconfig.client.json` (Client package): an ordinary package belongs to exactly one aggregate, never both; the `api/remotes` split is a repository-specific exception, not a template for new packages. Touch `knip.json` only when the package has entrypoints that repository discovery does not already cover. A `packages/client/*` package instead extends `tsconfig.base.client.json`, declares `dsh.client` in package.json, exports `./client`, and calls the shared client tsdown preset (`packages/client/tsdown.client.ts`). Covered automatically by globs or package-manifest discovery — no edits needed: root `package.json` workspaces, `scripts/publint-all.ts`, `tsdown.config.ts`, `.oxlintrc.json`, `scripts/check-workspace-constraints.ts`.

3. **Decide the package topology** — for a swappable capability, separate Service Definition / Service provider / Consumer roles into packages when they evolve independently (the bash trio is the template); a single-purpose plugin stays one package.

4. **Write the package README** — keep package-specific service API, config, events, extension points, and design notes first. End the README with the canonical Model Experience sequence and the Known Limitations and Deferred Work section. Fill Model Experience from the implementation: one H3 per direct, conditional, capped, lifetime, or auxiliary-model surface, with the three ordered H4 fields below and one prose paragraph under each; quote stable text owned by the package; a tool-schema surface states only deltas absent from the generated tool catalog. In `KV Cache effect`, distinguish append-only growth, a stable repeated prefix, replacement of earlier request tokens, and an independent model request, then name the package-owned changes that can invalidate reuse; "does not invalidate" means the package preserves an already-reusable prefix. A package with no context effect uses the audited `None` or `Indirectly, through ...` sentence forms; a model-agnostic generic package may join the `NO_MODEL_EXPERIENCE_SECTION` allowlist.

   ````markdown
   ## Model Experience

   ### Request surface and condition

   #### What the model sees

   The exact data-dependent fields, an anchored generated-catalog link, or an introduction to the verbatim literal below.

   ##### Verbatim text for this field, when needed

   ```markdown
   Stable system-prompt prose of any length, or another long non-generated literal, copied exactly from source.
   ```

   #### Token effect

   Fixed, conditional, retained, replaced, capped, or zero-direct token effect.

   #### KV Cache effect

   Append-only, prefix-stable, replacing, or independent behavior, including the exact conditions that may invalidate reuse.

   ## Known Limitations and Deferred Work

   - **Consumer-visible gap** — exact missing operation or case, its consequence, and any maintainer constraint.
   ````

5. **Verify** — run the verify block below, then the behavior-specific checks and coverage the change needs.

## While writing

- Every registration is an effect: register through `ctx` helpers or `ctx.effect()` with a disposer, and let plugin unload clean everything up — event listeners, tools, and timers included.
- New behavior goes on a documented extension point; nothing here changes `agent-loop`.
- Public service methods and typed events carry JSDoc with `@param`/`@returns`; typed events use declaration merging on the `cordis` `Events` interface and document their dispatch `@mode`.
- No hardcoded tunables: deployment-varying values are validated `Config` fields changeable from `cordis.yml`.
- Anything a model sees must be reconstructable from the session log.
- Misconfiguration fails loud: never silently skip a missing referent; validate at parser/config, wire, and process boundaries rather than trusting typed same-process callers.

## Verification

```sh
pnpm install            # registers the workspace
pnpm run doc-sync
pnpm run constraints && pnpm run typecheck && pnpm run lint
pnpm run build && pnpm run hygiene
```

Choose tests by change surface: unit tests for logic, the per-file 100% coverage gate for package source, real-API e2e (with a provider key) for provider behavior, keyless snapshots for any model-, protocol-, or human-visible behavior, and a REAL-composition test (booting `cordis.yml` through the Loader) for product-visible plugins — see `references` of this skill for each shape's specifics. A package `bin` entry additionally needs a built-artifact smoke running `lib/bin.js` under plain Node.

## The value schema DSL — rules that bite

The `output.schema` field in `defineTool` uses a cordis-specific DSL compiled by `@deepseek-ai/dsh-tools`. It is NOT standard JSON Schema. These are the exact rules enforced by `assertAuthorKeys` in `dsh-tools/lib/index.js`:

### Rule 1 — `additionalProperties: false` is mandatory on every `type: "object"` schema

The DSL requires every object schema to declare `additionalProperties: false`. This must appear at every nesting level.

```js
// Correct
output: {
  schema: {
    type: 'object',
    additionalProperties: false,
    properties: {
      name: { type: 'string' },
      nested: {
        type: 'object',        // <-- requires additionalProperties: false
        additionalProperties: false,
        properties: { value: { type: 'integer' } },
      },
    },
  },
}

// Wrong — DSL rejects this at compile time
output: {
  schema: {
    type: 'object',
    properties: {
      name: { type: 'string', additionalProperties: false }, // additionalProperties is ONLY valid on object-type schemas, not primitives
    },
  },
}
```

**Anti-pattern:** placing `additionalProperties: false` on a primitive field (`{ type: 'string', additionalProperties: false }`). This causes `"schema.properties.name.additionalProperties is not supported by the value schema DSL"`.

### Rule 2 — No union types in `type`

The DSL does not support `type: ['string', 'null']`. Use `oneOf` instead:

```js
// Correct — use oneOf for nullable fields
anchor: { oneOf: [{ type: 'null' }, { type: 'string' }] }

// Correct — use oneOf for optional object fields
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

// Wrong — causes "schema.properties.anchor.type must be string/number/integer/boolean/null/array/object/json, or use oneOf"
anchor: { type: ['string', 'null'] }
```

### Rule 3 — Only one `type` value per schema

Each property must have exactly one scalar type or be wrapped in `oneOf` for unions. Supported types: `'string'`, `'number'`, `'integer'`, `'boolean'`, `'null'`, `'array'`, `'object'`, `'json'`.

### Rule 4 — Array schemas take `items`, not `additionalProperties`

```js
// Correct
errors: { type: 'array', items: { type: 'string' } }

// Wrong — arrays do not accept additionalProperties
errors: { type: 'array', additionalProperties: false, items: { type: 'string' } }
```

### Rule 5 — `required` is per-property, not per-schema

```js
// Correct — required is a property sibling
properties: {
  id: { type: 'string', required: true },
  name: { type: 'string' },  // optional
},
```

### Rule 6 — Use `oneOf` for exact-one discriminated unions

```js
status: {
  oneOf: [
    { type: 'object', additionalProperties: false, properties: { kind: { type: 'string', const: 'ok' }, value: { type: 'string' } } },
    { type: 'object', additionalProperties: false, properties: { kind: { type: 'string', const: 'error' }, message: { type: 'string' } } },
  ],
},
```

### Full working output schema template

```js
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
      // optional object with oneOf
      field_g: {
        oneOf: [
          { type: 'null' },
          {
            type: 'object',
            additionalProperties: false,
            properties: {
              id: { type: 'string', required: true },
            },
          },
        ],
      },
      // array
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

### Diagnostic command — verify schema locally before the harness boots

```sh
node --input-type=module -e "
import { readFile } from 'node:fs/promises';
const src = await readFile('packages/util/<pkg>/index.mjs', 'utf8');
// Try importing — schema errors surface immediately on import
await import('./packages/util/<pkg>/index.mjs');
console.log('Schema valid');
"
```

A schema error surfaces at import time via `defineTool`'s constructor, before the harness boots. Run this after every schema change.
