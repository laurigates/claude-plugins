---
model: opus
name: dry-consolidation
description: |
  Find and extract duplicated code into shared abstractions. Use when you see repeated
  patterns across multiple files — identical utility functions, copy-pasted UI components,
  duplicated hooks or state management, or repeated boilerplate blocks. Systematically
  consolidates them into reusable utilities, components, hooks, and shared modules.
args: "[PATH] [--scope <utilities|components|hooks|all>] [--dry-run]"
allowed-tools: Read, Write, Edit, MultiEdit, Grep, Glob, Bash(npx tsc *), Bash(npm run *), Bash(npx *), Bash(bun *), Bash(pnpm *), Bash(yarn *), Bash(pytest *), Bash(cargo *), TodoWrite, Task
argument-hint: path or directory to scan for duplication
created: 2026-02-06
modified: 2026-02-10
reviewed: 2026-02-06
---

# DRY Consolidation

Systematic extraction of duplicated code into shared, tested abstractions.

## When to Use This Skill

| Use this skill when... | Use these instead when... |
|------------------------|--------------------------|
| Multiple files have identical/near-identical code blocks | Single file needs cleanup → `/code:refactor` |
| Copy-pasted utility functions across components | Looking for anti-patterns without fixing → `/code:antipatterns` |
| Repeated UI patterns (dialogs, pagination, error states) | General SOLID refactoring → `/refactor` |
| Duplicated hooks or state management boilerplate | Structural code search only → `ast-grep-search` |
| Import blocks are bloated from repeated inline patterns | Linting/formatting issues → `/lint:check` |

## Context

- Target path: !`test -n "$1" && echo "$1" || echo "src/"`
- Project type: !`find . -maxdepth 1 \( -name "package.json" -o -name "Cargo.toml" -o -name "pyproject.toml" -o -name "go.mod" \) 2>/dev/null`
- Source directories: !`find . -maxdepth 1 -type d \( -name "src" -o -name "lib" -o -name "app" -o -name "components" -o -name "packages" \) 2>/dev/null`
- Test framework: !`find . -maxdepth 2 \( -name "vitest.config.*" -o -name "jest.config.*" -o -name "pytest.ini" -o -name "conftest.py" \) 2>/dev/null`
- Existing shared utilities: !`find . -path "*/lib/*" -o -path "*/utils/*" -o -path "*/shared/*" -o -path "*/common/*" -o -path "*/hooks/*" 2>/dev/null | head -20`

## Parameters

- `$1`: Path or directory to scan (defaults to `src/`)
- `--scope`: Focus on a specific extraction type: `utilities`, `components`, `hooks`, or `all` (default: `all`)
- `--dry-run`: Analyze and report duplications without making changes

## Execution

Execute this 7-step consolidation workflow. Use TodoWrite to track each extraction as a separate task.

### Step 1: Scan for duplicated patterns

Scan the target path for duplicated patterns. Search for these duplication signals:

**Identical function bodies:**
```
Grep for function/method signatures that appear in multiple files.
Look for identical multi-line blocks (3+ lines) across files.
```

**Repeated inline patterns:**
- Utility functions defined identically in multiple files (string truncation, date formatting, validation)
- Identical error handling blocks (try/catch patterns, error state JSX)
- Copy-pasted UI fragments (pagination controls, confirmation dialogs, loading states)
- Repeated hook/state management patterns (delete confirmation + mutation + handler)
- Duplicated import blocks that signal repeated inline implementations

**Search strategy:**
1. Use Grep to find repeated function names, variable patterns, and import clusters
2. Use Glob to identify files with similar structure (e.g., all `*List.tsx`, all `*Detail.tsx`)
3. Read candidate files to confirm duplication and measure scope

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
- Estimated lines saved: [N]
```

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
python -m mypy .          # Type checking
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
| Quick scan | Use `--dry-run` to see duplication report without changes |
| Focused extraction | Use `--scope utilities` to extract only utility functions |
| Large codebase | Scope to specific directory: `/code:dry-consolidation src/components/` |
| Post-extraction verify | `npx tsc --noEmit 2>&1 | head -30` for quick type error check |
| Test run (fast) | `npm test -- --bail=1 --reporter=dot` for quick pass/fail |

## See Also

- `/code:refactor` — General SOLID refactoring for single files
- `/code:antipatterns` — Detection-only analysis for code smells
- `/refactor` — Quick refactoring of selected code
- `ast-grep-search` — Structural code search for finding patterns
