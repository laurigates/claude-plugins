---
name: cli-smoke-recipes
description: |
  Advisory pattern for exposing pure-function modules via CLI subcommands
  and a bulk-smoke justfile recipe. Applies to decoders, codecs, parsers,
  validators, formatters, compilers, transpilers — any module with an
  input-to-output contract. Use when designing a new module that
  transforms data, when adding CLI access to an existing library, when
  authoring smoke recipes that iterate every shipped input, or when
  deciding whether a feature can advance past "in progress" without its
  CLI surface.
allowed-tools: Read, Grep, Glob, TodoWrite
model: sonnet
created: 2026-04-24
modified: 2026-05-04
reviewed: 2026-04-24
---

# CLI Smoke Recipes

Every pure-function module that transforms data should be reachable from the shell plus a bulk-smoke recipe that iterates every shipped input. Applies to decoders, codecs, parsers, validators, formatters, compilers, transpilers, linters.

## When to Use This Skill

| Use this skill when… | Skip when… |
|---------------------|------------|
| Designing a new module with a clear input → output contract | Internal helper with no stable interface |
| Adding CLI exposure to an existing library | Code whose only consumer is another in-process module |
| Authoring justfile recipes for bulk verification | One-off scripts |
| Deciding if a feature is complete | Implementation is purely experimental |

## The Pattern

### 1. CLI exposure

Each transforming module is callable via `<bin> <module> <subcmd>`:

| Operation | Pattern | Required? |
|-----------|---------|-----------|
| `info` | Pure reader; prints headers / metadata | Yes |
| `decode` / `parse` | Source → output format | Yes if the module consumes |
| `encode` / `render` | Output → source format | Yes if the module produces |
| `identify` / `validate` | Classify / verify without full parse | Optional but cheap |

The subcommand is a shell entry point, not a new abstraction. It uses
the module's existing functions — never a re-implementation.

### 2. Stdout-first

Reader subcommands default to **streaming to stdout** when the
destination argument is omitted. This makes them pipe-friendly:

```bash
mytool codec info foo.bin | head -20
mytool codec decode foo.bin | jq .header
mytool codec decode foo.bin | cmp - expected.raw
```

Errors go to **stderr**, so stdout stays a clean data stream. Exit
codes follow standard conventions (0 success, non-zero failure). Do
not print decorative banners to stdout in reader commands.

### 3. Module purity

CLI paths keep module dependencies minimal. In practice: a codec
module's CLI entrypoint should not import the application's UI /
framework layer. The test:

> Can the CLI run in a headless, framework-free environment (CI
> sandbox, bare container, a naked shell)?

If yes, the module is pure enough. If no, the module has a UI
dependency that belongs somewhere else. Prune the import.

### 4. Justfile wrapper per subcommand

One recipe per subcommand, names: `<module>-<subcmd>`:

```just
codec-info path:
    @just build
    ./build/mytool codec info {{path}}

codec-decode path:
    @just build
    ./build/mytool codec decode {{path}}
```

The recipe declares `build` as a prerequisite so stale binaries never
hide bugs. Paths resolve against a workspace variable like
`GAME_ROOT` / `DATA_DIR` / `FIXTURE_DIR` so they work across machines
and in CI.

### 5. Bulk smoke recipe

Per module, one `<module>-smoke` recipe that iterates every shipped
instance of the input format and prints a one-line summary per input:

```just
codec-smoke:
    @just build
    for f in $(fd -e bin . "$DATA_DIR/codec"); do \
        printf "%-40s " "$(basename $f)"; \
        ./build/mytool codec info "$f" | head -1; \
    done
```

The bulk recipe catches correctness properties that per-file runs miss:

- "All N shipped inputs identify as the expected format" — catches
  format drift.
- "Round-trip against input X is byte-identical" — catches
  encode-vs-decode asymmetry.
- "Parser never crashes on any shipped input" — catches the most
  embarrassing class of bug.

### 6. Same-commit landing

CLI, justfile recipe, and module code ship in **one commit**. If the
CLI or recipe is deferred to a follow-up, the feature tracker does not
advance past "in progress." This is the same discipline as
`.claude/rules/docs-currency.md` applied to the manual-verification
surface instead of the docs.

## Detection Heuristic

Before applying the pattern, confirm the module qualifies:

| Signal | Indicates |
|--------|-----------|
| Module has a pure transformation function | Pattern applies |
| Input / output are serialisable (bytes, text, JSON) | Pattern applies |
| Module needs UI / framework context to run | Pattern does **not** apply — refactor first |
| Module is a one-off migration script | Pattern does not apply |

## Quick Reference

### Checklist for new transforming module

- [ ] `info` subcommand exposed
- [ ] `decode` / `parse` streams to stdout by default
- [ ] Errors go to stderr
- [ ] Module import graph excludes UI / framework layer
- [ ] One justfile recipe per subcommand, `build` prerequisite declared
- [ ] `<module>-smoke` iterates every shipped input
- [ ] CLI + recipes + module land in the same commit

### Common Mistakes

| Mistake | Correct Approach |
|---------|-----------------|
| Decorative banners on stdout | Stderr only; stdout is data |
| Running bulk smoke on "representative" inputs | Bulk smoke iterates **every** shipped input |
| CLI imports the UI layer | Refactor; keep CLI path headless |
| Deferring the smoke recipe to a follow-up | Same-commit or tracker does not advance |
| Hard-coded absolute paths in recipes | Resolve against a workspace variable |

## Related

- `tools-plugin:justfile-expert` — recipe-authoring mechanics
- `.claude/rules/docs-currency.md` — the same-commit principle this skill mirrors
- `blueprint-plugin:blueprint-docs-currency` — the docs-side counterpart
- `agent-patterns-plugin:parallel-agent-dispatch` — smoke recipes are the gate between waves in multi-wave dispatches

> Evidence: the manual-verification surface is the last line of defence
> before gameplay / real traffic / integration tests exist. Smoke recipes
> shipped in the same commit as a decoder module caught encoding
> consistency and round-trip byte-identity on first run — manual
> exercise had never caught either.
