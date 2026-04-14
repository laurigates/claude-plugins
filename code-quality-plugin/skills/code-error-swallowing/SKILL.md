---
created: 2026-04-14
modified: 2026-04-14
reviewed: 2026-04-14
allowed-tools: Bash(bash *), Bash(sg *), Read, Grep, Glob, TodoWrite
args: "[PATH] [--lang <shell|js|py|go|rust|auto>] [--severity <low|med|high>] [--emit-patch]"
argument-hint: "[PATH] [--lang LANG] [--severity LEVEL] [--emit-patch]"
description: |
  Scan for syntactic error swallowing — catch/except blocks that discard errors,
  `|| true` and `2>/dev/null` idioms in shell, floating promises in JS/TS,
  ignored Go error returns, and discarded Rust Results. Classifies each
  finding by severity, recommends a context-appropriate surfacing channel
  (CLI stderr, web toast, structured log, re-raise), and applies a privacy
  redaction policy when generating suggested replacement text. Use when
  failures "disappear", a CI job passes despite the real work failing, or a
  user reports that a feature silently does nothing.
name: code-error-swallowing
---

# Error-Swallowing Scanner

Detect syntactic patterns that suppress errors without surfacing them to a log,
user channel, or caller. Unlike `/code:silent-degradation` — which targets
*logical* silent failures (success on empty results) — this skill targets the
*syntactic* act of discarding an error signal.

## When to Use This Skill

| Use this skill when... | Use another skill instead when... |
|------------------------|-----------------------------------|
| Scripts report success but real work failed | `/code:silent-degradation` — operation "succeeds" with zero results |
| `|| true`, `2>/dev/null`, empty `catch {}`, `except: pass` suspected | `/code:antipatterns` — you want a broad multi-category scan |
| Floating promises or ignored Go/Rust errors | `/code:review` — you want prose code review |
| You need severity classification for error suppression | `/code:lint` — a linter already flags the issue |
| You want a context-aware surfacing recommendation | `/code:dead-code` — you suspect code never runs |

## Context

- Scan path: `$ARGUMENTS` (defaults to current directory)
- Language signals: !`find . -maxdepth 2 \( -name '*.sh' -o -name '*.bash' -o -name '*.ts' -o -name '*.tsx' -o -name '*.js' -o -name '*.jsx' -o -name '*.py' -o -name '*.go' -o -name '*.rs' \) -type f -not -path './node_modules/*' -not -path './.git/*'`
- App-type signals (frontend): !`find . -maxdepth 2 \( -name 'index.html' -o -name 'vite.config.*' -o -name 'next.config.*' \) -type f`
- App-type signals (CLI): !`find . -maxdepth 2 \( -name 'bin' -type d -o -name 'Makefile' -o -name 'justfile' \)`
- App-type signals (service): !`find . -maxdepth 2 \( -name 'Dockerfile' -o -name '*.service' -o -name 'pyproject.toml' \) -type f`
- Workflows: !`find .github/workflows -maxdepth 1 -name '*.yml' -type f`

## Parameters

Parse from `$ARGUMENTS`:

- `PATH`: directory or file to scan (defaults to `.`)
- `--lang <shell|js|py|go|rust|auto>`: restrict to one language (default `auto`)
- `--severity <low|med|high>`: minimum severity to report (default `med`)
- `--emit-patch`: generate a unified-diff patch on stdout instead of a report.
  No in-place mutation. The user applies with `git apply`.

## Execution

Execute this error-swallowing scan:

### Step 1: Detect languages and app context

From the context commands above, determine which language matchers to run.
For the app-context matrix (signals → surfacing channel), load
[REFERENCE-surfacing.md](REFERENCE-surfacing.md).

### Step 2: Run language-specific matchers

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

### Step 3: Classify severity

For every raw finding, assign **Low / Medium / High** using this matrix:

