---
model: opus
created: 2026-01-24
modified: 2026-01-24
reviewed: 2026-01-24
name: git-log-documentation
description: |
  Analyze git commit history to derive undocumented rules, PRDs, ADRs, and PRPs.
  Detects missing documentation from commit patterns: conventions that became rules,
  features built without requirements, architecture decisions made implicitly, and
  plan refinements visible only in commit evolution.
allowed-tools: Bash(git log *), Bash(git shortlog *), Bash(git diff *), Bash(git branch *),
               Bash(git show *), Bash(git rev-list *), Bash(git diff-tree *),
               Read, Grep, Glob, TodoWrite
---

# Git Log Documentation Derivation

Analyze git commit history to surface undocumented design decisions, conventions, architecture choices, and plan refinements that should be captured in formal documentation.

## When to Use

**Trigger phrases:**
- "what's undocumented in this project?"
- "derive rules from git history"
- "find missing documentation"
- "what decisions aren't documented?"
- "analyze commit history for documentation gaps"
- "generate docs from git log"

**Proactive triggers:**
- After a major feature is completed (many commits, no corresponding docs)
- When onboarding to an unfamiliar project
- During documentation audits or reviews
- When `.claude/rules/` is empty or sparse relative to project maturity

## Analysis Categories

### 1. Rules Derivation (`.claude/rules/`)

Identify implicit conventions in commit history that should become explicit rules.

**Detection signals:**

| Signal | Git Command | Indicates |
|--------|-------------|-----------|
| Repeated file patterns | `git log --diff-filter=A --name-only` | Directory/naming conventions |
| Consistent commit prefixes | `git log --format='%s' \| grep -oP '^\w+(\(\w+\))?:'` | Commit message conventions |
| Recurring tool usage | `git log --format='%b' \| grep -i 'run\|execute\|test'` | Workflow conventions |
| Config file changes | `git log --all -- '*.config.*' '*.rc' '.eslintrc*'` | Tool configuration patterns |
| Co-occurring file changes | `git log --name-only --format=''` | File coupling patterns |

**Analysis workflow:**

```bash
# 1. Identify file naming patterns from additions
git log --diff-filter=A --name-only --format='' -- '*.ts' '*.js' '*.py' | sort | uniq -c | sort -rn | head -20

# 2. Extract commit message conventions
git log --format='%s' -200 | grep -oP '^\w+(\([^)]+\))?' | sort | uniq -c | sort -rn

# 3. Find configuration evolution (tool choices)
git log --all --oneline -- '*.config.*' 'tsconfig*' '.eslintrc*' 'biome.json' 'pyproject.toml'

# 4. Detect test file conventions
git log --diff-filter=A --name-only --format='' -- '*.test.*' '*.spec.*' '*_test.*' | head -20

# 5. Find co-changed files (coupling)
git log --name-only --format='---' -100 | awk '/^---$/{if(NR>1)print "";next}{printf "%s,",$0}' | sort | uniq -c | sort -rn | head -10
```

**Rules to derive:**

| Pattern Found | Rule Category | Example Rule |
|---------------|---------------|--------------|
| Consistent test co-location | `testing.md` | "Tests live next to source: `foo.ts` → `foo.test.ts`" |
| Conventional commit types used | `commits.md` | "Use feat/fix/docs/refactor prefixes" |
| Specific linter configs | `code-quality.md` | "Use Biome for formatting, ESLint for logic rules" |
| Directory structure patterns | `project-structure.md` | "Feature modules in `src/features/{name}/`" |
| Import ordering in diffs | `imports.md` | "External → internal → relative imports" |

### 2. PRD Gap Detection (Product Requirements)

Identify features implemented without corresponding requirements documentation.

**Detection signals:**

```bash
# Find feature branches merged without PRD references
git log --merges --format='%s %b' | grep -i 'feat\|feature\|add' | grep -viL 'prd\|requirement\|spec'

# Identify substantial feature additions (many files added)
git log --format='%H %s' --diff-filter=A | while read hash msg; do
  count=$(git diff-tree --no-commit-id --name-only -r "$hash" | wc -l)
  [ "$count" -gt 5 ] && echo "$count $msg"
done | sort -rn | head -10

# Find feature-like directory additions
git log --diff-filter=A --name-only --format='%H' | xargs -I{} git diff-tree --no-commit-id -r {} | grep -E 'src/(features|modules|components)/' | sort -u

# Large commit clusters on feature branches
git log --all --format='%D %s' | grep -i 'feat\|feature\|implement'
```

