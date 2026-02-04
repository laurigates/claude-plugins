---
model: opus
created: 2025-12-16
modified: 2026-01-09
reviewed: 2025-12-26
description: "Create work-order with minimal context for isolated subagent execution, optionally linked to GitHub issue"
args: "[--no-publish] [--from-issue N]"
argument-hint: "--no-publish for local-only, --from-issue 123 to create from existing issue"
allowed_tools: [Read, Write, Glob, Bash, AskUserQuestion]
---

Generate a work-order document for isolated subagent execution with optional GitHub issue integration.

## Flags

| Flag | Description |
|------|-------------|
| `--no-publish` | Create local work-order only, skip GitHub issue creation |
| `--from-issue N` | Create work-order from existing GitHub issue #N |
| `--from-prp NAME` | Create work-order from existing PRP (auto-populates context) |

**Default behavior**: Creates both local work-order AND GitHub issue with `work-order` label.

## Prerequisites

- Blueprint Development initialized (`docs/blueprint/` exists)
- At least one PRD exists (unless using `--from-issue` or `--from-prp`)
- `gh` CLI authenticated (unless using `--no-publish`)

---

## Mode: Create from PRP (`--from-prp NAME`)

When `--from-prp NAME` is provided:

1. **Read PRP**:
   ```bash
   cat docs/prps/$NAME.md
   ```

2. **Extract PRP content**:
   - Parse frontmatter for id, confidence score, implements references
   - Extract Objective section
   - Extract Implementation Blueprint tasks
   - Extract TDD Requirements
   - Extract Success Criteria
   - Note ai_docs references

3. **Verify confidence**:
   - If confidence < 9: Warn that PRP may not be ready for delegation
   - Ask to proceed anyway or return to refine PRP

4. **Generate work-order**:
   - Pre-populate from PRP content
   - Include relevant ai_docs as inline context (not references)
   - Copy TDD requirements verbatim
   - Include file list from PRP's Codebase Intelligence section

5. **Continue to Step 6** (save and optionally publish)

---

## Mode: Create from Existing Issue (`--from-issue N`)

When `--from-issue N` is provided:

1. **Fetch issue**:
   ```bash
   gh issue view N --json title,body,labels,number
   ```

2. **Parse issue content**:
   - Extract objective from title/body
   - Extract any TDD requirements or success criteria if present
   - Note existing labels

