# Rust Tooling Reference

## Format / lint / test

```bash
cargo fmt                 # format everything (subcommands: --check, --all)
cargo fmt --check         # CI mode: fail if unformatted
cargo clippy --all-targets --all-features -- -D warnings   # deny all warnings
cargo test                # unit + integration + doctests
cargo test -- --nocapture # show println! output
cargo test --doc          # doctests only
cargo nextest run         # faster, better-isolated runner (if installed)
```

## Build

```bash
cargo build               # debug
cargo build --release
cargo build --target x86_64-unknown-linux-musl   # static, portable binary
cargo check --all-targets # fast semantic check, no codegen
```

## Dependency management

```bash
cargo add serde --features derive    # prefer over hand-editing versions
cargo add --dev
cargo tree -d                      # duplicate dependency versions in the graph
cargo update -p serde              # update one crate
```

## Documentation

```bash
cargo doc --no-deps --open         # project docs, private items:
cargo doc --no-deps --document-private-items --open
# docs.rs/<crate> — ground truth for signatures
```

## Auditing

```bash
cargo install cargo-audit
cargo audit                # CVE check against Cargo.lock
cargo deny check           # licenses + advisories + bans (if configured)
cargo outdated             # dependency freshness (if installed)
```

## Fuzzing / coverage

```bash
cargo install cargo-fuzz
cargo fuzz init
cargo fuzz run <target> -- -max_total_time=60
# coverage:
cargo install cargo-llvm-cov
cargo llvm-cov --html
```

## Profiling

```bash
cargo install flamegraph
cargo flamegraph --bin <name>              # needs debug symbols — see `debug = true` in release
# perf: perf record -g ./target/release/<name>
```

## MSRV / edition

- Set `rust-version` in Cargo.toml — enforced by cargo.
- `cargo build` fails with a clear error below MSRV; don't hand-roll checks.
- Edition 2024 requires rustc ≥1.85. Match the workspace; don't churn editions.

## CI ordering (one-liner)

```bash
cargo fmt --check && cargo clippy --all-targets --all-features -- -D warnings && cargo test --all-features && cargo audit
```