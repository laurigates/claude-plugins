---
model: opus
description: "Execute a PRP with validation loop, TDD workflow, and quality gates"
args: "[prp-name]"
argument-hint: "Name of PRP to execute (e.g., feature-auth-oauth2)"
allowed-tools: Read, Write, Edit, Glob, Bash, Task, AskUserQuestion
created: 2025-12-16
modified: 2026-02-14
reviewed: 2026-02-14
name: blueprint-prp-execute
---

# /blueprint:prp-execute

Execute a PRP (Product Requirement Prompt) with systematic implementation, validation gates, TDD workflow, and quality assurance.

**Usage**: `/blueprint:prp-execute [prp-name]`

**Prerequisites**:
- PRP exists in `docs/prps/[prp-name].md`
- Confidence score >= 7 (if lower, suggest `/blueprint:prp-create` refinement)

For detailed report templates, deferred items workflow, feature tracker sync, and error handling patterns, see [REFERENCE.md](REFERENCE.md).

## When to Use This Skill

| Use this skill when... | Use alternative when... |
|------------------------|-------------------------|
| Ready to implement a planned feature from a PRP | PRP is not yet ready (confidence < 7) |
| Want to execute with full validation and TDD workflow | Implementing ad-hoc features without documentation |
| Need feature tracker and GitHub issue tracking | Working on isolated bug fixes |
| Want automatic progress reporting and deferred items tracking | Quick prototyping without formal tracking |

## Context

- PRP file path: !`test -f docs/prps/${1:-unknown}.md && echo "EXISTS" || echo "MISSING"`
- PRP confidence score: !`grep -m1 "^confidence:" docs/prps/${1:-unknown}.md 2>/dev/null`
- Feature tracker enabled: !`test -f docs/blueprint/feature-tracker.json && echo "YES" || echo "NO"`
- Current branch: !`git rev-parse --abbrev-ref HEAD 2>/dev/null`
- Uncommitted changes: !`git status --porcelain 2>/dev/null`

## Parameters

Parse `$ARGUMENTS`:

- `prp-name` (required): Name of PRP file in `docs/prps/` (without .md extension)
  - Example: `feature-auth-oauth2` → loads `docs/prps/feature-auth-oauth2.md`

## Execution

Execute the complete PRP implementation workflow:

### Step 1: Load and validate PRP

1. Read PRP file: `docs/prps/{prp-name}.md`
2. Extract confidence score from frontmatter
3. If confidence < 7 → Error: "PRP confidence too low. Run `/blueprint:prp-create {prp-name}` to refine"
4. If confidence >= 9 → Offer delegation: "This PRP has high confidence. Execute now (current session) or create work-order for delegation?"
   - If work-order chosen → Run `/blueprint:work-order --from-prp {prp-name}` and exit
   - If delegation to multiple subagents chosen → Create focused work-orders per module from Implementation Blueprint and exit
5. Continue to Step 2 if executing now OR confidence 7-8
6. Load all referenced ai_docs entries for context
7. Parse Implementation Blueprint and create TodoWrite entries ordered by dependencies

### Step 2: Establish baseline with validation gates

Run pre-implementation validation gates (see [REFERENCE.md](REFERENCE.md#validation-gates)) to establish clean starting state:

1. Linting gate: `[command from PRP]` - Expected: PASS
2. Existing tests gate: `[command from PRP]` - Expected: PASS

If gates fail:
- Document existing issues
- Decide: fix first or proceed with note
- Continue when ready

### Step 3: Execute TDD implementation cycle

For each task in Implementation Blueprint:

1. **RED phase**: Write failing test matching PRP TDD Requirements
   - Create test file if needed
   - Run tests → Confirm FAILURE (test is meaningful)

2. **GREEN phase**: Implement minimal code to pass test
   - Follow Codebase Intelligence patterns from PRP
   - Apply patterns from ai_docs references
   - Watch for Known Gotchas
   - Run tests → Confirm SUCCESS

3. **REFACTOR phase**: Improve code while keeping tests green
   - Extract common patterns
   - Improve naming, add type hints
   - Follow project conventions
   - Run tests → Confirm PASS
   - Run validation gates frequently (not just at end)

4. **Mark progress**: Update TodoWrite: `✅ Task N: [Description]`

### Step 4: Run comprehensive final validation

Execute all validation gates from PRP (see [REFERENCE.md](REFERENCE.md#validation-gates)):
- Linting: `[cmd]` - Expected: PASS
- Type checking: `[cmd]` - Expected: PASS
- Unit tests: `[cmd]` - Expected: PASS (all tests)
- Integration tests: `[cmd]` - Expected: PASS (if applicable)
- Coverage check: `[cmd]` - Expected: Meets threshold
- Security scan: `[cmd]` - Expected: No high/critical issues (if applicable)
- Performance tests: `[cmd]` - Expected: Meets baseline (if defined)

Verify each success criterion from PRP.

### Step 5: Document deferred items

Identify and track any deferred work:

1. Review Implementation Blueprint - items not completed
2. Categorize each deferred item:
   - **Phase 2 (Required)**: Must have GitHub issues created
   - **Nice-to-Have**: Optional, no issue required
   - **Blocked**: Cannot complete - document blocker, create issue
3. Create GitHub issues for all Phase 2 and Blocked items (see [REFERENCE.md](REFERENCE.md#deferred-items-workflow))
4. Update PRP with deferred items section linking to GitHub issues
5. Do NOT proceed to Step 6 until all required issues are created

### Step 6: Sync feature tracker (if enabled)

If feature tracker exists (`docs/blueprint/feature-tracker.json`):

1. Identify which feature codes (e.g., FR2.1) were addressed from PRP
2. Update feature tracker for each code:
   - Status: `complete` (all criteria met) or `partial` (some criteria met) or `in_progress`
   - Files: List of modified/created files
   - Tests: List of test files
   - Commits: Commit hashes
   - Notes: Implementation notes
3. Recalculate statistics: completion percentages, phase status
4. Update TODO.md: Check boxes for completed features
5. Report feature tracker changes

### Step 7: Report results and next steps

Generate comprehensive execution summary report:

- **Tasks completed**: X/Y
- **Tests added**: N
- **Files modified**: [list]
- **Validation results**: Table of all gates (PASS/FAIL status)
- **Success criteria**: All verified
- **Deferred items summary**: Count and GitHub issue numbers
- **Feature tracker updates**: Features updated and percentages
- **New gotchas discovered**: [documented for future reference]
- **Recommendations**: Follow-up work or ai_docs updates

Prompt user for next action:
- Commit changes (Recommended) → Run `/git:commit`
- Create work-order for follow-up → Run `/blueprint:work-order`
- Update ai_docs with patterns → Run `/blueprint:curate-docs`
- Continue to next PRP → Run `/blueprint:prp-execute [next]`
- Done for now → Exit

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Check PRP exists | `test -f docs/prps/${1}.md && echo "EXISTS" \|\| echo "MISSING"` |
| Extract confidence | `head -50 docs/prps/${1}.md \| grep -m1 "^confidence:" \| sed 's/^[^:]*:[[:space:]]*//'` |
| List all PRPs | `ls docs/prps/*.md 2>/dev/null \| xargs basename -s .md` |
| Check feature tracker | `test -f docs/blueprint/feature-tracker.json && echo "YES" \|\| echo "NO"` |
| Fast validation | Run validation gates in parallel when possible |

---

For detailed validation gate definitions, deferred items workflow, error handling procedures, and agent team coordination, see [REFERENCE.md](REFERENCE.md).
