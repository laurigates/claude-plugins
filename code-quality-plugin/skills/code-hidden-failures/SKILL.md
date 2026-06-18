---
created: 2026-04-14
modified: 2026-06-18
reviewed: 2026-05-29
allowed-tools: Bash(bash *), Bash(sg *), Bash(grep *), Read, Grep, Glob, Edit, Write, TodoWrite
args: "[PATH] [--track <errors|degradation|both>] [--lang <shell|js|py|go|rust|auto>] [--severity <low|med|high>] [--emit-patch] [--fix]"
argument-hint: "[PATH] [--track both] [--lang LANG] [--severity LEVEL] [--emit-patch|--fix]"
description: "Scan for hidden failures: swallowed errors (empty catch, || true, 2>/dev/null) and silent degradation (success on zero results). Use when failures vanish or success masks empty output."
name: code-hidden-failures
model: opus
---

# Hidden-Failure Scanner

Detect code that fails without saying so. Two tracks:

| Track | Failure shape | Example |
|-------|---------------|---------|
| **errors** | *Syntactic* — an error signal is discarded | `catch (e) {}`, `\|\| true`, `2>/dev/null`, floating promise, `_ = err` |
| **degradation** | *Logical* — an operation "succeeds" with empty/useless output because a precondition was silently unmet | success toast on `count === 0`, `if (!apiKey) return []`, a 1-of-3 detector run with no indication |

The two were previously separate skills (`code-error-swallowing` +
`code-silent-degradation`); they are the same user intent — "the work
reported success but nothing real happened" — so they live in one scanner
with a `--track` selector.

## When to Use This Skill

| Use this skill when... | Use another skill instead when... |
|------------------------|-----------------------------------|
| Scripts/CI report success but real work failed | `/code:antipatterns` — broad multi-category scan |
| `\|\| true`, `2>/dev/null`, empty `catch {}`, `except: pass` suspected (errors track) | `/code:review` — prose code review |
| A feature reports success but produces nothing (degradation track) | `/code:lint` — a linter already flags the issue |
| Scans return 0 results / success banners on empty outcomes | `/code:dead-code` — you suspect code never runs |
| You need severity classification + a surfacing recommendation | — |

## Context

- Scan path: `$ARGUMENTS` (defaults to current directory)
- Language signals: !`find . -maxdepth 2 \( -name '*.sh' -o -name '*.bash' -o -name '*.ts' -o -name '*.tsx' -o -name '*.js' -o -name '*.jsx' -o -name '*.py' -o -name '*.go' -o -name '*.rs' \) -type f -not -path './node_modules/*' -not -path './.git/*'`
- App-type signals (frontend): !`find . -maxdepth 2 \( -name 'index.html' -o -name 'vite.config.*' -o -name 'next.config.*' \) -type f`
- App-type signals (CLI): !`find . -maxdepth 2 \( -name 'bin' -type d -o -name 'Makefile' -o -name 'justfile' \)`
- App-type signals (service): !`find . -maxdepth 2 \( -name 'Dockerfile' -o -name '*.service' -o -name 'pyproject.toml' \) -type f`
- Config signals: !`find . -maxdepth 2 \( -name '.env*' -o -name 'config.*' -o -name 'settings.*' \) -type f`
- Workflows: !`find . -path '*/.github/workflows/*' -maxdepth 3 -name '*.yml' -type f`

## Parameters

Parse from `$ARGUMENTS`:

- `PATH`: directory or file to scan (defaults to `.`)
- `--track <errors|degradation|both>`: which track to run (default `both`)
- `--lang <shell|js|py|go|rust|auto>`: errors track — restrict to one language (default `auto`)
- `--severity <low|med|high>`: minimum severity to report (default `med`)
- `--emit-patch`: errors track — emit a unified-diff patch on stdout (no in-place mutation; apply with `git apply`)
- `--fix`: degradation track — apply recommended fixes in place (precondition checks, status indicators, distinguishing copy)

`--emit-patch` and `--fix` are mutually exclusive — the errors track reviews
its surfacing copy via a patch, the degradation track applies structural
fixes directly.

## Execution

Run the selected track(s). Default `both`: run errors first, then degradation,
then a combined summary.

### Track A — Error swallowing

Run when `--track` is `errors` or `both`.

#### Step A1: Detect languages and app context

From the context commands above, determine which language matchers to run.
For the app-context matrix (signals → surfacing channel), load
[REFERENCE-surfacing.md](REFERENCE-surfacing.md).

#### Step A2: Run language-specific matchers

Load only the REFERENCE files for languages actually present in the path:

| Language | File | Tool |
|----------|------|------|
| Shell / bash | [REFERENCE-shell.md](REFERENCE-shell.md) | `bash ${CLAUDE_SKILL_DIR}/scripts/scan-shell.sh <path>` |
| JavaScript / TypeScript | [REFERENCE-js.md](REFERENCE-js.md) | `sg` ast-grep with language-specific patterns |
| Python | [REFERENCE-python.md](REFERENCE-python.md) | `sg` with `--lang py` |
| Go | [REFERENCE-go.md](REFERENCE-go.md) | Prefer repo's `errcheck` if configured, else `sg --lang go` |
| Rust | [REFERENCE-rust.md](REFERENCE-rust.md) | `sg --lang rust` + `clippy::let_underscore_must_use` hints |

For each matcher, capture: `file:line`, matched snippet, surrounding function
name if discoverable.

#### Step A3: Classify severity

For every raw finding, assign **Low / Medium / High**:

