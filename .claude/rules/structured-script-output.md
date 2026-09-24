---
created: 2026-05-14
modified: 2026-09-23
reviewed: 2026-07-04
paths:
  - "**/*.sh"
  - "scripts/**"
---
# Structured Script Output

Diagnostic shell scripts invoked by skills should emit a Bash-friendly
`KEY=VALUE` body wrapped in `=== SECTION ===` delimiters, with a
one-line `STATUS=` summary, an `ISSUE_COUNT=` roll-up, and on a non-OK
result a bounded `REASON=` naming the cause. The format is deterministic,
grep-and-awk parseable, and lets an orchestrating skill roll up many checks
into a status table without re-reading each script's prose.

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
| Context tokens for the rollup | Whole body | Two lines per passing check (`STATUS=` + `ISSUE_COUNT=`), a third (`REASON=`) on WARN/ERROR |
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
| Reason line | on WARN/ERROR only | `REASON=<one line, at most 200 characters>` | `REASON=missing_timeout: hook has no timeout` |
| Issue count | yes | `ISSUE_COUNT=<int>` | `ISSUE_COUNT=0` |
| Issues block | optional | `ISSUES:` then indented `  - SEVERITY=... TYPE=... MSG=...` lines | see example below |

Status vocabulary: `OK` / `WARN` / `ERROR` is what the reference
scripts emit and what `health-check` orchestration rolls up. A rollup
keyed on those three reads `GOOD`, `FAIL` or `PASS` as unknown, so every
`scripts/check-*.sh` must use them (enforced, see below); a one-off script
elsewhere should too.

Conventions that fall out of the schema:

- One section per invocation. Multiple sections in one script are fine
  but each needs a matching `=== END ... ===`.
- Verbose mode emits more `KEY=VALUE` lines, never prose paragraphs.
- Exit code carries severity in parallel with `STATUS=`: `0` for OK,
  `1` for ERROR. WARN scripts still exit `0` -- `STATUS=WARN` is the
  signal. (See [`.claude/rules/parallel-safe-queries.md`](parallel-safe-queries.md)
  for why non-zero exits in parallel batches are expensive.)

### `REASON=` on the non-OK path

`STATUS=ERROR` with `ISSUE_COUNT=3` says how many things failed and never
which, so the caller re-runs the script unfiltered or reads its source.
`REASON=` carries the cause at the rollup level, for three lines per
failing check instead of the whole body:

- Emit it only when `STATUS` is `WARN` or `ERROR`, never on `OK`, so the
  common path costs nothing extra.
- Exactly one line, at most 200 characters. Collapse whitespace and cut
  the cause to about 180 characters before any suffix.
- Derive it from the first finding at the reported severity, as
  `<TYPE>: <MSG>`, and append ` (+N more)` when there are other findings.
  The full list stays in `ISSUES:`.

A caller can then name the failing assertion from the summary lines
alone (#2691).

### `ISSUE_COUNT=` counts the script's own findings

When an `ISSUES:` block is present, `ISSUE_COUNT=` equals the number of
rows under it. `git-triage.sh` printed `ISSUE_COUNT=0` beneath ten
populated rows (#2714), which a rollup would have trusted.

A script whose domain objects are GitHub issues names those counts with a
domain key, such as `ISSUES_FETCHED=` or `GH_ISSUE_COUNT=`, and keeps
`ISSUE_COUNT=` for its findings, so a backlog size is never read as a
finding count.

### Enforcement

`scripts/check-structured-output-contract.sh --strict` (pre-commit) sweeps
every `scripts/check-*.sh` that emits `STATUS=`: canonical values, whether
literal or traced through a shell or Python variable, plus `ISSUE_COUNT=`
and `REASON=`. Scripts not yet migrated to `REASON=` are listed in
`scripts/structured-output-reason-pending.txt`; the guard errors on an entry
that now emits `REASON=`, so the list only shrinks. Static analysis cannot
prove the `REASON=` line sits on the non-OK path, so the same script's
`--validate` mode checks a captured block (one canonical `STATUS=`, an
integer `ISSUE_COUNT=` equal to the `ISSUES:` rows, `REASON=` present and
bounded iff not `OK`). A script's test twin pipes its failing and passing
fixture output through it.

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

With issues, in the shape the contract requires (the health-check
scripts predate `REASON=`):

```
=== HOOKS CONFIGURATION ===
JQ_AVAILABLE=true
TOTAL_HOOKS=4
STATUS=WARN
REASON=missing_timeout: hook has no timeout
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
| Emit `REASON=<one line>` on WARN/ERROR only | First finding as `<TYPE>: <MSG>`, at most 200 characters, never on OK |
| Emit `ISSUE_COUNT=<int>` | Even when `0` -- orchestrators check existence; equal to the `ISSUES:` rows |
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
