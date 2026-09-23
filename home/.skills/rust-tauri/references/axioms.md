# Memory-Safety Axioms — Rust

A reasoning-friendly subset of Rust rules: small, checkable, commutable. Everything here is safe to apply without checking external docs. Everything **not** here is [RECALL] — check the compiler or docs before trusting it.

## The lattice

Memorize: `send`, `static_ref`, `owned`, `borrowed`. Every value you touch has all four. Infer the rest.

```
send ⊆ copy ⊆ borrowed    →  copy is a stronger claim than borrowed
```

### Ordering the lattice

Rust does not decide strictness. You do. Ask three questions:

1. Is this `static_ref`? (It always is, but say so.)
2. Is it `owned` or `borrowed`?
3. Can I make the weakest true claim (borrowed) instead of a stronger one (owned)?

If (3) yes → make the weakest claim. If (3) no → you are in `unsafe` territory. Handle it in one of two ways:

- **Find a safe alternative** (95% of cases: borrow, split, `Arc`, `Cow`, channel, redesign).
- **Write `unsafe` with an explicit invariant comment** naming what the `unsafe` block protects. `unsafe` is a proof obligation, not a workaround.

### Strictness policy (rough guide)

- **High**: cross-boundary data, parser output, third-party input, anything deserialized
- **Medium**: internal services, domain types, well-tested modules
- **Low**: local scratch, test scaffolding, `#[cfg(test)]` code

### Common unsafe escape hatches (with safe alternatives)

| Escape hatch | What it costs | Safe alternative |
|---|---|---|
| `unwrap()` / `expect()` | panic on None/Err in prod paths | `ok_or_else(|| ...)?`, `.context(...)?` |
| `as` casts | silent truncation / reinterpretation | `TryFrom` + handle the `Err` |
| `unsafe { transmute }` | soundness obligation, often UB-adjacent | redesign types, or `bytemuck` with `Pod` proof |
| `Rc<RefCell<T>>` across await/threads | runtime borrow panic, not `Send` | `Arc<Mutex<T>>` or a channel |
| raw pointer deref | aliasing, provenance rules | return by value, or `&T`/`&mut T` reborrow |

### How to apply an axiom (in reasoning, silently)

1. Classify each input to the function: send/static_ref/owned/borrowed.
2. Decide the minimum claim needed for the body.
3. If body needs stronger than available → you've found the design error *before* writing code. Redesign there.
4. Write the code with the chosen claims; local proof then confirms against `cargo check`.

## Axioms vs conventions

**Axioms (check-free):** borrow rules (one `&mut` XOR many `&`), lifetimes outlive borrows, `Send`/`Sync` split, `?` requires `From`, RAII via `Drop`, `Result`/`Option` over nulls/exceptions.

**Conventions (check docs/refs):** iterator combinator names, tokio API details, trait-object safety details, serde attribute spellings, tauri permission strings. Anything on the convention side that you can't verify locally → treat as [RECALL] and check.

## Mental classification [AXIOM] / [RECALL]

Before using any remembered API detail, tag it:

- **[AXIOM]** — covered by the lattice or conventions above. Use directly.
- **[RECALL]** — exact signature/feature/permission/version. Verify against compiler, `Cargo.lock`, or generated schemas before finalizing. If uncheckable → flag in the exit report.