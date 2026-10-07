---
name: dry-consolidation
description: Find and extract duplicated code into shared abstractions. Use when seeing repeated utilities, copy-pasted components, duplicated hooks, or boilerplate repeated across files.
args: "[PATH] [--scope <utilities|components|hooks|all>] [--dry-run]"
allowed-tools: Read, Write, Edit, Grep, Glob, Bash(npx tsc *), Bash(npm run *), Bash(npm test *), Bash(npx *), Bash(bun *), Bash(pnpm *), Bash(yarn *), Bash(pytest *), Bash(ty *), Bash(ruff *), Bash(cargo *), Bash(ast-grep *), Bash(sg *), Task
model: opus
argument-hint: path or directory to scan for duplication
created: 2026-02-06
modified: 2026-09-02
reviewed: 2026-09-02
agent: general-purpose
context: fork
---

# DRY Consolidation

Systematic extraction of duplicated code into shared, tested abstractions.

## When to Use This Skill

| Use this skill when... | Use these instead when... |
|------------------------|--------------------------|
| Multiple files have identical/near-identical code blocks | Single file needs cleanup → `/code:refactor` |
| Copy-pasted utility functions across components | Looking for anti-patterns without fixing → `/code:antipatterns` |
| Repeated UI patterns (dialogs, pagination, error states) | Functional refactoring of a file or directory → `/code:refactor` |
| Duplicated hooks or state management boilerplate | Structural code search only → `ast-grep-search` |
| Near-duplicate copy-paste with renamed vars needs enumerating (jscpd finds the clusters here) | Matching one known structural pattern → `ast-grep-search` |
| Import blocks are bloated from repeated inline patterns | Linting/formatting issues → `/code:lint` |

## Context

- Target path: !`echo "$1"`
- Project type: !`find . -maxdepth 1 \( -name "package.json" -o -name "Cargo.toml" -o -name "pyproject.toml" -o -name "go.mod" \)`
- Source directories: !`find . -maxdepth 1 -type d \( -name "src" -o -name "lib" -o -name "app" -o -name "components" -o -name "packages" \)`
- Test framework: !`find . -maxdepth 2 \( -name "vitest.config.*" -o -name "jest.config.*" -o -name "pytest.ini" -o -name "conftest.py" \)`
- Existing shared utilities: !`find . \( -path "*/lib/*" -o -path "*/utils/*" -o -path "*/shared/*" -o -path "*/common/*" -o -path "*/hooks/*" \) -type f -print -quit`

## Parameters

- `$1`: Path or directory to scan (defaults to `src/`)
- `--scope`: Focus on a specific extraction type: `utilities`, `components`, `hooks`, or `all` (default: `all`)
- `--dry-run`: Analyze and report duplications without making changes

## Execution

Execute this 7-step consolidation workflow. Track each extraction as a separate task with `TodoWrite` when the session has the task tools (see `.claude/rules/agentic-permissions.md` § Task-tool availability), otherwise as a checklist in your response.

### Step 1: Discover duplicate clusters (deterministic clone detection)

Enumerate duplicate ranges with a deterministic clone detector, then read **only the reported ranges** — not whole candidate files. This keeps discovery reproducible and cheap. Token-based detection (jscpd) finds copy-paste independent of whitespace/formatting and of the enclosing symbol name — clone pairs a name-based Grep misses when the wrapping function is renamed. ast-grep (1b) then adds tolerance for variables renamed *inside* the block.

#### 1a. Token-based near-duplicates with jscpd

`jscpd` is a token-based copy/paste detector that supports 150+ languages despite the "js" in the name; `npx` runs it with no global install. Run it over the target path:

```bash
npx jscpd --reporters json --min-tokens 50 --output /tmp/jscpd-dry --silent <path>
```

It writes `/tmp/jscpd-dry/jscpd-report.json`. Read that report and parse its `duplicates` array — each entry gives the exact file/line ranges of a clone pair plus its size in tokens/lines:

An example of the report shape is in [references/clone-report.md](references/clone-report.md).

For each reported clone, **Read only the line ranges** (`Read` with `offset`/`limit` around `start`/`end`) to confirm the duplication and classify it — do not Read whole candidate files. jscpd similarity is high by construction for a reported clone (a `--min-tokens` match); note the tokens/lines for the Extraction Plan.

#### 1b. Structural confirmation with ast-grep

Once jscpd surfaces a cluster, confirm it is the same *shape* — same call-shape / same block modulo captured variables — with ast-grep metavariables. `$VAR` / `$INIT` match any identifier/expression, so a block differing only in renamed captures still matches:

