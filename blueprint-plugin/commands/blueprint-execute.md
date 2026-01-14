---
created: 2026-01-14
modified: 2026-01-14
reviewed: 2026-01-14
description: "Idempotent meta command that determines and executes the next logical blueprint action"
allowed_tools: [Read, Glob, Bash, AskUserQuestion, SlashCommand]
---

Intelligent meta command that analyzes repository state and executes the appropriate blueprint action.

**Concept**: Run this command anytime to automatically determine what should happen next in your blueprint workflow. Safe to run repeatedly - it's idempotent and will always figure out the right action.

**Usage**: `/blueprint:execute`

**How it works**: This command acts as an orchestrator, detecting your project's current state and delegating to specific blueprint commands as needed.

---

## State Detection & Action Flow

Run through these checks in order, executing the first matching action:

### 1. Check Initialization

```bash
# Check if blueprint is initialized
test -f docs/blueprint/manifest.json
```

**If NOT initialized**:
- Report: "Blueprint not initialized in this project."
- **Action**: Run `/blueprint-init`
- **Exit** after initialization completes

**If initialized**: Continue to step 2

---

### 2. Check for Upgrades

Read `docs/blueprint/manifest.json` and check `format_version`:

```bash
cat docs/blueprint/manifest.json | grep '"format_version"'
```

**Current format version**: 3.0.0

**If manifest version < 3.0.0**:
- Report: "Blueprint upgrade available: v{current} → v3.0.0"
- **Action**: Run `/blueprint-upgrade`
- **Exit** after upgrade completes

**If up to date**: Continue to step 3

---

### 3. Check for Stale/Modified Generated Content

Read manifest.json `generated` section and check each generated rule:

```bash
# For each generated rule, compute hash and compare
for rule in .claude/rules/*.md; do
  current_hash=$(sha256sum "$rule" | cut -d' ' -f1)
  # Compare with manifest stored hash
done
```

**If stale content detected** (PRDs changed since generation):
- Report: "Stale generated content detected: {count} files (PRDs changed)"
- Use AskUserQuestion:
  ```
  question: "Generated content is out of sync with PRDs. What would you like to do?"
  options:
    - label: "Regenerate from PRDs (Recommended)"
      description: "Update generated rules to match current PRD content"
    - label: "Skip for now"
      description: "Continue with other actions"
  ```
- **If "Regenerate"**: Run `/blueprint-generate-rules`, then **Exit**
- **If "Skip"**: Continue to step 4

**If modified content detected** (user edited generated files):
- Report: "Modified generated content: {count} files (locally edited)"
- Use AskUserQuestion:
  ```
  question: "You've modified generated content. What would you like to do?"
  options:
    - label: "Review changes"
      description: "Run /blueprint-sync to see what changed"
    - label: "Promote to custom layer"
      description: "Move edited files to custom layer to prevent regeneration"
    - label: "Skip for now"
      description: "Continue with other actions"
  ```
- **If "Review"**: Run `/blueprint-sync`, then **Exit**
- **If "Promote"**: Ask which file to promote, run `/blueprint-promote [name]`, then **Exit**
- **If "Skip"**: Continue to step 4

**If content is current**: Continue to step 4

---

### 4. Check for PRDs Without Generated Rules

```bash
# Count PRDs
prd_count=$(find docs/prds -name "*.md" 2>/dev/null | wc -l)

# Count generated rules in manifest
generated_count=$(cat docs/blueprint/manifest.json | jq '.generated.rules | length')
```

**If prd_count > 0 AND generated_count == 0**:
- Report: "Found {prd_count} PRDs but no generated rules"
- **Action**: Run `/blueprint-generate-rules`
- **Exit** after generation completes

**If rules exist or no PRDs**: Continue to step 5

---

### 5. Check for Ready PRPs

```bash
# Find PRPs in docs/prps/
find docs/prps -name "*.md" -type f 2>/dev/null
```

**If PRPs found**:
- List all PRPs with their confidence scores (if present in frontmatter)
- Use AskUserQuestion:
  ```
  question: "Found {count} PRP(s). Which would you like to execute?"
  options:
    - label: "{prp-1-name} (confidence: {score})"
      description: "Execute this PRP with TDD workflow"
    - label: "{prp-2-name} (confidence: {score})"
      description: "Execute this PRP with TDD workflow"
    # ... for each PRP
    - label: "Skip PRP execution"
      description: "Continue to other actions"
  ```
- **If PRP selected**: Run `/blueprint-prp-execute {selected-prp}`, then **Exit**
- **If "Skip"**: Continue to step 6

**If no PRPs**: Continue to step 6

---

### 6. Check for Pending Work-Orders

```bash
# Find pending work-orders
find docs/blueprint/work-orders -maxdepth 1 -name "*.md" -type f 2>/dev/null
```

**If work-orders found**:
- List all pending work-orders
- Use AskUserQuestion:
  ```
  question: "Found {count} pending work-order(s). What would you like to do?"
  options:
    - label: "Execute: {work-order-1}"
      description: "Run this work-order"
    - label: "Execute: {work-order-2}"
      description: "Run this work-order"
    # ... for each work-order
    - label: "Skip work-orders"
      description: "Continue to other actions"
  ```
- **If work-order selected**:
  - Read and execute the work-order
  - Move to `completed/` when done
  - **Exit**
- **If "Skip"**: Continue to step 7

**If no work-orders**: Continue to step 7

---

### 7. Check Work Overview for Next Tasks

```bash
# Read work-overview.md
cat docs/blueprint/work-overview.md
```

Parse the "In Progress" and "Pending" sections:
- Extract task items
- Check if any are actionable

