# Code Quality Plugin

Code review, refactoring, linting, anti-pattern detection, and static analysis for Claude Code.

## Overview

This plugin provides comprehensive code quality tools including automated code review, refactoring assistance, linting, anti-pattern detection, dependency auditing, test quality analysis, and complexity metrics using ast-grep for structural analysis.

## Skills

| Skill | Description |
|-------|-------------|
| `/code:review` | Comprehensive code review with automated fixes |
| `/code:refactor` | Refactor code applying functional programming principles - pure functions, immutability, and composition |
| `/code:antipatterns` | Analyze codebase for anti-patterns and code smells using ast-grep |
| `/code:lint` | Universal linter - auto-detects and runs appropriate linting tools (with `--fix` for autofix) |
| `/code:dry-consolidation` | Find and extract duplicated code into shared, tested abstractions |
| `/code:docs-quality` | Analyze documentation quality - PRDs, ADRs, PRPs, CLAUDE.md, and .claude/rules/ |
| `/code:hidden-failures` | Detect hidden failures — swallowed errors (empty catch, `\|\| true`, `2>/dev/null`, floating promises, ignored Go/Rust errors) and silent degradation (ops succeed with zero results); `--track errors\|degradation\|both` |
| `/code:dead-code` | Detect dead code, unused exports, unreachable branches, and orphaned files |
| `/code:dep-audit` | Audit dependencies for security vulnerabilities, outdated packages, and license compliance |
| `/code:test-quality` | Analyze test suite quality — detect test smells, empty assertions, flaky patterns |
| `/code:complexity` | Analyze code complexity metrics — cyclomatic, cognitive, function length, coupling |
| `/code-quality:bulk-sweep-classify` | Route a bulk sweep by target: code renames go through `ast-grep-search` structurally; prose/docs sweeps use the four-category classify-then-transform discipline with allowlist-aware verification |
| `ast-grep-search` | AST-based code search for structural pattern matching |

## Agents

| Agent | Description |
|-------|-------------|
| `code-review` | Code quality, architecture, and performance analysis |
| `code-refactoring` | Functional refactoring - pure functions, immutability, and composition |
| `code-analysis` | Structural code analysis and pattern detection |
| `linter-fixer` | Automatic linting and code formatting |
| `security-audit` | Security analysis and vulnerability assessment |

## Usage Examples

### Code Review

```bash
/code:review src/
```

Performs comprehensive code review including:
- Code quality analysis
- Security assessment
- Performance evaluation
- Maintainability review

### Anti-Pattern Detection

```bash
/code:antipatterns --focus security --severity high
```

Scans for anti-patterns using ast-grep structural matching:
- Code smells
- Security vulnerabilities
- Performance issues
- Maintainability problems

### Refactoring

```bash
/code:refactor src/components/
```

