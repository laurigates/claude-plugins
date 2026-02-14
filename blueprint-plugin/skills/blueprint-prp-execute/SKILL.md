---
model: opus
description: "Execute a PRP with validation loop, TDD workflow, and quality gates"
args: "[prp-name]"
argument-hint: "Name of PRP to execute (e.g., feature-auth-oauth2)"
allowed-tools: Read, Write, Edit, Glob, Bash, Task, AskUserQuestion
created: 2025-12-16
modified: 2026-02-14
reviewed: 2025-12-16
name: blueprint-prp-execute
---

Execute a PRP (Product Requirement Prompt) with systematic implementation and validation.

**Usage**: `/blueprint:prp-execute [prp-name]`

**Prerequisites**:
- PRP exists in `docs/prps/[prp-name].md`
- Confidence score >= 7 (if lower, suggest `/blueprint:prp-create` refinement)

For detailed report templates, deferred items workflow, feature tracker sync, and error handling patterns, see [REFERENCE.md](REFERENCE.md).

---

## Phase 1: Load Context

### 1.1 Read PRP

```bash
cat docs/prps/$PRP_NAME.md
```

### 1.2 Verify Confidence Score

| Score | Action |
|-------|--------|
| >= 9 | Ready for autonomous execution (or delegation) |
| 7-8 | Proceed with some discovery expected |
| < 7 | **STOP** - Recommend refinement first |

### 1.3 Offer Delegation (Confidence >= 9)

If confidence >= 9, use AskUserQuestion to offer:
- **Execute now** (current session) - Continue to Phase 2
- **Create work-order for delegation** - Run `/blueprint:work-order --from-prp {prp-name}`, then **Exit**
- **Create multiple work-orders** - Split into independent tasks for parallel execution, then **Exit**

### 1.4 Read ai_docs References

Load all referenced ai_docs entries: `ai_docs/libraries/*.md`, `ai_docs/project/patterns.md`.

### 1.5 Plan Execution

Based on the Implementation Blueprint:
1. Create TodoWrite entries for each task
2. Order by dependencies
3. Identify validation checkpoints

---

## Phase 2: Run Initial Validation Gates

Run validation gates to establish baseline:

```bash
# Gate 1: Ensure linting passes before changes
[linting command from PRP]

# Gate 2: Ensure existing tests pass
[test command from PRP]
```

**If gates fail**: Document existing issues, decide whether to fix first or proceed.

---

## Phase 3: TDD Implementation

For each task in Implementation Blueprint:

### 3.1 Write Tests First (RED)

Write test case as specified in PRP. Run tests - expected: new test **FAILS**.

### 3.2 Implement Minimal Code (GREEN)

Write minimum code to pass the test. Follow patterns from Codebase Intelligence and ai_docs. Watch for Known Gotchas. Run tests - expected: test **PASSES**.

### 3.3 Refactor (REFACTOR)

Improve code while keeping tests green: extract patterns, improve naming, add type hints, follow conventions. Run tests - expected: tests **STILL PASS**.

### 3.4 Run Validation Gates

After each significant change:

```bash
# Gate 1: Linting
[linting command]

# Gate 2: Type checking
[type check command]

# Gate 3: Unit tests
[test command]
```

**If any gate fails**: Fix, re-run, continue only when passing.

### 3.5 Update Progress

Mark task as complete in TodoWrite.

---

## Phase 4: Final Validation

### 4.1 Run All Validation Gates

Execute every gate from the PRP: linting, type checking, unit tests, integration tests, coverage check, security scan (if applicable).

### 4.2 Verify Success Criteria

Check each success criterion from PRP against actual results.

### 4.3 Check Performance Baselines

If performance baselines defined, run performance tests and compare to targets.

---

## Phase 4.5: Deferred Items Report

Review the PRP's Implementation Blueprint and identify deferred Phase 2, Nice-to-Have, and blocked items. Create GitHub issues for all Phase 2 and blocked items. Update PRP with deferred items section.

See [REFERENCE.md](REFERENCE.md) for deferred items table format and GitHub issue template.

**Important**: Do not proceed to Phase 5 until all Phase 2 and blocked items have GitHub issues created.

---

## Phase 5: Sync Feature Tracker

Check if `docs/blueprint/feature-tracker.json` exists. If enabled:

1. **Identify** which FR codes were addressed by completed tasks
2. **Update status** for each FR code (complete, partial, in_progress)
3. **Recalculate statistics** (counts, completion percentage, phase status)
4. **Sync documentation** (update TODO.md checkboxes)

See [REFERENCE.md](REFERENCE.md) for feature tracker update format and sync details.

---

## Phase 6: Report

### 6.1 Execution Summary

Generate completion report covering: implementation summary (tasks, tests, files), validation results table, success criteria verification, deferred items summary, feature tracker status, new gotchas discovered, and recommendations.

See [REFERENCE.md](REFERENCE.md) for the full report template.

### 6.2 Update ai_docs

If new patterns or gotchas discovered, update relevant ai_docs entries.

### 6.3 Mark PRP Complete

Annotate PRP as executed:
```markdown
## Status: EXECUTED
**Executed on**: [date]
**Commit**: [hash]
**Notes**: [any notes]
```

### 6.4 Prompt for Next Action

Use AskUserQuestion to offer: commit changes, create work-order for follow-up, update ai_docs, continue to next PRP, or exit.

---

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Execute PRP | `/blueprint:prp-execute {name}` |
| Quick test loop | `[test command] --dots --bail=1` |
| Lint check | `[lint command] --reporter=github` |
| Delegate instead | `/blueprint:work-order --from-prp {name}` |

## Tips

- Trust the PRP - it was researched for a reason
- Run validation gates frequently (not just at the end)
- Document any new gotchas discovered
- Update ai_docs with lessons learned
- Commit after each passing validation cycle