| Severity | Criteria | Examples |
|----------|----------|----------|
| **Low** | Matches a documented allowlist entry *or* catch block has a log call + rethrow. | Frontmatter extraction `|| true` (see `.claude/rules/shell-scripting.md` lines 135–162); `except FileNotFoundError: pass` around an optional cache. |
| **Medium** | Error suppressed with no log, no fallback value, no surfacing, on a recoverable operation. | `catch (e) {}` around a UI-layer fetch; `|| true` after `make lint`. |
| **High** | Suppression around a required operation: data writes, auth, secret handling, config loading, release builds, push/deploy. | `npm publish 2>/dev/null || true`; `except: pass` around a DB commit; `_ = os.Remove(tmpPath)` on a path the caller assumed was cleaned. |

Apply the per-language allowlist rules from each `REFERENCE-*.md` before
assigning Low.

### Step 4: Recommend a surfacing channel

For each Medium/High finding, consult `REFERENCE-surfacing.md` to pick the
channel appropriate to the detected app context. Do **not** recommend a
uniform "log and rethrow" — the right channel differs:

| App context | Recommended channel |
|-------------|---------------------|
| CLI / shell | `echo "warn: ..." >&2` + non-zero exit on High |
| Web frontend | `console.error` + user-facing toast/banner with sanitized copy |
| Web backend / daemon | Structured log (error ID) + generic 5xx + opaque user message |
| Library | Re-raise / return `Result` / propagate — do not surface to user |
| CI / build script | `echo "::error::..."` (GitHub) or stderr + non-zero exit |

### Step 5: Apply privacy redaction

Every suggested replacement text (in the report *and* in `--emit-patch`
output) MUST be passed through the redaction rules in
`REFERENCE-surfacing.md` §Privacy. Summary:

1. Redact env values by name pattern (`*TOKEN*`, `*KEY*`, `*SECRET*`,
   `*PASSWORD*`, `GH_*`, `ANTHROPIC_*`, `AWS_*`) → `[REDACTED]`.
2. Rewrite absolute home paths (`$HOME`, `/Users/…`, `/home/…`) → `~`.
3. Truncate message payloads at 200 characters.
4. Prefer action-oriented copy over raw stderr forwarding.
5. Never forward `set -x` / xtrace output.

For web frontend, split: verbose detail → `console.error`; short sanitized
copy → UI channel.

### Step 6: Report findings

Print:

```
Error-Swallowing Scan: <path>
Detected app context: <cli|frontend|backend|library|daemon|ci>

| Severity | File:Line       | Pattern                 | Recommended surfacing            |
|----------|-----------------|-------------------------|----------------------------------|
| High     | release.sh:42   | `npm publish ... \|\| true` | stderr + exit 1                  |
| Medium   | api/fetch.ts:17 | empty catch             | console.error + toast (sanitized)|
| Low      | build.sh:8      | frontmatter `\|\| true` | allowlisted — no change          |

Totals: high=N, medium=N, low=N (across M files)
```

Group by severity descending; omit Low findings unless `--severity low`.

### Step 7: Emit patch (if --emit-patch)

Generate a unified diff (printed to stdout, not written to files) that:

1. Covers only Medium/High findings.
2. Applies the surfacing channel appropriate to the detected app context.
3. Runs every inserted string through the Step 5 redaction rules.
4. Includes a `# TODO(error-swallowing): review wording` comment next to
   each generated user-facing message so the human can polish copy.

Do not modify files in place. Remind the user: `git apply <patchfile>`.

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Default scan of repo | `/code:error-swallowing .` |
| Shell only, high severity | `/code:error-swallowing . --lang shell --severity high` |
| JS/TS in a subdir | `/code:error-swallowing src/ --lang js` |
| Produce review-ready patch | `/code:error-swallowing src/ --emit-patch > /tmp/fix.patch` |

## See Also

- `/code:silent-degradation` — logical silent failures (zero-result success)
- `/code:antipatterns` — delegates to this skill for the error-swallowing
  category
- `.claude/rules/shell-scripting.md` — canonical allowlist for shell
  `|| true` / `2>/dev/null` usage
- `REFERENCE-surfacing.md` — app-context → channel matrix and privacy rules