**If in-progress tasks found**:
- Report: "Found {count} in-progress tasks in work-overview.md"
- Use AskUserQuestion:
  ```
  question: "You have in-progress tasks. What would you like to do?"
  options:
    - label: "Continue current work"
      description: "Work on: {first-in-progress-task}"
    - label: "Create PRP for task"
      description: "Create detailed PRP for systematic execution"
    - label: "Create work-order for task"
      description: "Package task for subagent execution"
    - label: "Skip to pending tasks"
      description: "Move to pending items instead"
  ```
- **Action based on selection**, then **Exit**

**If pending tasks found** (and no in-progress):
- Report: "Found {count} pending tasks in work-overview.md"
- Use AskUserQuestion:
  ```
  question: "You have pending tasks. What would you like to do?"
  options:
    - label: "Start: {first-pending-task}"
      description: "Begin work on this task"
    - label: "Create PRP for task"
      description: "Create detailed PRP for systematic execution"
    - label: "Create work-order for task"
      description: "Package task for subagent execution"
    - label: "Skip for now"
      description: "Continue to other checks"
  ```
- **Action based on selection**
- **Exit** if action taken, otherwise continue to step 8

**If no clear tasks**: Continue to step 8

---

### 8. Check Feature Tracker (If Enabled)

```bash
# Check if feature tracker exists
test -f docs/blueprint/feature-tracker.json
```

**If feature tracker exists**:

a. Check staleness:
```bash
# Get last_updated from tracker
last_sync=$(cat docs/blueprint/feature-tracker.json | jq -r '.last_updated // empty')
# Compare with current date (warn if > 7 days)
```

**If stale** (> 7 days old):
- Report: "Feature tracker hasn't been synced in {days} days"
- **Action**: Run `/blueprint-feature-tracker-sync`
- Continue to step 8b after sync

b. Show incomplete features:
```bash
# Get statistics
cat docs/blueprint/feature-tracker.json | jq '.statistics'
```

- Report completion status
- List next incomplete features
- Use AskUserQuestion:
  ```
  question: "Feature tracker shows {complete}/{total} features complete. Next steps?"
  options:
    - label: "Work on: {next-incomplete-feature}"
      description: "Start implementing this feature"
    - label: "View feature status"
      description: "Run /blueprint-feature-tracker-status for details"
    - label: "Sync tracker"
      description: "Update tracker with latest progress"
    - label: "Continue to status"
      description: "Move to general status check"
  ```
- **Action based on selection**, then **Exit**

**If no feature tracker**: Continue to step 9

---

### 9. No Clear Next Action - Show Status & Options

When no automatic action is determined, show comprehensive status and options.

**Action**: Run `/blueprint-status`

This will:
- Display full blueprint status
- Show three-layer architecture
- List available next actions
- Prompt user for what to do next

**Exit** after status completes.

---

## Idempotency Guarantees

This command is safe to run repeatedly because:

1. **State detection is read-only**: Only reads files, doesn't modify until action is chosen
2. **Single action execution**: Executes ONE action per run, then exits
3. **User confirmation**: Critical actions prompt before executing
4. **Consistent state**: Each action leaves project in valid state
5. **No side effects**: Re-running after completion shows status, doesn't re-execute

## Examples

### Example 1: Uninitialized Project

```bash
$ /blueprint:execute
```

Output:
```
Blueprint not initialized in this project.

Initializing blueprint structure...
[Runs /blueprint-init]
```

### Example 2: Has Ready PRPs

```bash
$ /blueprint:execute
```

Output:
```
Blueprint Status: ✅ Up to date (v3.0.0)

Found 2 ready PRPs:
1. add-authentication.md (confidence: 9/10)
2. optimize-performance.md (confidence: 8/10)

[Prompts: Which PRP to execute?]
```

### Example 3: All Caught Up

```bash
$ /blueprint:execute
```

Output:
```
Blueprint Status: ✅ Up to date (v3.0.0)

No pending PRPs, work-orders, or stale content detected.

[Shows full status from /blueprint-status]
[Prompts: What would you like to do next?]
```

### Example 4: Stale Generated Content

```bash
$ /blueprint:execute
```

Output:
```
Blueprint Status: ⚠️ Attention needed

Stale generated content detected: 2 files
- architecture-patterns.md (PRD changed on 2026-01-13)
- testing-strategies.md (PRD changed on 2026-01-12)

[Prompts: Regenerate from PRDs?]
```

## Benefits

1. **Reduced cognitive load**: Don't need to remember which command to run
2. **Progressive workflow**: Naturally guides through blueprint methodology
3. **Safe exploration**: Can run anytime without breaking things
4. **Smart defaults**: Automatically picks the right action for current state
5. **Flexible**: Can skip actions and continue to next check
6. **Always actionable**: Always suggests next steps, never leaves you stuck

## Integration with Existing Commands

This meta command **delegates** to existing blueprint commands rather than replacing them:

- Users can still run specific commands directly when they know what they want
- `/blueprint:execute` is for when you want the system to decide
- Both approaches work together seamlessly

## Common Workflows

### Morning Start Routine
```bash
$ /blueprint:execute  # Figures out where you left off
```

### After Pulling Changes
```bash
$ /blueprint:execute  # Checks for stale content, upgrades, etc.
```

### Periodic Check-in
```bash
$ /blueprint:execute  # Shows progress, suggests next work
```

### Stuck or Unsure
```bash
$ /blueprint:execute  # Always knows what to do next
```

---

**Note**: This is a meta-orchestrator command. It analyzes state and delegates to specific blueprint commands. It's designed to be the "smart entry point" for blueprint workflow while preserving access to individual commands for power users.
