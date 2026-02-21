---
model: opus
name: feedback-session
description: |
  Analyze current session for skill feedback and create GitHub issues. Use when
  a skill gave wrong guidance, a command failed due to skill advice, you discovered
  a better pattern, or a skill worked particularly well. Creates labeled issues
  for tracking.
args: "[--dry-run] [--bugs-only] [--enhancements-only] [--positive-only] [plugin-name]"
allowed-tools: Bash(gh issue *), Bash(gh label *), Bash(gh search *), Bash(git status *), Bash(git remote *), Read, Grep, Glob, AskUserQuestion, TodoWrite
argument-hint: "--dry-run | --bugs-only | plugin-name"
created: 2026-02-18
modified: 2026-02-18
reviewed: 2026-02-18
---

# /feedback:session

Analyze the current session for skill feedback and create GitHub issues to track bugs, enhancements, and positive patterns.

## When to Use This Skill

| Use this skill when... | Use alternative when... |
|------------------------|------------------------|
| A skill gave wrong or outdated guidance | Want to update skills directly -> `/project:distill` |
| A command failed due to skill advice | Need static skill quality analysis -> `/health:audit` |
| Discovered a better flag or pattern | Want to capture general learnings -> `/project:distill` |
| A skill worked particularly well | Want to track command usage stats -> `/analytics-report` |
| End of session, want to file feedback | Need to fix a skill right now -> edit the SKILL.md directly |

## Context

- Repository: !`git remote get-url origin 2>/dev/null`
- Open feedback issues: !`gh issue list --label session-feedback --state open --json number,title --jq '.[].title' 2>/dev/null`
- Open positive issues: !`gh issue list --label positive-feedback --state open --json number,title --jq '.[].title' 2>/dev/null`

## Parameters

Parse these from `$ARGUMENTS`:

| Parameter | Description |
|-----------|-------------|
| `--dry-run` | Show findings without creating issues |
| `--bugs-only` | Only report bugs (wrong/outdated guidance) |
| `--enhancements-only` | Only report enhancement opportunities |
| `--positive-only` | Only report positive feedback |
| `[plugin-name]` | Scope analysis to a specific plugin |

## Execution

Execute this session feedback workflow:

### Step 1: Ensure labels exist

Check and create required labels:

1. Check if `session-feedback` label exists: `gh label list --json name --jq '.[].name' | grep -q session-feedback`
2. If missing, create it: `gh label create session-feedback --description "Feedback from session analysis" --color "d876e3"`
3. Check if `positive-feedback` label exists similarly
4. If missing, create it: `gh label create positive-feedback --description "Skills that worked well" --color "0e8a16"`

### Step 2: Analyze conversation history

Review the entire conversation for feedback signals. Look for these categories:

**Bugs** (label: `session-feedback`, `bug`):
- Skill gave wrong command syntax or outdated flags
- Command failed because skill guidance was incorrect
- Skill recommended a pattern that caused errors
- Skill was missing a critical caveat or prerequisite

**Enhancements** (label: `session-feedback`, `enhancement`):
- Discovered a better flag or option than what the skill suggests
- Found a workflow gap the skill should cover
- Identified a missing pattern or integration
- Found a more efficient approach than the skill recommends

**Positive** (label: `positive-feedback`):
- Skill provided correct, effective guidance
- Skill's agentic optimizations saved time
- Skill's decision table correctly directed to the right tool
- Skill's patterns worked well in practice

For each finding, record:
- **Category**: bug, enhancement, or positive
- **Plugin**: which plugin the skill belongs to
- **Skill**: which specific skill
- **Description**: what happened
- **Evidence**: the specific interaction or error that demonstrates it

Filter by `$ARGUMENTS`:
- If `--bugs-only`: only report bugs
- If `--enhancements-only`: only report enhancements
- If `--positive-only`: only report positive feedback
- If `[plugin-name]` specified: only report for that plugin

### Step 3: Deduplicate against open issues

For each finding, search for existing issues:

```
gh issue list --label session-feedback --search "<skill-name> <key-phrase>" --json number,title --jq '.[].title'
```

Skip findings that match an existing open issue title. Note skipped items for the summary.

### Step 4: Present findings for review

Use AskUserQuestion to present categorized findings. Group by category:

Format each finding as:
```
[BUG] plugin-name/skill-name: brief description
[ENH] plugin-name/skill-name: brief description
[POS] plugin-name/skill-name: brief description
```

Let the user select which findings to file as issues (use multiSelect).

If `--dry-run`, present findings and stop here.

### Step 5: Create approved issues

For each approved finding, create a GitHub issue:

**Title format**: `feedback(<plugin-name>): <description>`

**Labels**:
- Bugs: `session-feedback`, `bug`
- Enhancements: `session-feedback`, `enhancement`
- Positive: `positive-feedback`

**Body template**:
```markdown
## Skill

`<plugin-name>/skills/<skill-name>/SKILL.md`

## Category

<Bug | Enhancement | Positive feedback>

## Description

<What happened during the session>

## Evidence

<Specific interaction, error message, or successful outcome>

## Suggested Action

<What should change in the skill, or what should be preserved>
```

Create each issue: `gh issue create --title "feedback(<plugin>): <desc>" --label "<labels>" --body "<body>"`

### Step 6: Report summary

Print a summary:

| Metric | Count |
|--------|-------|
| Findings identified | N |
| Duplicates skipped | N |
| Issues created | N |
| Skipped by user | N |

List created issue numbers with links.

## Agentic Optimizations

| Context | Command |
|---------|---------|
| List feedback issues | `gh issue list --label session-feedback --json number,title,labels -q '.[]'` |
| Search for duplicates | `gh issue list --label session-feedback --search "keyword" --json title -q '.[].title'` |
| Create label | `gh label create name --description "desc" --color "hex"` |
| Create issue | `gh issue create --title "t" --label "l1,l2" --body "b"` |
| Check label exists | `gh label list --json name -q '.[].name'` |

## Quick Reference

| Flag | Description |
|------|-------------|
| `--dry-run` | Show findings without creating issues |
| `--bugs-only` | Only bug reports |
| `--enhancements-only` | Only enhancement suggestions |
| `--positive-only` | Only positive feedback |
| `[plugin-name]` | Scope to specific plugin |