**PRD candidates emerge when:**
- 5+ commits implement related functionality without a requirements reference
- New directories created for feature modules
- Multiple components added serving a single user workflow
- Commits reference user stories or requirements informally ("users should be able to...")

### 3. ADR Gap Detection (Architecture Decisions)

Identify architecture decisions made in code but not documented.

**Detection signals:**

```bash
# Technology introductions (new dependencies)
git log --all --oneline -- 'package.json' 'Cargo.toml' 'pyproject.toml' 'go.mod' | head -20

# Framework/library migrations (removals + additions)
git log --format='%H %s' -- 'package.json' | while read hash msg; do
  echo "=== $msg ==="
  git show "$hash" -- package.json | grep -E '^\+|^\-' | grep -E '"(dependencies|devDependencies)"' -A 50 | head -20
done

# Architectural file changes (configs, infrastructure)
git log --all --oneline -- 'docker*' 'Dockerfile*' '.github/workflows/*' 'terraform/*' 'k8s/*'

# Pattern shifts (e.g., class→functional, callbacks→promises→async)
git log --format='%H %s' -50 | grep -i 'refactor\|migrate\|switch\|replace\|upgrade'

# Database/schema changes
git log --all --oneline -- '*migration*' '*schema*' '*.sql' 'prisma/*' 'drizzle/*'
```

**ADR candidates emerge when:**
- New major dependency added without documented rationale
- Migration commits (library A → library B)
- Infrastructure pattern changes (monolith → microservice indicators)
- Database technology or schema strategy changes
- Build tool replacements (webpack → vite, jest → vitest)

### 4. PRP Gap Detection (Implementation Plans)

Identify implementation work done without planning documentation.

**Detection signals:**

```bash
# Multi-commit feature implementations
git log --format='%H %s' --all | grep -iE 'step [0-9]|part [0-9]|phase [0-9]|wip|in progress'

# Branch-based feature work
git branch -a --format='%(refname:short)' | grep -iE 'feat|feature|implement'

# Coordinated multi-file changes
git log --format='%H %s' -50 | while read hash msg; do
  files=$(git diff-tree --no-commit-id --name-only -r "$hash" 2>/dev/null | wc -l)
  [ "$files" -gt 3 ] && echo "$files files: $msg"
done | sort -rn | head -15

# TODO/FIXME additions that indicate planned work
git log -p --all -S 'TODO\|FIXME\|HACK\|XXX' --format='%H %s' | grep '^commit\|TODO\|FIXME' | head -30
```

**PRP candidates emerge when:**
- Sequential commits building toward a feature ("add X model", "add X controller", "add X tests")
- WIP commits later squashed or refined
- Multi-file coordinated changes across layers (model + controller + view + test)
- Branch names indicating planned feature work

### 5. Plan Refinement Detection (Suunnitelmien tarkentuminen)

Identify cases where the implementation approach evolved - the plan was refined mid-execution but the refinement wasn't documented.

**Detection signals:**

```bash
# Reverts and re-implementations
git log --format='%s' --all | grep -i 'revert\|redo\|redo\|rework\|rethink\|redesign'

# Refactors shortly after initial implementation
git log --format='%H %s %ai' --all | grep -i 'refactor' | head -20

# Files modified many times in short period (approach changes)
git log --format='%ai %H' --follow -- 'src/important-file.ts' | head -20

# Approach changes visible in commit messages
git log --format='%s' -100 | grep -iE 'actually|instead|better approach|switch to|try|attempt'

# Fixup commits indicating plan adjustments
git log --format='%s' --all | grep -iE '^fixup|^squash|adjust|tweak|correct approach'

# High-churn files (modified frequently = plan was unclear)
git log --format='' --name-only -100 | sort | uniq -c | sort -rn | head -15
```

**Plan refinement indicators:**
- File created then significantly rewritten within days
- Revert followed by alternative implementation
- "Actually..." or "better approach" in commit messages
- High churn on specific files (many edits in short timespan)
- Refactor commits shortly after feature commits

## Execution Workflow

### Step 1: Scope the Analysis

```bash
# Determine project age and commit volume
git rev-list --count HEAD
git log --format='%ai' --reverse | head -1  # First commit date
git log --format='%ai' -1                    # Latest commit

# Check existing documentation
ls -la .claude/rules/ docs/prds/ docs/adrs/ docs/prps/ 2>/dev/null
```

### Step 2: Run Detection Passes

Run each detection category and collect findings. Prioritize by:
1. **Certainty**: How clear is the documentation gap?
2. **Impact**: How much would documenting this help?
3. **Recency**: Recent undocumented changes are more actionable

### Step 3: Cross-Reference with Existing Docs

