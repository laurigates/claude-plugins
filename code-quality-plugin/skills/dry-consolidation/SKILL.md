---
name: dry-consolidation
description: Find and extract duplicated code into shared abstractions. Use when seeing repeated utilities, copy-pasted components, duplicated hooks, or boilerplate repeated across files.
args: "[PATH] [--scope <utilities|components|hooks|all>] [--dry-run]"
allowed-tools: Read, Write, Edit, MultiEdit, Grep, Glob, Bash(npx tsc *), Bash(npm run *), Bash(npx *), Bash(bun *), Bash(pnpm *), Bash(yarn *), Bash(pytest *), Bash(cargo *), Bash(ast-grep *), Bash(sg *), TodoWrite, Task
model: opus
argument-hint: path or directory to scan for duplication
created: 2026-02-06
modified: 2026-07-06
reviewed: 2026-02-06
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
| Import blocks are bloated from repeated inline patterns | Linting/formatting issues → `/lint:check` |

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

Execute this 7-step consolidation workflow. Use TodoWrite to track each extraction as a separate task.

### Step 1: Discover duplicate clusters (deterministic clone detection)

Enumerate duplicate ranges with a deterministic clone detector, then read **only the reported ranges** — not whole candidate files. This keeps discovery reproducible and cheap. Token-based detection (jscpd) finds copy-paste independent of whitespace/formatting and of the enclosing symbol name — clone pairs a name-based Grep misses when the wrapping function is renamed. ast-grep (1b) then adds tolerance for variables renamed *inside* the block.

#### 1a. Token-based near-duplicates with jscpd

`jscpd` is a token-based copy/paste detector that supports 150+ languages despite the "js" in the name; `npx` runs it with no global install. Run it over the target path:

```bash
npx jscpd --reporters json --min-tokens 50 --output /tmp/jscpd-dry --silent <path>
```

It writes `/tmp/jscpd-dry/jscpd-report.json`. Read that report and parse its `duplicates` array — each entry gives the exact file/line ranges of a clone pair plus its size in tokens/lines:

```json
{
  "duplicates": [
    {
      "format": "tsx",
      "lines": 12,
      "tokens": 84,
      "firstFile":  { "name": "src/UserList.tsx",  "start": 20, "end": 32 },
      "secondFile": { "name": "src/OrderList.tsx", "start": 15, "end": 27 }
    }
  ],
  "statistics": { "total": { "clones": 3, "duplicatedLines": 40, "duplicatedTokens": 252, "percentage": 5.1 } }
}
```

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

**Duplication signals to classify** (both the jscpd and the Grep path feed the same categories in Step 2):
- Utility functions defined identically in multiple files (string truncation, date formatting, validation)
- Identical error handling blocks (try/catch patterns, error state JSX)
- Copy-pasted UI fragments (pagination controls, confirmation dialogs, loading states)
- Repeated hook/state management patterns (delete confirmation + mutation + handler)
- Duplicated import blocks that signal repeated inline implementations

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

Mark each extraction as completed in the todo list before moving to the next.

### Step 5: Write tests

Write tests for each extracted abstraction:

| Abstraction Type | Test Approach |
|-----------------|---------------|
| Utility function | Unit tests covering all input variations, edge cases |
| UI component | Render tests, prop variations, accessibility |
| Custom hook | Hook testing with mock dependencies, state transitions |
| Type definitions | Type-level tests if applicable (tsd, expect-type) |

Place test files adjacent to the abstraction or in the project's test directory, following existing conventions.

### Step 6: Clean up dead code

After all extractions are complete:

1. **Remove unused imports** from all updated consumer files
2. **Remove dead code** — inline helper functions that are now replaced
3. **Verify no orphaned references** — search for any remaining references to removed code

### Step 7: Verify all checks pass

Run the full verification suite:

**TypeScript/JavaScript projects:**
```bash
npx tsc --noEmit          # Type checking
npm run lint              # Linting (or biome/eslint directly)
npm run test              # Full test suite
```

**Python projects:**
```bash
ty check .                # Type checking
ruff check .              # Linting
pytest                    # Test suite
```

**Rust projects:**
```bash
cargo check               # Type checking
cargo clippy              # Linting
cargo test                # Test suite
```

All three must pass. If any fail, fix the issues before reporting completion.

### Output Summary

After all phases complete, report:

```
## DRY Consolidation Summary

### Extractions
- [Abstraction Name] (type) — replaced N blocks in M files
- ...

### New Files Created
- path/to/new/file.ts — [description]
- ...

### Tests Added
- N tests across M test files

### Net Effect
- ~N lines of duplicated code consolidated
- N reusable abstractions created
- All verified: typecheck + lint + N passing tests
```

## Agentic Optimizations

| Context | Approach |
|---------|----------|
| Deterministic clone scan | `npx jscpd --reporters json --min-tokens 50 --output /tmp/jscpd-dry --silent <path>` then parse `duplicates[]` for exact ranges |
| Structural shape confirm | `ast-grep -p '<pattern with $METAVARS>' --lang <lang> <path>` |
| Quick scan | Use `--dry-run` to see duplication report without changes |
| Focused extraction | Use `--scope utilities` to extract only utility functions |
| Large codebase | Scope to specific directory: `/code:dry-consolidation src/components/` |
| Post-extraction verify | `npx tsc --noEmit 2>&1 | head -30` for quick type error check |
| Test run (fast) | `npm test -- --bail=1 --reporter=dot` for quick pass/fail |

## See Also

- `/code:refactor` — Functional refactoring of a file or directory (pure functions, immutability, composition)
- `/code:antipatterns` — Detection-only analysis for code smells
- `ast-grep-search` — Structural code search for finding patterns

## Related Skills

- If dead code detected during consolidation → `/code:dead-code`
- If complexity is high after consolidation → `/code:complexity`
