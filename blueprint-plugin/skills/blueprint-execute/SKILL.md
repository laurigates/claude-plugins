---
model: opus
created: 2026-01-14
modified: 2026-02-06
reviewed: 2026-01-30
description: "Idempotent meta command that determines and executes the next logical blueprint action"
allowed-tools: Read, Glob, Bash, AskUserQuestion, SlashCommand, Task
name: blueprint-execute
---

Intelligent meta command that analyzes repository state and executes the appropriate blueprint action.

**Concept**: Run this command anytime to automatically determine what should happen next in your blueprint workflow. Safe to run repeatedly - it's idempotent and will always figure out the right action.

**Usage**: `/blueprint:execute`

**How it works**: This command acts as an orchestrator, detecting your project's current state and delegating to specific blueprint commands as needed. It uses parallel agents for efficient context gathering.

---

## Phase 0: Parallel Context Gathering

Before determining actions, launch parallel agents to gather comprehensive context efficiently:

### 0.1 Launch Parallel Agents

Run these agents **simultaneously** to gather context:

**Agent 1: Git History Analysis**
```
<Task subagent_type="Explore" prompt="Analyze git repository status: recent commits (last 20), branches, any uncommitted changes, conventional commit usage. Return summary with key decisions visible in commit messages.">
```

**Agent 2: Documentation Status**
```
<Task subagent_type="Explore" prompt="Check documentation status: PRDs in docs/prds/, ADRs in docs/adrs/, PRPs in docs/prps/. For each found, extract frontmatter (id, status, confidence). Return counts and actionable items.">
```

**Agent 3: Blueprint State**
```
<Task subagent_type="Explore" prompt="Check blueprint state: manifest.json version, generated rules in .claude/rules/, feature tracker status. Report any staleness or missing components.">
```

### 0.2 Consolidate Agent Results

Merge agent findings into a unified context:
- Git history quality (conventional commits %, recent activity)
- Documentation coverage (PRDs, ADRs, PRPs counts and status)
- Blueprint health (version, staleness, missing components)
- Actionable items (ready PRPs, pending work-orders)

This context informs the action selection below.

name: blueprint-execute
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

name: blueprint-execute
---

### 3. Check for Missing Documentation (Derive Phase)

Check if project has git history but missing documentation:

```bash
# Has git history?
git rev-list --count HEAD 2>/dev/null || echo 0

# Has PRDs?
find docs/prds -name "*.md" 2>/dev/null | wc -l

# Has ADRs?
find docs/adrs -name "*.md" 2>/dev/null | wc -l

# Has derived rules from git?
cat docs/blueprint/manifest.json | jq -r '.derived_rules.last_derived_at // empty'
```

**If git history exists (>10 commits) but NO PRDs and NO ADRs**:
- Report: "Project has git history but no documentation. Derivation recommended."
- Use AskUserQuestion:
  ```
  question: "This project has git history but no PRDs/ADRs. How would you like to derive documentation?"
  options:
    - label: "Derive all from git history (Recommended)"
      description: "Run /blueprint:derive-plans for comprehensive analysis"
    - label: "Derive PRD only"
      description: "Run /blueprint:derive-prd from README and docs"
    - label: "Derive ADRs only"
      description: "Run /blueprint:derive-adr from codebase analysis"
    - label: "Skip derivation"
      description: "I'll create documentation manually"
  ```
- **Action based on selection**, then **Exit**

**If git history exists but NO derived rules**:
- Report: "Git-based rules not yet derived."
- Use AskUserQuestion:
  ```
  question: "Would you like to derive rules from git commit decisions?"
  options:
    - label: "Yes, derive rules from git"
      description: "Run /blueprint:derive-rules to extract decisions from commits"
    - label: "Skip for now"
      description: "Continue with other actions"
  ```
- **If "Yes"**: Run `/blueprint:derive-rules`, then **Exit**
- **If "Skip"**: Continue to step 4

**If documentation exists**: Continue to step 4

---

### 4. Check for Stale/Modified Generated Content

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
- **If "Skip"**: Continue to step 5

**If content is current**: Continue to step 5

name: blueprint-execute
---

### 5. Check for PRDs Without Generated Rules

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

**If rules exist or no PRDs**: Continue to step 6

---

### 6. Check for Ready PRPs

```bash
# Find PRPs in docs/prps/
find docs/prps -name "*.md" -type f 2>/dev/null
```

**If PRPs found**:
- List all PRPs with their confidence scores (if present in frontmatter)
- Count high-confidence PRPs (score >= 9)

**If multiple high-confidence PRPs exist (>= 2 with score >= 9)**:
- Report: "Found {count} high-confidence PRPs ready for delegation"
- Use AskUserQuestion:
  ```
  question: "Multiple PRPs are ready for parallel execution. What would you like to do?"
  options:
    - label: "Create work-orders for all (parallel delegation)"
      description: "Generate work-orders for {count} PRPs to execute in parallel"
    - label: "Execute one PRP now"
      description: "Choose a single PRP to execute in this session"
    - label: "Skip PRP execution"
      description: "Continue to other actions"
  ```
