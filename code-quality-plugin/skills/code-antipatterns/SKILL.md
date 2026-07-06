---
created: 2025-12-16
modified: 2026-07-06
reviewed: 2026-07-06
description: Analyze a codebase for anti-patterns using ast-grep. Use when finding magic numbers, console.logs, var usage, excessive any, eval/innerHTML security issues, or deep nesting.
allowed-tools: Read, Bash(ast-grep *), Bash(sg *), Bash(rg *), Glob, Grep, TodoWrite, Task, SlashCommand
args: "[PATH] [--focus <category>] [--severity <level>]"
argument-hint: "[PATH] [--focus <category>] [--severity <level>]"
name: code-antipatterns
---

## When to Use This Skill

| Use this skill when... | Use something else instead when... |
|------------------------|------------------------------------|
| Running a parallel anti-pattern scan and producing a report | Looking up the full YAML rule catalog → see [REFERENCE.md](REFERENCE.md) |
| Specifically targeting empty catches, floating promises, or `\|\| true` | Use the dedicated scanner → `code-hidden-failures --track errors` |
| Finding success-on-empty / silent degradation patterns | Use the dedicated scanner → `code-hidden-failures --track degradation` |
| Broad code-quality review across security, perf, and architecture | Run the full review delegate → `code-review` |

## Context

- Analysis path: `$1` (defaults to current directory if not specified)
- JS/TS files: !`find . -type f \( -name "*.js" -o -name "*.ts" -o -name "*.jsx" -o -name "*.tsx" \)`
- Vue files: !`find . -name "*.vue"`
- Python files: !`find . -name "*.py"`

## Your Task

Perform comprehensive anti-pattern analysis. The **mechanical detection** is one
deterministic `ast-grep scan` over a shipped rule project — you do **not** re-type
`sg -p '…'` patterns and do **not** fan out agents just to run them. Your job is
the **judgment**: severity triage, recommendations, and fix planning on top of the
scan's structured findings.

### Step 1: Run the deterministic scan

The detection catalog lives as an ast-grep **rule project** in
[`rules/`](rules/) (one `*.yml` per pattern under `rules/lib/`, each with a
valid/invalid test fixture in `rules/tests/`). Run the whole catalog in one pass:

```bash
ast-grep scan -c ${CLAUDE_SKILL_DIR}/rules/sgconfig.yml --json=compact <path>
```

Each JSON finding carries `ruleId`, `file`, `range` (line/column), `message`, and
the matched `text`. Parse this — it is the raw finding set for every category
below. The rules cover: empty catch, `console.log`, `var`, `eval`/`new Function`,
`innerHTML`/`outerHTML`, `as any` / `: any` annotations, magic-number timers, Vue
props mutation, Python mutable defaults, bare `except`, `global`, and
`type() ==`.

**Graceful degradation** — if `ast-grep` (packaged as `ast-grep` or `sg`) is not
installed, fall back to the per-pattern flow: read [REFERENCE.md](REFERENCE.md),
which links each rule to its source `.yml`, and run the individual
`ast-grep -p '<pattern>' --lang <lang>` commands by hand. The rule project is the
fast path; the reference is the fallback.

### Step 2: Judgment (the agent's actual work)

The scan is mechanical and reproducible; **triage, recommendation, and fix
planning are the judgment work** — do them yourself on the scan output rather than
spawning agents to re-run patterns:

- **Severity triage** — promote/demote each finding using the context in the
  Category tables below and the app type (frontend/backend/CLI/library).
- **Error-swallowing findings** (empty catch, floating promises, bare except) →
  **delegate** to `/code:hidden-failures --track errors` for its severity model,
  surfacing recommendations, and privacy redaction. Do not re-classify them here.
- **Recommendations & fix planning** — group systemic issues, note which findings
  ast-grep can auto-`fix`, and recommend process changes (lint rules, pre-commit).

Reserve any parallel `Task` fan-out for **genuinely independent reasoning** (e.g.
a deep security review or a framework-specific architecture pass) — never for
running the patterns, which Step 1 already did once, deterministically.

### Analysis Categories

Based on the detected languages, analyze for these categories:

1. **JavaScript/TypeScript Anti-patterns**
   - Callbacks, magic values, console.logs
   - var usage, deprecated patterns
   - Error swallowing (empty catch, floating promises) → **delegate** to `/code:hidden-failures --track errors`

