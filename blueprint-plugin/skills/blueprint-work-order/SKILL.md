---
created: 2025-12-16
modified: 2026-10-09
reviewed: 2026-04-25
description: Create a work-order for isolated subagent execution, optionally linked to a GitHub issue. Use when breaking a PRP into delegatable tasks or spawning from an issue.
args: "[--no-publish] [--from-issue N]"
argument-hint: "--no-publish for local-only, --from-issue 123 to create from existing issue"
allowed-tools: Read, Write, Glob, Bash, AskUserQuestion
name: blueprint-work-order
---

Generate a work-order document for isolated subagent execution with optional GitHub issue integration.

## When to Use This Skill

| Use this skill when... | Use blueprint-prp-create instead when... |
|---|---|
| You're breaking a PRP into delegatable subagent tasks | You're creating the PRP itself with full research and validation gates |
| You want a focused TDD task packet with minimal context | You need a comprehensive context-gathered implementation plan |
| You want to spawn a work-order from an existing PRP (`--from-prp`) | Use blueprint-prp-execute instead when running an already-written PRP |
| You're creating a work-order from a GitHub issue (`--from-issue`) | Use confidence-scoring instead to evaluate readiness before delegating |

## Flags

| Flag | Description |
|------|-------------|
| `--no-publish` | Create local work-order only, skip GitHub issue creation |
| `--from-issue N` | Create work-order from existing GitHub issue #N (a `work-order-draft` proposal issue is promoted: packet consumed, label swapped to `work-order`) |
| `--from-prp NAME` | Create work-order from existing PRP (auto-populates context) |

**Default behavior**: Creates both local work-order AND GitHub issue with `work-order` label.

## Interaction Mode

Before any closing `AskUserQuestion` menu, resolve the automation config:

```bash
bash "${CLAUDE_SKILL_DIR}/../../scripts/get-automation-config.sh"
```

When `EFFECTIVE_INTERACTION_MODE=quiet` **and** this invocation was
automation-initiated (autopilot, session bookend, drift-nudge follow-up — not
a slash command the user typed), skip closing navigation menus ("what next?" /
"create another?" style): apply the safe default and end with a one-line
receipt instead. Quiet mode never skips confirmation gates that guard writes —
only navigation menus. A direct user invocation always behaves fully
interactively (explicit intent overrides quiet; see ADR-0020).

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
   - Note curated-rule references (`.claude/rules/` entries)

3. **Verify confidence**:
   - If confidence < 9: Warn that PRP may not be ready for delegation
   - Ask to proceed anyway or return to refine PRP

4. **Generate work-order**:
   - Pre-populate from PRP content
   - Include relevant curated rules as inline context (not references)
   - Copy TDD requirements verbatim
   - Include file list from PRP's Codebase Intelligence section

5. **Continue to Step 6** (save and optionally publish)

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

2a. **Promote a `work-order-draft` proposal** (ADR-0020 auto-draft channel):

   If the issue carries the `work-order-draft` label, it is an auto-drafted
   proposal from `/blueprint:autopilot` — its body already IS the full
   work-order packet (title form `[work-order-draft] PRP-NNN: <title>`).
   Promotion is the human committing act the draft channel preserves:
   - Consume the packet verbatim as the work-order content (the draft body
     supersedes step 3's re-generation; still verify the referenced PRP exists
     and its confidence is current — warn if it dropped below 9)
   - In step 4, additionally swap the labels:
     `gh issue edit N --remove-label "work-order-draft" --add-label "work-order"`
   - Proceed with the normal save path (Step 6): the local WO file,
     `feature-tracker.json` `tasks.pending`, and the manifest `id_registry`
     mutate HERE, at promotion — never at draft time

3. **Generate work-order**:
   - Number matches issue number (e.g., issue #42 → work-order `042-...`)
   - Pre-populate from issue content
   - Add context sections (files, PRD reference, etc.)

4. **Update issue with link**:
   ```bash
   gh issue comment N --body "Work-order created: \`docs/blueprint/work-orders/NNN-task-name.md\`"
   # Ensure the label exists before applying it
   if ! gh label list --search "work-order" --json name | jq -e '.[] | select(.name=="work-order")' >/dev/null 2>&1; then
     gh label create work-order --description "AI-assisted work order" --color "0E8A16"
   fi
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

Use the template in [references/work-order-template.md](references/work-order-template.md): frontmatter (`id`, `status`, `implements`, `relates-to`, `github-issues`), then Objective, Context, TDD Requirements, Implementation Steps, Success Criteria, Notes, and Related Work-Orders.

### Step 6: Save Work-Order

Save to `docs/blueprint/work-orders/NNN-task-name.md`
Ensure zero-padded numbering (001, 002, 010, 100)

### Step 7: Create GitHub Issue (unless `--no-publish`)

Create the issue (title `[WO-NNN] [Task Name]`, label `work-order`) and capture its number with the commands in [references/github-publishing.md](references/github-publishing.md).

Update the `**GitHub Issue**:` line in the work-order file with the issue number.

### Step 8: Update `docs/blueprint/feature-tracker.json`

Add new work-order to pending tasks:
```bash
jq '.tasks.pending += [{"id": "WO-NNN", "description": "[Task name]", "source": "PRP-NNN", "added": "YYYY-MM-DD"}]' \
  docs/blueprint/feature-tracker.json > tmp.json && mv tmp.json docs/blueprint/feature-tracker.json
```

### Step 8.5: Update Manifest

Update `docs/blueprint/manifest.json` ID registry:

Add the `documents.WO-NNN` and `github_issues` entries shown in [references/id-registry-entry.md](references/id-registry-entry.md).

Also update the source PRP/PRD to add this work-order to its tracking.

### Step 9: Report

Print the report in [references/report-template.md](references/report-template.md).

### Step 10: Prompt for Next Action

Ask with the prompt in [references/next-action-prompt.md](references/next-action-prompt.md).

**Based on selection:**
- "Execute this work-order" → Run `/project:continue` with work-order context
- "Create another work-order" → Run `/blueprint:work-order` again
- "Delegate to subagent" → Provide handoff instructions for subagent execution
- "I'm done" → Exit

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

## GitHub Integration Notes

Completion flow (`Fixes #N` auto-closes the issue), the `work-order` label convention, and offline mode: [references/github-publishing.md](references/github-publishing.md).