```bash
ast-grep -p 'const $VAR = useState($INIT)' --lang tsx <path>
```

Use this to separate a genuine extractable duplicate from a coincidental token overlap before planning the extraction. (For a standalone structural search without extraction, use the `ast-grep-search` skill.)

#### 1c. Graceful fallback (Grep) when the detector is unavailable

When `npx`/`jscpd` is unavailable, or the ecosystem has no `npx` on PATH, fall back to agent-driven text search:

1. Use Grep to find repeated function names, variable patterns, and import clusters
2. Use Glob to identify files with similar structure (e.g., all `*List.tsx`, all `*Detail.tsx`)
3. Read candidate files to confirm duplication and measure scope

This fallback has lower recall for near-duplicates (renamed variables, reordered params) — prefer the jscpd path when available, and reserve Grep for when it is not.

The duplication signals both paths feed into Step 2 are listed in
[references/duplication-signals.md](references/duplication-signals.md).

### Step 2: Classify duplications

Group discovered duplications into extraction categories:

| Category | Extract Into | Location Convention |
|----------|-------------|---------------------|
| **Utilities** | Pure functions | `src/lib/utils/` or `src/utils/` |
| **Components** | Shared UI components | `src/components/ui/` or `src/components/shared/` |
| **Hooks** | Custom React/Vue hooks | `src/hooks/` or `src/composables/` |
| **Types** | Shared type definitions | `src/types/` or alongside the abstraction |

Follow the project's existing conventions for shared code location. If no convention exists, propose one based on the framework.

### Step 3: Plan extractions

For each duplication cluster, plan the extraction:

1. **Name the abstraction** — Use a clear, descriptive name that reflects the shared behavior
2. **Define the interface** — Determine parameters needed to cover all usage variations
3. **Choose the location** — Follow project conventions for shared code placement
4. **List all consumers** — Identify every file that will be updated
5. **Assess risk** — Note any subtle differences between duplicated instances that need parameterization

Present the plan to the user before proceeding (unless `--dry-run` was not specified and the scope is clear).

**Plan format:**
```
## Extraction Plan

### 1. [Abstraction Name] → [target file path]
- Type: utility | component | hook
- Replaces: [N] identical blocks across [M] files
- Consumers: [list of files]
- Parameters: [any variations that need to be parameterized]
- Duplicated: [N] tokens / [N] lines (from jscpd; blank when the Grep fallback was used)
- Similarity: [N]% (from jscpd; "exact" when ast-grep-confirmed as the same shape)
- Estimated lines saved: [N]
```

The `Duplicated` and `Similarity` fields come from jscpd's report (tokens/lines per clone, and the cluster's percentage) — a quantified `--dry-run` report instead of a best-effort narrative. When the Grep fallback (1c) supplied the cluster, leave them blank or note "grep-estimated".

### Step 4: Extract shared abstractions

Execute each planned extraction:

1. **Create the shared abstraction** with proper typing and documentation
2. **Replace each instance** in consumer files with an import + usage of the new abstraction
3. **Handle variations** — parameterize differences between instances rather than creating multiple abstractions
4. **Update imports** — add the new import, remove imports that were only needed for the inline version

**Extraction order:** Start with utilities (no dependencies), then components, then hooks (may depend on utilities/components).

Mark each extraction as completed in the tracker before moving to the next.

### Step 5: Write tests

Write tests for each extracted abstraction:

Pick the test approach per abstraction type (utility, component, hook, types) from
[references/test-and-verify.md](references/test-and-verify.md#test-approach-by-abstraction-type).

Place test files adjacent to the abstraction or in the project's test directory, following existing conventions.

### Step 6: Clean up dead code

After all extractions are complete:

1. **Remove unused imports** from all updated consumer files
2. **Remove dead code** — inline helper functions that are now replaced
3. **Verify no orphaned references** — search for any remaining references to removed code

### Step 7: Verify all checks pass

Run the full verification suite:

Run type checking, linting, and the full test suite with the project's tools — the
TypeScript/JavaScript, Python, and Rust command sets are in
[references/test-and-verify.md](references/test-and-verify.md#verification-commands).

All three must pass. If any fail, fix the issues before reporting completion.

### Output Summary

After all phases complete, report using the summary template in
[references/output-summary.md](references/output-summary.md).

## Agentic Optimizations

Compact command forms (clone scan, shape confirm, scoped runs, fast verify) are in
[references/agentic-optimizations.md](references/agentic-optimizations.md).

## See Also

Sibling skills (`/code:refactor`, `/code:antipatterns`, `ast-grep-search`) and follow-ups
(`/code:dead-code`, `/code:complexity`) are listed in [references/related.md](references/related.md).
