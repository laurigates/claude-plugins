---
model: opus
created: 2026-01-30
modified: 2026-02-17
reviewed: 2026-02-14
description: "Derive Claude rules from git commit log decisions. Newer commits override older decisions when conflicts exist."
args: "[--since DATE] [--scope SCOPE]"
argument-hint: "--since 2024-01-01 for date range, --scope api for specific area"
allowed-tools: Read, Write, Glob, Grep, Bash, AskUserQuestion, Task
name: blueprint-derive-rules
---

# /blueprint:derive-rules

Extract project decisions from git commit history and codify them as Claude rules. Newer commits override older decisions when conflicts exist.

**Use case**: Derive implicit project patterns from git history to establish consistent AI-assisted development guidelines.

**Usage**: `/blueprint:derive-rules [--since DATE] [--scope SCOPE]`

## When to Use This Skill

| Use this skill when... | Use alternative when... |
|------------------------|-------------------------|
| Want to extract implicit decisions from git history | Creating rules from requirements (use PRDs instead) |
| Project has significant commit history | New project with little history |
| Establishing project coding standards | Quick manual rule creation |

## Context

- Git repository: !`git rev-parse --git-dir 2>/dev/null`
- Blueprint initialized: !`test -f docs/blueprint/manifest.json 2>/dev/null`
- Total commits: !`git rev-list --count HEAD 2>/dev/null`
- Conventional commits %: !`git log --format="%s" 2>/dev/null`
- Existing rules: !`find .claude/rules -name "*.md" -type f 2>/dev/null`

## Parameters

Parse `$ARGUMENTS`:

- `--since DATE`: Analyze commits from specific date (e.g., `--since 2024-01-01`)
- `--scope SCOPE`: Focus on specific area (e.g., `--scope api`, `--scope testing`)

## Execution

Execute the complete git-to-rules derivation workflow:

### Step 1: Verify prerequisites

1. If not a git repository → Error: "This directory is not a git repository"
2. If Blueprint not initialized → Suggest `/blueprint:init` first
3. If few commits (< 20) → Warn: "Limited commit history; derived rules may be incomplete"

### Step 2: Analyze git history quality

1. Calculate total commits in scope
2. Calculate conventional commits percentage
3. Report quality: Higher % = higher confidence in extracted rules
4. Parse `--since` and `--scope` flags to determine analysis range

### Step 3: Extract decision-bearing commits

Use parallel agents to analyze git history efficiently (see [REFERENCE.md](REFERENCE.md#git-analysis)):

- **Agent 1**: Analyze `refactor:` commits for code style patterns
- **Agent 2**: Analyze `fix:` commits for repeated issue types
- **Agent 3**: Analyze `feat!:` and `BREAKING CHANGE:` commits for architecture decisions
- **Agent 4**: Analyze `chore:` and `build:` commits for tooling decisions

Consolidate findings by domain (code-style, testing, api-design, etc.), chronologically (newest first), and by frequency (most common wins).

### Step 4: Resolve conflicts

When multiple commits address the same topic:

1. Detect conflicts using pattern matching: `git log --format="%H|%ai|%s" | grep "{topic}"`
2. Apply resolution strategy:
   - **Newer overrides older**: Latest decision wins
   - **Higher frequency wins**: If 5 commits say X and 1 says Y, X wins
   - **Breaking changes override**: `feat!:` trumps regular commits
3. Mark overridden decisions as "superseded" with reference to newer decision
4. Confirm significant decisions with user via AskUserQuestion

### Step 5: Generate rules in `.claude/rules/`

For each decision, generate rule file using template from [REFERENCE.md](REFERENCE.md#rule-template):

1. Extract source commit, date, type
2. Determine confidence level (High/Medium/Low based on commit frequency and clarity)
3. Generate actionable rule statement
4. Include code examples from commit diffs
5. Reference any superseded earlier decisions

Generate separate rule files by category (see [REFERENCE.md](REFERENCE.md#rule-categories)):
- `code-style.md`, `testing-standards.md`, `api-conventions.md`, `error-handling.md`, `dependencies.md`, `security-practices.md`

### Step 6: Handle conflicts with existing rules

Check for conflicts with existing rules in `.claude/rules/`:

1. If conflicts found → Ask user: Git-derived overrides existing rule, or keep existing?
2. Apply user choice: Update, merge, or keep separate
3. Document conflict resolution in rule file

### Step 7: Update task registry

Update the task registry entry in `docs/blueprint/manifest.json`:

```bash
jq --arg now "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg sha "$(git rev-parse HEAD 2>/dev/null)" \
  --argjson processed "${COMMITS_ANALYZED:-0}" \
  --argjson created "${RULES_DERIVED:-0}" \
  '.task_registry["derive-rules"].last_completed_at = $now |
   .task_registry["derive-rules"].last_result = "success" |
   .task_registry["derive-rules"].context.commits_analyzed_up_to = $sha |
   .task_registry["derive-rules"].stats.runs_total = ((.task_registry["derive-rules"].stats.runs_total // 0) + 1) |
   .task_registry["derive-rules"].stats.items_processed = $processed |
   .task_registry["derive-rules"].stats.items_created = $created' \
  docs/blueprint/manifest.json > tmp.json && mv tmp.json docs/blueprint/manifest.json
```

### Step 8: Update manifest and report

1. Update `docs/blueprint/manifest.json` with derived rules metadata: timestamp, commits analyzed, rules generated, source commits
2. Generate completion report showing:
   - Commits analyzed (count and date range)
   - Conventional commits percentage
   - Rules generated by category
   - Confidence scores per rule
   - Any conflicts resolved
3. Prompt user for next action: Review rules, execute derived development workflow, or done

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Check git status | `git rev-parse --git-dir 2>/dev/null && echo "YES" \|\| echo "NO"` |
| Count total commits | `git rev-list --count HEAD 2>/dev/null \|\| echo "0"` |
| Conventional commits % | `git log --format="%s" \| grep -c "^(feat\|fix\|refactor)" \|\| echo 0` |
| Extract decision commits | `git log --format="%H\|%s\|%b" \| grep -E "(always\|never\|must\|prefer)"` |
| Fast derivation | Use parallel agents (Explore) for multi-domain analysis |

---

For git analysis patterns, rule templates, conflict resolution, and detailed procedures, see [REFERENCE.md](REFERENCE.md).
