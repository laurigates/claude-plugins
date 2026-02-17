# Blueprint Execute - Reference

Detailed reference material for the blueprint-execute meta command, including AskUserQuestion templates, examples, and common workflows.

## AskUserQuestion Templates

### Step 3: Missing Documentation Prompt

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

### Step 3: Derived Rules Prompt

```
question: "Would you like to derive rules from git commit decisions?"
options:
  - label: "Yes, derive rules from git"
    description: "Run /blueprint:derive-rules to extract decisions from commits"
  - label: "Skip for now"
    description: "Continue with other actions"
```

### Step 4: Stale Content Prompt

```
question: "Generated content is out of sync with PRDs. What would you like to do?"
options:
  - label: "Regenerate from PRDs (Recommended)"
    description: "Update generated rules to match current PRD content"
  - label: "Skip for now"
    description: "Continue with other actions"
```

### Step 4: Modified Content Prompt

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

### Step 6: Multiple Ready PRPs Prompt

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

### Step 6: PRP Selection Prompt

```
question: "Found {count} PRP(s). Which would you like to execute?"
options:
  - label: "{prp-1-name} (confidence: {score})"
    description: "Execute this PRP with TDD workflow"
  - label: "{prp-2-name} (confidence: {score})"
    description: "Execute this PRP with TDD workflow"
  - label: "Skip PRP execution"
    description: "Continue to other actions"
```

### Step 7: Pending Work-Orders Prompt

```
question: "Found {count} pending work-order(s). What would you like to do?"
options:
  - label: "Execute: {work-order-1}"
    description: "Run this work-order"
  - label: "Execute: {work-order-2}"
    description: "Run this work-order"
  - label: "Skip work-orders"
    description: "Continue to other actions"
```

### Step 8: In-Progress Tasks Prompt

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

### Step 8: Pending Tasks Prompt

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

### Step 9: Feature Tracker Prompt

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
Blueprint Status: Up to date (v3.0.0)

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
Blueprint Status: Up to date (v3.0.0)

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
Blueprint Status: Attention needed

Stale generated content detected: 2 files
- architecture-patterns.md (PRD changed on 2026-01-13)
- testing-strategies.md (PRD changed on 2026-01-12)

[Prompts: Regenerate from PRDs?]
```

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

## Benefits

1. **Reduced cognitive load**: No need to remember which command to run
2. **Progressive workflow**: Naturally guides through blueprint methodology
3. **Safe exploration**: Can run anytime without breaking things
4. **Smart defaults**: Automatically picks the right action for current state
5. **Flexible**: Can skip actions and continue to next check
6. **Always actionable**: Always suggests next steps, never leaves you stuck

## Feature Tracker Auto-Sync Details

When feature tracker exists and is stale (> 1 day old), or a PRP was just executed, or a work-order was completed:

1. Read current feature-tracker.json
2. Read TODO.md (if exists) for checkbox states
3. Detect any discrepancies (checked boxes vs tracker status)
4. Auto-resolve discrepancies by trusting TODO.md (most recently edited by user)
5. Update feature-tracker.json with new statistics and task states
6. Report changes made (if any)

Auto-sync is silent when no changes - only reports if something was updated.

## Task Registry Schedule Logic

### Due Calculation

| Schedule | Due When |
|----------|----------|
| `daily` | `last_completed_at` is null OR > 24 hours ago |
| `weekly` | `last_completed_at` is null OR > 7 days ago |
| `on-change` | Source inputs changed since last run (task-specific) |
| `on-demand` | Never auto-suggested; only runs on explicit invocation |

### Priority Order for Due Tasks

When multiple tasks are due, execute in this order:
1. `sync-ids` (fast, foundational)
2. `feature-tracker-sync` (fast, updates status)
3. `adr-validate` (fast, read-only check)
4. `generate-rules` (may modify files)
5. `derive-rules` (may modify files)
6. `derive-plans` (longer running)
7. `claude-md` (depends on other outputs)

### Auto-Run Task Prompt (for due non-auto tasks)

```
question: "These maintenance tasks are due. Which would you like to run?"
options:
  - label: "Run all due tasks"
    description: "Execute {N} due tasks in priority order"
  - label: "Choose specific tasks"
    description: "Select which tasks to run"
  - label: "Skip maintenance"
    description: "Continue to other actions"
```
