---
created: 2026-05-14
modified: 2026-06-24
reviewed: 2026-07-04
paths:
  - "**/*.sh"
  - "scripts/**"
---
# Structured Script Output

Diagnostic shell scripts invoked by skills should emit a Bash-friendly
`KEY=VALUE` body wrapped in `=== SECTION ===` delimiters, with a
one-line `STATUS=` summary and an `ISSUE_COUNT=` roll-up. The format is
deterministic, grep-and-awk parseable, and lets an orchestrating skill
roll up many checks into a status table without re-reading each
script's prose.

The convention was promoted from the
[`health-plugin/skills/health-check/scripts/`](../../health-plugin/skills/health-check/scripts/)
suite after positive feedback in [#1270](https://github.com/laurigates/claude-plugins/issues/1270) --
the `check-*.sh` scripts there are the reference implementation.

## Why

Skills that orchestrate multiple diagnostic scripts pay context-window
cost for every line of decorative output (colour codes, spinners, ASCII
boxes, prose summaries). Structured output is cheaper in three ways:

| Cost | Prose / decorated output | Structured KEY=VALUE |
|------|-------------------------|----------------------|
| Parsing complexity | Regex over varying prose | `grep -E '^STATUS=' \| cut -d= -f2` |
| Context tokens for the rollup | Whole body | Two lines per check (`STATUS=` + `ISSUE_COUNT=`) |
| Multi-script separation | Heuristics on blank lines | `=== END SECTION ===` delimiter |

See [`.claude/rules/agentic-optimization.md`](agentic-optimization.md)
for the broader "machine-readable output" principle this rule is one
concrete instance of.

## Schema

| Token | Required | Shape | Example |
|-------|----------|-------|---------|
| Section header | yes | `=== <NAME> ===` (uppercase, spaces ok) | `=== SETTINGS FILES ===` |
| Section footer | yes | `=== END <NAME> ===` (same name) | `=== END SETTINGS FILES ===` |
| Key/value lines | yes | `KEY=value` (uppercase keys, no spaces around `=`) | `PLUGIN_COUNT=47` |
| Status line | yes | `STATUS=OK\|WARN\|ERROR` | `STATUS=OK` |
| Issue count | yes | `ISSUE_COUNT=<int>` | `ISSUE_COUNT=0` |
| Issues block | optional | `ISSUES:` then indented `  - SEVERITY=... TYPE=... MSG=...` lines | see example below |

Status vocabulary: `OK` / `WARN` / `ERROR` is what the reference
scripts emit and what `health-check` orchestration rolls up. Variants
like `GOOD` / `FAIL` are acceptable for one-off scripts but harm
cross-suite rollups -- prefer the canonical three.

Conventions that fall out of the schema:

- One section per invocation. Multiple sections in one script are fine
  but each needs a matching `=== END ... ===`.
- Verbose mode emits more `KEY=VALUE` lines, never prose paragraphs.
- Exit code carries severity in parallel with `STATUS=`: `0` for OK,
  `1` for ERROR. WARN scripts still exit `0` -- `STATUS=WARN` is the
  signal. (See [`.claude/rules/parallel-safe-queries.md`](parallel-safe-queries.md)
  for why non-zero exits in parallel batches are expensive.)

## Mini example

From `health-plugin/skills/health-check/scripts/check-settings.sh`:

```
=== SETTINGS FILES ===
JQ_AVAILABLE=true
USER_SETTINGS=OK
PROJECT_SETTINGS=OK
TOTAL_ALLOW_PATTERNS=12
TOTAL_DENY_PATTERNS=3
STATUS=OK
ISSUE_COUNT=0
=== END SETTINGS FILES ===
```

With issues:

```
=== HOOKS CONFIGURATION ===
JQ_AVAILABLE=true
TOTAL_HOOKS=4
STATUS=WARN
ISSUE_COUNT=1
ISSUES:
  - SEVERITY=WARN TYPE=missing_timeout HOOK=PreToolUse MSG=hook has no timeout
=== END HOOKS CONFIGURATION ===
```

## Adoption checklist

When you write a new diagnostic script:

| Check | Detail |
|-------|--------|
| Wrap output in `=== <NAME> ===` / `=== END <NAME> ===` | One section per script keeps rollups simple |
| Emit `STATUS=OK\|WARN\|ERROR` | Use the canonical three-value vocabulary |
| Emit `ISSUE_COUNT=<int>` | Even when `0` -- orchestrators check existence |
| Uppercase keys, no spaces around `=` | `PLUGIN_COUNT=47`, not `plugin_count = 47` |
| Indent multi-issue rows with two spaces under `ISSUES:` | Matches the reference scripts' awk-friendly shape |
| Avoid colour codes, spinners, prose paragraphs | They survive into the orchestrator's context as noise |
| Exit `0` on OK/WARN, `1` on ERROR | Lets parallel batches survive (see `parallel-safe-queries.md`) |
| Accept `--home-dir` / `--project-dir` flags | Path portability -- see [`.claude/rules/shell-scripting.md`](shell-scripting.md) |

## Related

- [`health-plugin/skills/health-check/scripts/`](../../health-plugin/skills/health-check/scripts/) -- reference implementation (`check-hooks.sh`, `check-mcp.sh`, `check-plugins.sh`, `check-settings.sh`)
- [`.claude/rules/agentic-optimization.md`](agentic-optimization.md) -- machine-readable output as a general principle
- [`.claude/rules/agentic-permissions.md`](agentic-permissions.md) -- "Output structured `KEY=value` pairs with `=== SECTION ===` headers" under Script Conventions
- [`.claude/rules/shell-scripting.md`](shell-scripting.md) -- safe shell patterns (`set -uo pipefail`, prefixed variable names, `--home-dir`/`--project-dir` flags)
- [`.claude/rules/parallel-safe-queries.md`](parallel-safe-queries.md) -- why exit codes matter in parallel batches
- Evidence: [#1270](https://github.com/laurigates/claude-plugins/issues/1270) -- positive feedback on `STATUS=`/`ISSUE_COUNT=` rollups