- **If "Create work-orders for all"**:
  - For each high-confidence PRP:
    - Run `/blueprint:work-order --from-prp {prp-name} --no-publish`
  - Report: "Created {count} work-orders. You can now delegate these to subagents."
  - **Exit**

**If single PRP or "Execute one PRP now" selected**:
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
- **If PRP selected**:
  - Run `/blueprint-prp-execute {selected-prp}`
  - Feature tracker sync happens automatically within prp-execute (Phase 5)
  - **Exit**
- **If "Skip"**: Continue to step 7

**If no PRPs**: Continue to step 7

name: blueprint-execute
---

### 7. Check for Pending Work-Orders

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
  - **Sync feature tracker** (if enabled):
    - Check if work-order references FR codes
    - Update feature status based on work-order completion
    - Recalculate statistics
  - **Exit**
- **If "Skip"**: Continue to step 8

**If no work-orders**: Continue to step 8

---

### 8. Check Feature Tracker for Active Tasks

```bash
# Read tasks from feature-tracker.json
cat docs/blueprint/feature-tracker.json | jq '{
  in_progress: .tasks.in_progress,
  pending: .tasks.pending,
  current_phase: .current_phase
}'
```

**If in-progress tasks found**:
- Report: "Found {count} in-progress tasks"
- Use AskUserQuestion:
  ```
  question: "You have in-progress tasks. What would you like to do?"
  options:
    - label: "Continue: {first-task.description}"
      description: "Resume work on [{first-task.id}]"
    - label: "Create work-order for delegation"
      description: "Package current task for subagent execution"
    - label: "Skip to pending tasks"
      description: "Move to pending items instead"
  ```
- **Action based on selection**, then **Exit**

**If pending tasks found** (and no in-progress):
- Report: "Found {count} pending tasks"
- Use AskUserQuestion:
  ```
  question: "You have pending tasks. What would you like to do?"
  options:
    - label: "Start: {first-task.description}"
      description: "Begin work on [{first-task.id}]"
    - label: "Create PRP for task"
      description: "Create detailed PRP for systematic execution"
    - label: "Create work-order for task"
      description: "Package task for subagent execution"
    - label: "Skip for now"
      description: "Continue to other checks"
  ```
- **If task selected**: Move task to in_progress in feature-tracker.json, then work on it
- **If "Create work-order"**: Run `/blueprint:work-order` with task context
- **Exit** if action taken, otherwise continue to step 9

**If no tasks in tracker**: Continue to step 9

name: blueprint-execute
---

### 9. Check Feature Tracker (If Enabled)

```bash
# Check if feature tracker exists
test -f docs/blueprint/feature-tracker.json
```

**If feature tracker exists**:

a. **Auto-sync on every execution** (keeps tracker fresh):
```bash
# Get last_updated from tracker
last_sync=$(cat docs/blueprint/feature-tracker.json | jq -r '.last_updated // empty')
# Compare with current date
```

**If stale** (> 1 day old) OR if a PRP was just executed OR work-order completed:
- Report: "Auto-syncing feature tracker..."
- **Action**: Run feature tracker sync logic inline:
  1. Read current feature-tracker.json
  2. Read TODO.md (if exists) for checkbox states
  3. Detect any discrepancies (checked boxes vs tracker status)
  4. Auto-resolve discrepancies by trusting TODO.md (most recently edited by user)
  5. Update feature-tracker.json with new statistics and task states
  6. Report changes made (if any)

**Auto-sync is silent when no changes** - only reports if something was updated.

b. Show completion status:
```bash
# Get statistics
cat docs/blueprint/feature-tracker.json | jq '.statistics'
```

- Report completion percentage: "{complete}/{total} ({percentage}%)"
- List current phase status
- If incomplete features exist, show next 3 actionable features

c. **Only prompt if user interaction is beneficial**:

**If completion < 100%** and no other pending actions:
- Use AskUserQuestion:
  ```
  question: "Feature tracker: {complete}/{total} complete ({percentage}%). What's next?"
  options:
    - label: "Work on: {next-incomplete-feature}"
      description: "Start implementing this feature"
    - label: "Create PRP for feature"
      description: "Create detailed implementation plan"
    - label: "View detailed status"
      description: "Run /blueprint-feature-tracker-status"
    - label: "Continue to other actions"
      description: "Skip feature work for now"
  ```
- **Action based on selection**, then **Exit**

**If completion == 100%**:
- Report: "🎉 All features complete!"
- Continue to step 10

**If no feature tracker**: Continue to step 10

---

### 10. No Clear Next Action - Show Status & Options

When no automatic action is determined, show comprehensive status and options.

**Action**: Run `/blueprint-status`

This will:
- Display full blueprint status
- Show three-layer architecture
- List available next actions
- Prompt user for what to do next

**Exit** after status completes.

name: blueprint-execute
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
