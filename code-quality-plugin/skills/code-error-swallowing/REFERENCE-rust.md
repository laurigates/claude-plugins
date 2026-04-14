# Reference — Rust Error Swallowing

Rust's `Result` and `#[must_use]` make the compiler a first line of defense.
This skill's job is to find the *runtime* suppressions — the places where
`.ok()`, `let _ =`, and friends discard errors deliberately. Prefer
`cargo clippy` with the relevant lints enabled when available.

## Patterns

| ID | Pattern | Default severity |
|----|---------|------------------|
| `rs-let-underscore-result` | `let _ = <expr>;` where expr is `Result` | Medium |
| `rs-ok-discard` | `<expr>.ok();` as a statement | Medium |
| `rs-unwrap-or-default-on-err` | `<expr>.unwrap_or_default()` on an error that should be surfaced | Medium |
| `rs-map-err-empty` | `.map_err(\|_\| ())` / `.map_err(\|_\| Default::default())` | Medium |
| `rs-match-err-empty` | `match x { Ok(v) => v, Err(_) => Default::default() }` | Medium |
| `rs-ignore-closure-result` | `.ok().or(None)` chain that forgets error | Medium |
| `rs-io-result-drop` | `writeln!(f, "...").ok();` | Medium |

### ast-grep commands

```bash
sg -p 'let _ = $EXPR;' --lang rust
sg -p '$EXPR.ok();' --lang rust
sg -p '$EXPR.map_err(|_| $$)' --lang rust
```

Better: run `cargo clippy -- -W clippy::let_underscore_must_use -W clippy::unused_io_amount`.

## Allowlist (classify as Low)

| Pattern | Why |
|---------|-----|
| `let _: () = <expr>;` — explicit unit binding to assert expression shape | Not a Result |
| `let _ = tx.send(msg);` on a `mpsc::Sender` where receiver drop is expected | Channel close semantics |
| `drop(<guard>)` or `let _ = <guard>;` on RAII guards (locks, spans) | Intentional lifetime extension |
| `.unwrap_or_default()` on an `Option<String>` in display code | Option, not Result |
| Inside a `Drop` impl | Panicking in Drop is worse than swallowing |

## Severity promotion

Promote to **High** when discarded Result comes from:

- `std::fs::write`, `fs::remove_file` (non-temp), `OpenOptions::write`
- Any `sqlx::*`, `diesel::*`, `sea_orm::*` mutating op
- `reqwest::Client::post` / `put` / `delete`
- Cryptographic ops: `signature::sign`, `decrypt_*`, key loading
- `Command::status` / `output` for deploy/publish binaries

## Remediation templates

### Library — propagate with `?`

```rust
// Before
let _ = do_thing();

// After
do_thing()?;
```

### Binary / CLI — log + exit

```rust
// Before
let _ = cleanup();

// After
if let Err(err) = cleanup() {
    eprintln!("warn: cleanup failed: {err}"); // TODO(error-swallowing): review wording
    std::process::exit(1);
}
```

### Fallback value with log

```rust
// Before
let value = parse(s).unwrap_or_default();

// After
let value = parse(s).unwrap_or_else(|err| {
    tracing::warn!(?err, "parse failed, using default");
    Default::default()
});
```

## Clippy lints to recommend

When repository has `Cargo.toml` but missing these lints, recommend enabling:

```toml
[lints.clippy]
let_underscore_must_use = "warn"
unused_io_amount = "warn"
unwrap_used = "warn"       # stricter; opt-in
expect_used = "warn"       # stricter; opt-in
```

Also in the source:

```rust
#![warn(unused_must_use)]
```

## Framework-specific notes

### Tokio

- `tokio::spawn(async { ... })` returning a `JoinHandle` that's never
  awaited nor given a handler is a floating task — **Medium** unless
  explicitly annotated as fire-and-forget.

### Axum / Actix

- A handler `match` that returns `StatusCode::OK` on an `Err` arm is
  **High**.