Refactors code applying functional programming principles:
- Pure functions (separate computation from side effects)
- Immutability (transform data, don't mutate it)
- Composition (build from small, focused functions)
- Higher-order functions (map/filter/reduce over loops)
- Explicit effects (push I/O to the boundary)

### DRY Consolidation

```bash
/code:dry-consolidation src/components/
```

Finds and extracts duplicated code into shared abstractions:
- Discovers clones deterministically with `jscpd` (token-based, 150+ languages) plus `ast-grep` shape confirmation, falling back to Grep when `npx`/`jscpd` is unavailable
- Utility functions (string helpers, formatters, validators)
- UI components (dialogs, pagination, error states)
- Custom hooks (delete confirmation, form state, mutations)
- Runs tests and verification after all extractions

### Universal Linting

```bash
/code:lint --fix
```

Auto-detects project type and runs appropriate linters:
- Biome/ESLint for JavaScript/TypeScript
- Ruff for Python
- Clippy for Rust

### Documentation Quality Check

```bash
/code:docs-quality
```

Analyzes documentation quality and standards:
- CLAUDE.md structure and completeness
- .claude/rules/ organization
- ADRs (Architecture Decision Records)
- PRDs (Product Requirements Documents)
- PRPs (Product Requirement Prompts)
- Freshness and git history alignment
- Generates comprehensive quality report with actionable recommendations

### Hidden-Failure Scan

```bash
/code:hidden-failures src/
```

Detects code that fails without saying so, across two tracks:

**errors** (syntactic error suppression) — empty `catch {}`, `|| true`,
`2>/dev/null`, floating promises, ignored Go/Rust results — across shell,
JS/TS, Python, Go, and Rust. Recommends a surfacing channel based on detected
app context (CLI stderr, web toast + `console.error`, structured log,
`Result` propagation) and applies a privacy redaction policy to any generated
user-facing strings. Use `--emit-patch` for a reviewable diff.

**degradation** (logical silent failure) — missing config causing features to
skip without warning, success banners when nothing ran, multi-step operations
that silently skip steps, missing precondition validation, degraded mode
without notification. Use `--fix` to add precondition checks, warning
messages, and status indicators.

```bash
/code:hidden-failures src/ --track errors --severity high
/code:hidden-failures src/ --track degradation --fix
```

Select a single track with `--track errors|degradation` (default `both`).

### Dead Code Detection

```bash
/code:dead-code src/
```

Detects dead code across languages:
- Unused exports and files (Knip for JS/TS)
- Unused functions and variables (Vulture for Python)
- Unused dependencies (cargo-machete for Rust)

### Dependency Audit

```bash
/code:dep-audit --type all
```

Audits dependencies for:
- Known CVEs and security vulnerabilities
- Outdated packages
- License compliance issues

### Test Quality Analysis

```bash
/code:test-quality tests/
```

Analyzes test suite health:
- Empty tests with no assertions
- Weak/tautological assertions
- Flaky patterns (setTimeout, hardcoded ports)
- Missing edge case coverage

### Complexity Analysis

```bash
/code:complexity src/ --threshold 10
```

Measures and reports:
- Cyclomatic and cognitive complexity
- Function length distribution
- Nesting depth hotspots
- File-level coupling indicators

## ast-grep Patterns

The plugin includes ast-grep patterns for common issues:

```bash
# Find console.log statements
ast-grep -p 'console.log($$$)'

# Find empty catch blocks
ast-grep -p 'catch ($ERR) { }'

# Find TODO comments
ast-grep -p '// TODO: $MSG'
```

## Configure Plugin Pairing

This plugin works reactively (analyze and fix). The **configure-plugin** works proactively (set up tooling). They complement each other:

| code-quality-plugin (reactive) | configure-plugin (proactive) |
|---|---|
| `/code:lint` — run linters | `/configure:linting` — set up linters |
| `/code:lint --fix` — autofix lint issues | `/configure:formatting` — set up formatters |
| `/code:dead-code` — find dead code | `/configure:dead-code` — set up detection tools |
| `/code:dep-audit` — audit dependencies | `/configure:security` — set up security scanning |
| `/code:test-quality` — analyze test quality | `/configure:tests` + `/configure:coverage` — set up frameworks |
| `/code:docs-quality` — check doc quality | `/configure:docs` — set up doc generators |

## Companion Plugins

Works well with:
- **configure-plugin** - Proactive tool setup (see pairing table above)
- **testing-plugin** - For test coverage analysis
- **git-plugin** - For pre-commit quality checks
- **python-plugin** / **typescript-plugin** - Language-specific linting

## Installation

```bash
/plugin install code-quality-plugin@laurigates-claude-plugins
```

## PostToolUse Pre-flight Cue

The plugin ships a PostToolUse behavioral cue hook (ADR-0017) that fires **once per session** when an Edit or Write touches a file with structural signals. When it fires, it feeds back a short reminder to run `/code-quality:code-lint` **once the current edit sequence is complete** — and, **only when a skill file under a `skills/` tree changed**, to also run `/evaluate:evaluate-skill`.

The cue deliberately does *not* ask for a lint *right now*. A PostToolUse hook cannot tell edit 1 of 4 from a finished change, and linting a knowingly half-applied refactor produces actively-wrong findings — e.g. "`inline` is unused, rename to `_inline`" for a symbol whose four uses land three edits later (issue #2272).

**Which layer covers which case.** The rewording above is what addresses the scenario issue #2272 actually filed: edit 1 of a 4-edit sequence *still fires*, because the sequence debounce is **backward-looking** — it can only see edits that already happened, so it can never suppress the first edit of anything. Only the instruction changed, from "lint before continuing" to "lint once the sequence settles". The debounce's narrower job is to make sure the session's single cue lands on a *settled* edit instead of a mid-burst one.

### How it works

- **Fires on**: Edit and Write tool completions
- **Structural signals** (any one is enough to fire):
  - The diff contains a public-symbol line: `export`, `export default`, `module.exports`, `pub`, `public`, `def`, `class`, `func` — for shell scripts (`.sh`/`.bash`/`.zsh`), `export` is excluded since `export FOO=bar` is a builtin assignment, not a public-API symbol (issue #1766)
  - The edited file is a manifest: `plugin.json`, `marketplace.json`, `package.json`, `Cargo.toml`, `pyproject.toml`
  - The payload (new_string + content) is >= 50 lines
- **`/evaluate:evaluate-skill` reminder**: appended only for paths under a `skills/` tree, so the cue points at a real action rather than a no-op on ordinary code edits (issue #1766)
- **Silenced for**: `.md`/`.txt` files, `CHANGELOG.md`, test/spec files, lockfiles, docs under `docs/adrs/` or `docs/prds/`
- **Sequence debounce** (issue #2272): the cue stays silent when another Edit/Write to the **same file** landed within the last `CODE_QUALITY_PREFLIGHT_CUE_DEBOUNCE_TTL` seconds (default 120) — a burst of edits to one file means a sequence is still in flight. A debounced edit **does not consume the once-per-session budget**, so the session's one cue lands on a settled edit rather than on the noisiest mid-burst one. Recency is recorded for every non-excluded Edit/Write (structural or not) in `~/.cache/code-quality-preflight-cue/.edits/<session_id>/<file-key>`, and re-arms once the file goes quiet. Keying is session-scoped so concurrent sessions editing the same path never debounce each other.
  - **Accepted true-positive loss**: in a session that edits *one* file repeatedly at sub-TTL intervals and never returns to it after a quiet period, the cue can never fire for that file — every edit refreshes the recency marker, and PostToolUse only runs when an edit happens, so no invocation ever observes the quiet gap. Issue #2272's shape (1) takes this trade knowingly.
  - **Cache hygiene**: the debounce writes one marker per (session, file touched) plus a directory per session, so a sweep prunes markers untouched for `CODE_QUALITY_PREFLIGHT_CUE_MARKER_TTL` minutes (default 1440) and the emptied session directories. A `.last-sweep` sentinel gates it to at most hourly, so the hot path costs one `find` on the sentinel (~3ms) rather than the three prune passes. `CODE_QUALITY_PREFLIGHT_CUE_MARKER_TTL=0` is rejected rather than honoured — unlike `…_DEBOUNCE_TTL`, where 0 disables, 0 here would mean "prune anything a minute old" and disarm live debounces, so it falls back to the default.
- **Once per session**: after firing, a marker file under `~/.cache/code-quality-preflight-cue/<session_id>` prevents re-firing in the same session
- **ADR-0017 compliance**: uses `{"decision":"block","reason":"..."}` with `continueOnBlock: true` — the reason is fed back to the model and the turn continues

### Bypass

Set `CODE_QUALITY_SKIP_HOOKS=1` in your environment to disable the hook entirely for that session.

### Tuning and test seams

| Variable | Default | Effect |
|----------|---------|--------|
| `CODE_QUALITY_SKIP_HOOKS` | unset | `1` disables the hook entirely |
| `CODE_QUALITY_PREFLIGHT_CUE_CACHE_DIR` | `~/.cache/code-quality-preflight-cue` | Redirects both the session dedup marker and the `.edits/` recency markers (used by the regression tests under `hooks/test-code-quality-preflight-cue.sh`) |
| `CODE_QUALITY_PREFLIGHT_CUE_DEBOUNCE_TTL` | `120` (seconds) | Sequence-debounce window. `0` disables the debounce, restoring per-edit evaluation. A non-numeric value falls back to the default |
| `CODE_QUALITY_PREFLIGHT_CUE_MARKER_TTL` | `1440` (minutes) | Age at which a `.edits/` recency marker is swept. A non-numeric value falls back to the default |

Both suppression layers fail open, and so does the cache-path resolution: a broken clock, an unwritable cache dir, or an unset `HOME` (which falls back to `${TMPDIR:-/tmp}`) lets the cue fire rather than silencing it or aborting the tool call. Regression tests `(o)` and `(p)` in `hooks/test-code-quality-preflight-cue.sh` pin the `HOME`-unset and sweep behaviours.

## License

MIT