3. **Generate work-order**:
   - Number matches issue number (e.g., issue #42 → work-order `042-...`)
   - Pre-populate from issue content
   - Add context sections (files, PRD reference, etc.)

4. **Update issue with link**:
   ```bash
   gh issue comment N --body "Work-order created: \`docs/blueprint/work-orders/NNN-task-name.md\`"
   gh issue edit N --add-label "work-order"
   ```

5. **Continue to save and report** (skip to Step 6 below)

---

## Mode: Create New Work-Order (Default)

### Step 1: Analyze Current State

- Read `docs/blueprint/feature-tracker.json` for current phase and tasks
- Run `git status` to check uncommitted work
- Run `git log -5 --oneline` to see recent work
- Find existing work-orders (count them for numbering)

### Step 2: Read Relevant PRDs

- Read PRD files to understand requirements
- Identify next logical work unit based on:
  * Work-overview progress
  * PRD phase/section ordering
  * Git history (what's been done)

### Step 3: Determine Next Work Unit

Should be:
* **Specific**: Single feature/component/fix
* **Isolated**: Minimal dependencies
* **Testable**: Clear success criteria
* **Focused**: 1-4 hours of work

**Good examples**:
- "Implement JWT token generation methods"
- "Add input validation to registration endpoint"
- "Create database migration for users table"

**Bad examples** (too broad):
- "Implement authentication"
- "Fix bugs"

### Step 4: Determine Minimal Context

- **Files to modify/create** (only relevant ones)
- **PRD sections** (only specific requirements for this task)
- **Existing code** (only relevant excerpts, not full files)
- **Dependencies** (external libraries, environment variables)

### Step 5: Generate Work-Order

- Number: Find highest existing work-order number + 1 (001, 002, etc.)
- Name: `NNN-brief-task-description.md`

**Work-order structure**:

```markdown
---
id: WO-NNN
created: {YYYY-MM-DD}
status: pending
implements:                    # Source PRP or PRD
  - PRP-NNN
relates-to:                    # Related documents
  - ADR-NNNN
github-issues:
  - N
---

# Work-Order NNN: [Task Name]

**ID**: WO-NNN
**GitHub Issue**: #N
**Status**: pending

## Objective
[One sentence describing what needs to be accomplished]

## Context

### Required Files
[Only files needed - list with purpose]

### PRD Reference
[Link to specific PRD section, not entire PRD]

### Technical Decisions
[Only decisions relevant to this specific task]

### Existing Code
[Only relevant code excerpts needed for integration]

## TDD Requirements

### Test 1: [Test Description]
[Exact test to write, with code template]
**Expected Outcome**: Test should fail

### Test 2: [Test Description]
[Exact test to write]
**Expected Outcome**: Test should fail

[More tests as needed]

## Implementation Steps

1. **Write Test 1** - Run: `[test_command]` - Expected: **FAIL**
2. **Implement Test 1** - Run: `[test_command]` - Expected: **PASS**
3. **Refactor (if needed)** - Run: `[test_command]` - Expected: **STILL PASS**
[Repeat for all tests]

## Success Criteria
- [ ] All specified tests written and passing
- [ ] [Specific functional requirement met]
- [ ] [Performance/security baseline met]
- [ ] No regressions (existing tests pass)

## Notes
[Additional context, gotchas, considerations]

## Related Work-Orders
- **Depends on**: Work-Order NNN (if applicable)
- **Blocks**: Work-Order NNN (if applicable)
```

---

### Step 6: Save Work-Order

Save to `docs/blueprint/work-orders/NNN-task-name.md`
Ensure zero-padded numbering (001, 002, 010, 100)

### Step 7: Create GitHub Issue (unless `--no-publish`)

```bash
gh issue create \
  --title "[WO-NNN] [Task Name]" \
  --body "## Work Order: [Task Name]

**ID**: WO-NNN
**Local Context**: \`docs/blueprint/work-orders/NNN-task-name.md\`

### Related Documents
- **Implements**: {PRP-NNN or PRD-NNN}
- **Related ADRs**: {list of ADR-NNNN}

### Objective
[One-line objective from work order]

### TDD Requirements
- [ ] Test 1: [description]
- [ ] Test 2: [description]

### Success Criteria
- [ ] [Criterion 1]
- [ ] [Criterion 2]

---
*AI-assisted development work order. See linked file for full execution context.*" \
  --label "work-order"
```

Capture issue number and update work-order file:
```bash
# Extract issue number from gh output
gh issue create ... 2>&1 | grep -oE '#[0-9]+' | head -1
```

Update the `**GitHub Issue**:` line in the work-order file with the issue number.

### Step 8: Update `docs/blueprint/feature-tracker.json`

Add new work-order to pending tasks:
```bash
jq '.tasks.pending += [{"id": "WO-NNN", "description": "[Task name]", "source": "PRP-NNN", "added": "YYYY-MM-DD"}]' \
  docs/blueprint/feature-tracker.json > tmp.json && mv tmp.json docs/blueprint/feature-tracker.json
```

### Step 8.5: Update Manifest

Update `docs/blueprint/manifest.json` ID registry:

```json
{
  "id_registry": {
    "documents": {
      "WO-NNN": {
        "path": "docs/blueprint/work-orders/NNN-task-name.md",
        "title": "[Task Name]",
        "implements": ["PRP-NNN"],
        "github_issues": [N],
        "created": "{date}"
      }
    },
    "github_issues": {
      "N": ["WO-NNN", "PRP-NNN"]
    }
  }
}
```

Also update the source PRP/PRD to add this work-order to its tracking.

### Step 9: Report

```
Work-order created!

ID: WO-NNN
Work-Order: 003-jwt-token-generation.md
Location: docs/blueprint/work-orders/003-jwt-token-generation.md
GitHub Issue: #42 (or "Local only" if --no-publish)

Traceability:
- Implements: PRP-002 (OAuth Integration)
- Related: ADR-0003 (Session Storage)

Objective: [Brief objective]

Context included:
- Files: [List files]
- Tests: [Number of tests specified]
- Dependencies: [Key dependencies]

Ready for execution:
- Can be executed by subagent with isolated context
- TDD workflow enforced (tests specified first)
- Clear success criteria defined
- PR should use "Fixes #42" to auto-close issue
- Commit messages should use: feat(WO-NNN): description
```

### Step 10: Prompt for Next Action

Use AskUserQuestion:
```
question: "Work-order ready. What would you like to do?"
options:
  - label: "Execute this work-order (Recommended)"
    description: "Start working on the task with TDD workflow"
  - label: "Create another work-order"
    description: "Generate the next task from pending items"
  - label: "Delegate to subagent"
    description: "Hand off for isolated execution"
  - label: "I'm done for now"
    description: "Exit - work-order is saved and ready"
```

**Based on selection:**
- "Execute this work-order" → Run `/project:continue` with work-order context
- "Create another work-order" → Run `/blueprint:work-order` again
- "Delegate to subagent" → Provide handoff instructions for subagent execution
- "I'm done" → Exit

---

## Key Principles

- **Minimal context**: Only what's needed, not full files/PRDs
- **Specific tests**: Exact test cases, not vague descriptions
- **TDD enforced**: Tests specified before implementation
- **Clear criteria**: Unambiguous success checkboxes
- **Isolated**: Task should be doable with only provided context
- **Transparent**: GitHub issue provides visibility to collaborators

---

## Error Handling

| Condition | Action |
|-----------|--------|
| No PRDs exist | Guide to write PRDs first |
| No tasks in feature-tracker | Ask for current phase/status |
| Task unclear | Ask user what to work on next |
| `gh` not authenticated | Warn and fallback to `--no-publish` behavior |
| Issue already has `work-order` label | Warn, ask to update or create new |

---

## GitHub Integration Notes

### Completion Flow
1. Work completed on work-order
2. PR created with `Fixes #N` in body/title
3. Work-order moved to `completed/` directory
4. Issue auto-closes when PR merges

### Label Convention
The `work-order` label identifies issues created from this workflow. Create it in your repo if it doesn't exist:
```bash
gh label create work-order --description "AI-assisted work order" --color "0E8A16"
```

### Offline Mode
Use `--no-publish` when:
- Working offline
- Private experimentation
- Issue visibility not needed

Can publish later by manually creating issue and updating work-order file.