| Severity | Criteria | Examples |
|----------|----------|----------|
| **Low** | Matches a documented allowlist entry *or* the catch block has a log call + rethrow. | Frontmatter extraction `\|\| true` (see `.claude/rules/shell-scripting.md` lines 135–162); `except FileNotFoundError: pass` around an optional cache. |
| **Medium** | Error suppressed with no log, no fallback value, no surfacing, on a recoverable operation. | `catch (e) {}` around a UI-layer fetch; `\|\| true` after `make lint`. |
| **High** | Suppression around a required operation: data writes, auth, secret handling, config loading, release builds, push/deploy. | `npm publish 2>/dev/null \|\| true`; `except: pass` around a DB commit; `_ = os.Remove(tmpPath)` on a path the caller assumed was cleaned. |

Apply the per-language allowlist rules from each `REFERENCE-*.md` before
assigning Low.

#### Step A4: Recommend a surfacing channel

For each Medium/High finding, consult `REFERENCE-surfacing.md` to pick the
channel appropriate to the detected app context — do **not** recommend a
uniform "log and rethrow":

| App context | Recommended channel |
|-------------|---------------------|
| CLI / shell | `echo "warn: ..." >&2` + non-zero exit on High |
| Web frontend | `console.error` + user-facing toast/banner with sanitized copy |
| Web backend / daemon | Structured log (error ID) + generic 5xx + opaque user message |
| Library | Re-raise / return `Result` / propagate — do not surface to user |
| CI / build script | `echo "::error::..."` (GitHub) or stderr + non-zero exit |

#### Step A5: Apply privacy redaction

Every suggested replacement (report *and* `--emit-patch`) MUST pass through
the redaction rules in `REFERENCE-surfacing.md` §Privacy:

1. Redact env values by name pattern (`*TOKEN*`, `*KEY*`, `*SECRET*`, `*PASSWORD*`, `GH_*`, `ANTHROPIC_*`, `AWS_*`) → `[REDACTED]`.
2. Rewrite absolute home paths (`$HOME`, `/Users/…`, `/home/…`) → `~`.
3. Truncate message payloads at 200 characters.
4. Prefer action-oriented copy over raw stderr forwarding.
5. Never forward `set -x` / xtrace output.

For web frontend, split: verbose detail → `console.error`; short sanitized
copy → UI channel.

#### Step A6: Emit patch (if `--emit-patch`)

Generate a unified diff to stdout (not written to files) that covers only
Medium/High findings, applies the app-context-appropriate channel, runs every
inserted string through the Step A5 redaction, and adds a
`# TODO(hidden-failures): review wording` comment next to each generated
user-facing message. Remind the user: `git apply <patchfile>`.

### Track B — Silent degradation

Run when `--track` is `degradation` or `both`. Detection patterns, severity
guide, and fixes live in [REFERENCE-degradation.md](REFERENCE-degradation.md).

#### Step B1: Discover source files

Glob `**/*.{ts,tsx,js,jsx,py,go,rs}` in the target path, excluding
`node_modules`, `dist`, `build`, `.git`, `vendor`, `__pycache__`.

#### Step B2: Scan for the five degradation patterns

Match the five pattern categories from
[REFERENCE-degradation.md](REFERENCE-degradation.md): silent config skip,
success on zero results, silent step skipping, missing precondition
validation, hidden degraded mode. For each finding capture `file:line`, which
pattern, what the user experiences, and the preconditions the code needs.

#### Step B3: Classify (degradation severity)

High = success messaging when nothing worked (patterns 2, 3); Medium =
functionality silently disabled by config/env (patterns 1, 5); Low = missing
upfront validation (pattern 4).

#### Step B4: Apply fixes (if `--fix`)

Apply the per-pattern fixes from
[REFERENCE-degradation.md](REFERENCE-degradation.md) § Recommended Fixes in
place, then list every change with `file:line` references.

### Combined Report

Group by severity descending; omit Low unless `--severity low`. Tag each row
with its track.

```
Hidden-Failure Scan: <path>  (track: both)
Detected app context: <cli|frontend|backend|library|daemon|ci>

| Track       | Severity | File:Line       | Pattern                     | Recommended action               |
|-------------|----------|-----------------|-----------------------------|----------------------------------|
| errors      | High     | release.sh:42   | `npm publish ... \|\| true` | stderr + exit 1                  |
| degradation | High     | scan.ts:88      | success on zero results     | distinguish "none" vs "skipped"  |
| errors      | Medium   | api/fetch.ts:17 | empty catch                 | console.error + toast (sanitized)|

Totals: errors(high=N med=N low=N)  degradation(high=N med=N low=N)  across M files
```

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Default scan (both tracks) | `/code:hidden-failures .` |
| Errors only, shell, high severity | `/code:hidden-failures . --track errors --lang shell --severity high` |
| Degradation only, with fixes | `/code:hidden-failures src/ --track degradation --fix` |
| Review-ready error patch | `/code:hidden-failures src/ --track errors --emit-patch > /tmp/fix.patch` |

## See Also

- `/code:antipatterns` — delegates here for the error-swallowing category
- `/code:review` — prose code review
- `.claude/rules/shell-scripting.md` — canonical allowlist for shell `\|\| true` / `2>/dev/null`
- `REFERENCE-surfacing.md` — app-context → channel matrix and privacy rules (errors track)
- `REFERENCE-degradation.md` — the five degradation patterns, severities, and fixes (degradation track)
- `/configure:sentry`, `/configure:feature-flags` — surfacing/monitoring infrastructure