```bash
# Check what rules already exist
ls .claude/rules/ 2>/dev/null

# Check existing PRDs/ADRs/PRPs
find docs/ -name '*.md' -type f 2>/dev/null | head -30

# Check README for documented decisions
grep -i 'decision\|chose\|architecture\|convention' README.md 2>/dev/null
```

### Step 4: Generate Recommendations

For each gap found, produce:
- **Type**: Rule / PRD / ADR / PRP
- **Title**: Descriptive name
- **Evidence**: Commits that support this finding
- **Priority**: High (active convention) / Medium (historical decision) / Low (minor pattern)
- **Draft content**: Skeleton of what the document should contain

### Step 5: Output Report

Structure findings as actionable items:

```markdown
## Documentation Gaps Found

### Rules (`.claude/rules/`)

1. **[HIGH] testing-conventions.md**
   Evidence: 45 test files follow `*.test.ts` pattern (commits abc123, def456...)
   Draft: "Co-locate tests with source. Use `describe/it` structure..."

2. **[MEDIUM] commit-conventions.md**
   Evidence: 90% of commits use conventional format since commit xyz789
   Draft: "Use conventional commits: feat/fix/docs/refactor..."

### PRDs

1. **[HIGH] User Authentication Feature**
   Evidence: 12 commits in src/auth/ (Jan 5-15) with no PRD reference
   Commits: feat: add OAuth2 flow, feat: add MFA support, feat: add password reset...

### ADRs

1. **[HIGH] Migration from Jest to Vitest**
   Evidence: commit abc123 "refactor: migrate test runner to vitest"
   Before: jest.config.js removed, After: vitest.config.ts added
   Undocumented rationale for the switch

### PRPs (Plan Refinements)

1. **[MEDIUM] Payment Flow Redesign**
   Evidence: Initial impl (commit abc), revert (def), redesign (ghi)
   The approach changed from webhooks to polling - not documented why
```

## Output Formats

### For Rules Generation

When generating `.claude/rules/` content, follow the project's existing rule format:

```markdown
# Rule Title

## Purpose
Why this convention exists (derived from commit patterns).

## Convention
The actual rule, stated clearly.

## Evidence
- First appeared: commit <hash> (<date>)
- Established pattern: <N> files/commits follow this
- Exceptions: <any notable deviations>

## Examples
Good/bad examples from actual commits.
```

### For PRD/ADR/PRP Drafts

Generate skeleton documents that can be passed to blueprint commands:
- PRD → structure for `/blueprint:prd`
- ADR → structure for `/blueprint:adr`
- PRP → structure for `/blueprint:prp-create`

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Quick pattern scan | `git log --format='%s' -100 \| sort \| uniq -c \| sort -rn \| head -20` |
| File addition patterns | `git log --diff-filter=A --name-only --format='' \| sort \| uniq -c \| sort -rn` |
| High-churn detection | `git log --format='' --name-only -100 \| sort \| uniq -c \| sort -rn \| head -15` |
| Technology changes | `git log --oneline -- 'package.json' 'Cargo.toml' 'pyproject.toml'` |
| Refactor signals | `git log --format='%s' \| grep -i 'refactor\|migrate\|switch\|replace'` |
| Plan refinements | `git log --format='%s' \| grep -iE 'revert\|rework\|actually\|better approach'` |

## Composability

| Combined With | Purpose |
|---------------|---------|
| `document-detection` | Feed findings into document creation workflow |
| `/blueprint:prd` | Generate PRDs from detected feature gaps |
| `/blueprint:adr` | Generate ADRs from detected architecture decisions |
| `/blueprint:prp-create` | Generate PRPs from detected implementation patterns |
| `git-commit-workflow` | Understand commit convention context |

## Limitations

- Cannot determine *intent* - only patterns. Human review is needed.
- Squashed merges hide intermediate plan refinements.
- Very old history may reflect outdated conventions.
- Commit messages quality directly affects detection quality.
- Cannot detect verbal/meeting decisions not reflected in commits.

## Quick Reference

| Analysis | Key Signals | Output |
|----------|-------------|--------|
| Rules | Repeated patterns, naming conventions, tool configs | `.claude/rules/*.md` |
| PRDs | Feature clusters without requirement refs | `docs/prds/*.md` skeleton |
| ADRs | Dependency changes, migrations, pattern shifts | `docs/adrs/*.md` skeleton |
| PRPs | Multi-commit features, sequential implementation | `docs/prps/*.md` skeleton |
| Refinements | Reverts, rewrites, "actually..." commits, high churn | Amendments to existing docs |
