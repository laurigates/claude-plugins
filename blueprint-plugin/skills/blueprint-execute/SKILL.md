---
model: sonnet
created: 2026-01-14
modified: 2026-02-17
reviewed: 2026-01-30
description: "Idempotent meta command that determines and executes the next logical blueprint action"
allowed-tools: Read, Glob, Bash, AskUserQuestion, SlashCommand, Task
name: blueprint-execute
---

Intelligent meta command that analyzes repository state and executes the appropriate blueprint action.

**Concept**: Run this command anytime to automatically determine what should happen next in your blueprint workflow. Safe to run repeatedly - it's idempotent and will always figure out the right action.

**Usage**: `/blueprint:execute`

**How it works**: This command acts as an orchestrator, detecting your project's current state and delegating to specific blueprint commands as needed. It uses parallel agents for efficient context gathering.

For detailed AskUserQuestion templates, examples, and common workflows, see [REFERENCE.md](REFERENCE.md).

---

## Phase 0: Parallel Context Gathering

Launch these agents **simultaneously** to gather context:

| Agent | Task |
|-------|------|
| **Git History Analysis** | Recent commits (last 20), branches, uncommitted changes, conventional commit usage |
| **Documentation Status** | PRDs, ADRs, PRPs in `docs/` - counts, frontmatter status, actionable items |
| **Blueprint State** | manifest.json version, generated rules in `.claude/rules/`, feature tracker status |
| **Task Registry** | Read `task_registry` from manifest.json: enabled/disabled status, schedules, last run times, due tasks |

Consolidate findings into unified context: git quality, documentation coverage, blueprint health, actionable items.

---

## State Detection & Action Flow

Run through these checks in order, executing the first matching action:

### 1. Check Initialization

```bash
test -f docs/blueprint/manifest.json
```

**If NOT initialized**: Run `/blueprint-init`, then **Exit**.

### 2. Check for Upgrades

```bash
cat docs/blueprint/manifest.json | grep '"format_version"'
```

**Current format version**: 3.0.0

**If manifest version < 3.0.0**: Run `/blueprint-upgrade`, then **Exit**.

### 2.5. Check Task Registry for Due Tasks

If manifest has `task_registry`:

```bash
jq -r '.task_registry | to_entries[] | select(.value.enabled == true) | select(.value.auto_run == true) | .key' docs/blueprint/manifest.json
```

For each enabled auto_run task, check if due based on schedule:
- `daily`: Due if `last_completed_at` is null or > 24h ago
- `weekly`: Due if `last_completed_at` is null or > 7d ago
- `on-change`: Due if source inputs changed (checked by individual task)
- `on-demand`: Never auto-triggered

**If auto_run tasks are due**: Execute them silently in order (read-only tasks like validate, sync). Report results briefly. Continue to next check.

**If non-auto_run tasks are due**: Note them for display in status. Don't prompt here - let specific checks handle them.

### 3. Check for Missing Documentation (Derive Phase)

```bash
git rev-list --count HEAD 2>/dev/null || echo 0
find docs/prds -name "*.md" 2>/dev/null | wc -l
find docs/adrs -name "*.md" 2>/dev/null | wc -l
cat docs/blueprint/manifest.json | jq -r '.derived_rules.last_derived_at // empty'
```

**If git history (>10 commits) but NO PRDs and NO ADRs**: Prompt for derivation method (derive all, PRD only, ADRs only, or skip). Execute selected action, then **Exit**.

**If git history but NO derived rules**: Prompt to derive rules from git. If yes, run `/blueprint:derive-rules`, then **Exit**.

### 4. Check for Stale/Modified Generated Content

Check each generated rule hash against manifest:

**If stale** (PRDs changed since generation): Prompt to regenerate or skip. If regenerate, run `/blueprint-generate-rules`, then **Exit**.

**If modified** (user edited generated files): Prompt to review, promote to custom layer, or skip. Execute selected action, then **Exit**.

### 5. Check for PRDs Without Generated Rules

```bash
prd_count=$(find docs/prds -name "*.md" 2>/dev/null | wc -l)
generated_count=$(cat docs/blueprint/manifest.json | jq '.generated.rules | length')
```

**If PRDs exist but no generated rules**: Run `/blueprint-generate-rules`, then **Exit**.

### 6. Check for Ready PRPs

```bash
find docs/prps -name "*.md" -type f 2>/dev/null
```

**If multiple high-confidence PRPs (>= 2 with score >= 9)**: Prompt for parallel work-order creation or single PRP execution.

**If single PRP or user selects one**: Run `/blueprint-prp-execute {selected-prp}`, then **Exit**.

### 7. Check for Pending Work-Orders

```bash
find docs/blueprint/work-orders -maxdepth 1 -name "*.md" -type f 2>/dev/null
```

**If work-orders found**: Prompt for selection. Execute chosen work-order, move to `completed/` when done, sync feature tracker if enabled, then **Exit**.

### 8. Check Feature Tracker for Active Tasks

```bash
cat docs/blueprint/feature-tracker.json | jq '{
  in_progress: .tasks.in_progress,
  pending: .tasks.pending,
  current_phase: .current_phase
}'
```

**If in-progress tasks**: Prompt to continue, create work-order, or skip. Execute selection, then **Exit**.

**If pending tasks** (no in-progress): Prompt to start task, create PRP, create work-order, or skip. Execute selection, then **Exit**.

### 9. Check Feature Tracker (If Enabled)

```bash
test -f docs/blueprint/feature-tracker.json
```

**Auto-sync** if due per task_registry schedule (default: daily) or after PRP execution/work-order completion. See [REFERENCE.md](REFERENCE.md) for sync details.

**If completion < 100%**: Show status and prompt for next feature work.

**If completion == 100%**: Report all features complete, continue to step 10.

### 10. No Clear Next Action - Show Status & Options

Run `/blueprint-status` to display full blueprint status with available next actions.

---

## Registry Updates

After executing any task action, update the corresponding `task_registry` entry in manifest.json:

```bash
jq --arg task "$TASK_NAME" --arg now "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg result "$RESULT" \
  '.task_registry[$task].last_completed_at = $now | .task_registry[$task].last_result = $result | .task_registry[$task].stats.runs_total = ((.task_registry[$task].stats.runs_total // 0) + 1)' \
  docs/blueprint/manifest.json > tmp.json && mv tmp.json docs/blueprint/manifest.json
```

This ensures every execute run updates operational metadata for tracking and future scheduling decisions.

## Idempotency Guarantees

| Guarantee | How |
|-----------|-----|
| State detection is read-only | Only reads files until action is chosen |
| Single action execution | Executes ONE action per run, then exits |
| User confirmation | Critical actions prompt before executing |
| Consistent state | Each action leaves project in valid state |
| No side effects | Re-running after completion shows status only |

## Integration with Existing Commands

This meta command **delegates** to existing blueprint commands rather than replacing them. Users can still run specific commands directly when they know what they want. `/blueprint:execute` is for when you want the system to decide.

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Smart next action | `/blueprint:execute` |
| Morning start | `/blueprint:execute` (figures out where you left off) |
| After pulling changes | `/blueprint:execute` (checks for stale content) |
| Direct init | `/blueprint-init` (skip detection) |
| Direct PRP execution | `/blueprint-prp-execute {name}` (skip detection) |

---

**Note**: This is a meta-orchestrator command. It analyzes state and delegates to specific blueprint commands. It's designed to be the "smart entry point" for blueprint workflow while preserving access to individual commands for power users.
