# Errors Track — Fallback When ast-grep Is Unavailable

**Graceful degradation** — if `ast-grep` (packaged as `ast-grep` or `sg`) is not
installed, fall back to the per-pattern flow: read the `REFERENCE-{js,python,go,
rust}.md` files (each links its patterns to the rule `.yml`) and run the
individual `sg -p '<pattern>' --lang <lang>` commands by hand. Prefer the repo's
own `errcheck`/`staticcheck` (Go) or `cargo clippy` (Rust) when configured — the
rule project surfaces what those linters would catch, it does not replace them.
