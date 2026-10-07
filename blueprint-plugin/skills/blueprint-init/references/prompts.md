# blueprint-init — AskUserQuestion Prompts

Exact wording for each interactive step. The effect of each answer is defined in SKILL.md.

## Step 1 — already initialized

```
Use AskUserQuestion:
question: "Blueprint already initialized (v{version}). What would you like to do?"
options:
  - "Check for upgrades" → run /blueprint:upgrade
  - "Reinitialize (will reset manifest)" → continue with step 2
  - "Cancel" → exit
```

## Step 2 — feature tracking

```
question: "Would you like to enable feature tracking?"
options:
  - label: "Yes - Track implementation against requirements"
    description: "Creates feature-tracker.json to track FR codes from a requirements document"
  - label: "No - Skip feature tracking"
    description: "Can be added later with /blueprint:feature-tracker-sync"
```

## Step 4 — maintenance task scheduling

```
question: "How should blueprint maintenance tasks run?"
options:
  - label: "Prompt before running (Recommended)"
    description: "Always ask before running maintenance tasks like sync, validate"
  - label: "Auto-run safe tasks"
    description: "Read-only tasks (validate, sync, status) run automatically when due"
  - label: "Fully automatic"
    description: "All tasks run automatically on schedule, including writes like rule generation"
  - label: "Manual only"
    description: "Tasks only run when you explicitly invoke them"
```

## Step 4a — generated-rules output path

```bash
# Only prompt if .claude/rules/ has any content not created by blueprint
find .claude/rules -maxdepth 1 -type f -name '*.md'
```

```
Use AskUserQuestion (only when .claude/rules/ has existing content):
question: "Detected existing content in .claude/rules/. Where should blueprint write generated rules?"
options:
  - label: ".claude/rules/blueprint/ (Recommended)"
    description: "Isolated subdirectory — keeps blueprint-managed and hand-authored rules separate, prevents collisions on regenerate"
  - label: ".claude/rules/ (flat)"
    description: "Write generated rules alongside hand-authored ones; risk of overwrite when filenames collide"
```

## Step 5 — decision detection

```
question: "Would you like to enable automatic decision detection?"
options:
  - label: "Yes - Detect decisions worth documenting"
    description: "Claude will notice when conversations contain architecture decisions, feature requirements, or implementation plans that should be captured as ADR/PRD/PRP documents"
  - label: "No - Manual commands only"
    description: "Use /blueprint:derive-plans, /blueprint:prp-create explicitly when you want to create documents"
```

## Step 11 — next action

```
question: "Blueprint initialized. What would you like to do next?"
options:
  - label: "Derive plans from git history (Recommended)"
    description: "Analyze commit history, PRs, and issues to build PRDs, ADRs, and PRPs from existing project decisions"
  - label: "Derive rules from codebase"
    description: "Analyze commit patterns and code conventions to generate .claude/rules/"
  - label: "Update CLAUDE.md"
    description: "Generate or update CLAUDE.md with project context and blueprint integration"
  - label: "I'm done for now"
    description: "Exit - you can run /blueprint:status anytime to see options"
```