2. **Async/Promise Patterns**
   - Nested callbacks, Promise constructor anti-pattern
   - Error-handling coverage (unhandled/floating promises) → **delegate** to `/code:hidden-failures --track errors`

3. **Framework-Specific** (if detected)
   - **Vue 3**: Props mutation, reactivity issues, Options vs Composition API mixing
   - **React**: Missing deps in hooks, inline functions, prop drilling

4. **TypeScript Quality** (if .ts files present)
   - Excessive `any` types, non-null assertions, type safety issues

5. **Code Complexity**
   - Long functions (>50 lines), deep nesting (>4 levels), large parameter lists

6. **Security Concerns**
   - eval usage, innerHTML XSS, hardcoded secrets, injection risks

7. **Memory & Performance**
   - Event listeners without cleanup, setInterval leaks, inefficient patterns

8. **Python Anti-patterns** (if detected)
   - Mutable default arguments, global variables
   - Bare except and suppression patterns → **delegate** to `/code:hidden-failures --track errors`

### Delegated Category: Error Swallowing

Do NOT re-implement empty-catch / bare-except / floating-promise detection
here. Invoke `/code:hidden-failures --track errors` via the SlashCommand tool with the
same `PATH` and severity filter, then fold its findings into the
consolidated report under a dedicated **Error Swallowing** section.

Rationale: a single source of truth prevents drift between severity
models, app-context surfacing recommendations, and privacy redaction
policies. See `code-quality-plugin/skills/code-hidden-failures/SKILL.md`.

### What the rule project does *not* cover (agent judgment)

Two catalog concerns are not structural single-node matches and stay as
**agent-judgment** passes on the code, not rules:

- **Deep nesting / long functions / cyclomatic complexity** — a metric over a
  function body, not a pattern. Use `/code:complexity` or read the flagged files.
- **Floating promises** — the repo's own toolchain is authoritative; defer to
  `tsc` + the `no-floating-promises` ESLint rule, or `/code:hidden-failures
  --track errors`, rather than a broad structural rule that would flag every call.

### Output Format

Consolidate findings into this structure:

```markdown
## Anti-pattern Analysis Report

### Summary
- Total issues: X
- Critical: X | High: X | Medium: X | Low: X
- Categories with most issues: [list]

### Critical Issues (Fix Immediately)
| File | Line | Issue | Category |
|------|------|-------|----------|
| ... | ... | ... | ... |

### High Priority Issues
| File | Line | Issue | Category |
|------|------|-------|----------|
| ... | ... | ... | ... |

### Medium Priority Issues
[Similar table]

### Low Priority / Style Issues
[Similar table or summary count]

### Recommendations
1. [Prioritized fix recommendations]
2. [...]

### Category Breakdown
- **Security**: X issues (details)
- **Async/Promises**: X issues (details)
- **Code Complexity**: X issues (details)
- [...]
```

### Optional Flags

- `--focus <category>`: Focus on specific category (security, async, complexity, framework)
- `--severity <level>`: Minimum severity to report (critical, high, medium, low)
- `--fix`: Attempt automated fixes where safe

### Post-Analysis

After consolidating findings:
1. Prioritize issues by impact and effort
2. Suggest which issues can be auto-fixed with ast-grep
3. Identify patterns that indicate systemic problems
4. Recommend process improvements (linting rules, pre-commit hooks)

## See Also

- **Rule project**: [`rules/`](rules/) — the executable ast-grep catalog (`sgconfig.yml` + `rules/lib/*.yml` + `rules/tests/*-test.yml`); run `ast-grep test -c rules/sgconfig.yml --skip-snapshot-tests` to verify every rule against its fixtures
- **Reference**: [REFERENCE.md](REFERENCE.md) - narrative catalog linking each pattern to its rule file
- **Skill**: `ast-grep-search` - ast-grep usage reference
- **Command**: `/code:review` - Comprehensive code review
- **Agent**: `security-audit` - Deep security analysis
- **Agent**: `code-refactoring` - Automated refactoring

## Related Configure Skills

- If linting not configured → `/configure:linting` for automated enforcement
- If security scanning not set up → `/configure:security` for CI integration
