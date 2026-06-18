---
created: 2026-01-24
modified: 2026-06-18
reviewed: 2026-06-10
allowed-tools: Bash(bash *), Bash(git log *), Bash(git shortlog *), Bash(git diff *), Bash(git branch *),
               Bash(git show *), Bash(git rev-list *), Bash(git diff-tree *),
               Bash(git status *), Read, Grep, Glob, Edit, Write, TodoWrite
args: "[--rules] [--prd] [--adr] [--prp] [--all] [--since=<date>] [--depth=<N>]"
argument-hint: "[--rules] [--prd] [--adr] [--prp] [--all] [--since=<date>] [--depth=<N>]"
disable-model-invocation: true
description: "Derive ADRs, rules, PRDs from git commit history. Use when finding doc gaps, detecting unrecorded decisions, deriving conventions from commits, or generating skeleton docs."
name: git-derive-docs
---

## When to Use This Skill

| Use this skill when... | Use the alternative when... |
|---|---|
| Mining git history for undocumented rules, PRDs, ADRs, or PRPs | Use `git-cli-agentic` for one-shot porcelain queries against the history |
| Generating skeleton documentation from commit-message patterns | Use `git-commit-workflow` to set conventions BEFORE the history accrues |
| Detecting architectural decisions or feature work that was never recorded | Use `github-issue-writing` to file fresh issues from the gaps you find |
| Auditing whether `.claude/rules/` and `docs/{prds,adrs,prps}/` reflect actual practice | Use `git-triage` to triage the open issues and PRs surfaced during the audit |

## Context

- Current branch: !`git branch --show-current`
- Commit count: !`git rev-list --count HEAD`
- Latest commit: !`git log --format='%ai' --max-count=1`
- Existing rules: !`find . -path '*/.claude/rules/*' -maxdepth 3 -type f`
- Existing docs: !`find . -maxdepth 3 \( -path '*/docs/prds/*' -o -path '*/docs/adrs/*' -o -path '*/docs/prps/*' \) -type f`
- Commit conventions sample: !`git log --format='%s' --max-count=20`

## Parameters

- `--rules`: Derive `.claude/rules/` from commit patterns (conventions, naming, tooling)
- `--prd`: Detect features implemented without requirements documentation
- `--adr`: Detect architecture decisions made without decision records
- `--prp`: Detect implementation work done without planning documentation
- `--all`: Run all detection categories (default if no flags specified)
- `--since=<date>`: Limit analysis to commits after date (e.g., `--since=2025-01-01`)
- `--depth=<N>`: Number of commits to analyze (default: 200)
- `--dry-run`: Report findings without creating files
- `--refinements`: Focus on plan refinement detection (approach changes, reverts, rework)

## Your task

Analyze git commit history to identify documentation gaps.

### Step 1: Determine Scope and gather history signals

Parse flags to determine which categories to analyze. Default to `--all` if no category flags provided.

Run the data-gathering script once. It aggregates file-naming patterns
(top directories + added-file extensions), tallies commit-convention frequency
(`CONV_<type>=<count>`), and detects dependency/migration signals
(`DEP_MANIFEST_COMMITS`, `MIGRATION_COMMITS`, `REFACTOR_COMMITS`), plus existing
doc coverage (`DOCS_*`):

```bash
bash "${CLAUDE_SKILL_DIR}/scripts/git-derive-docs.sh" --home-dir "$HOME" --project-dir "$(pwd)" --depth "$DEPTH" --since "$SINCE"
```

Parse `STATUS=` and `ISSUES:` from the output. Pass `--since` (precedence) or
`--depth` (default 200). The structured rollup replaces the raw `git log`
pipes the rest of this skill used to run inline.

### Step 2: Rules Detection (if --rules or --all)

The script already aggregated the convention signals: read the `CONV_<type>`
frequency tally (commit-message conventions), the `DIR_<n>=<path>` /
`EXT_<name>=<count>` entries (file-naming patterns), and `DOCS_*` (existing
coverage). Cross-reference with existing `.claude/rules/` to avoid duplicates —
the script reports current rule-file counts under `DOCS__CLAUDE_RULES`.

### Step 3: PRD Detection (if --prd or --all)

Find features built without requirements documentation:

```bash
# Feature commits without PRD references
git log --format='%H %s' -$DEPTH | grep -iE '^[a-f0-9]+ feat' | head -20

# Large additions (new feature directories)
git log --diff-filter=A --name-only --format='%H---' -$DEPTH | awk '/^[a-f0-9]+---/{hash=$0;next}{if(hash)print hash,$0}'

# Cluster commits by directory to find feature groups
git log --format='' --name-only -$DEPTH | grep -oP '^[^/]+/[^/]+' | sort | uniq -c | sort -rn | head -15
```

Cross-reference with existing `docs/prds/` to avoid duplicates.

### Step 4: ADR Detection (if --adr or --all)

Find architecture decisions without documentation. The script already detected
the deterministic dependency/migration signals — read `DEP_MANIFEST_COMMITS`
(commits touching dependency manifests), `MIGRATION_COMMITS` (migrate/switch/
replace/upgrade language), and `REFACTOR_COMMITS` (restructure/reorganize/
redesign language) from Step 1's output. For the specific commit subjects behind
a non-zero count, drill in with a targeted log:

```bash
# Infrastructure-change commits (for context behind the signal counts)
git log --oneline -$DEPTH -- 'docker*' 'Dockerfile*' '.github/workflows/*' 'terraform/*' 'k8s/*'
```

Cross-reference with existing `docs/adrs/` (the script reports the count under
`DOCS__DOCS_ADRS`) to avoid duplicates. Judging whether a flagged commit
represents a real architectural decision worth an ADR stays with you.

### Step 5: PRP Detection (if --prp or --all)

Find implementation work without planning docs:

```bash
# Sequential implementation commits
git log --format='%s' -$DEPTH | grep -iE 'step [0-9]|part [0-9]|phase [0-9]|wip'

# Multi-file coordinated changes
git log --format='%H %s' -$DEPTH | while read hash msg; do
  files=$(git diff-tree --no-commit-id --name-only -r "$hash" 2>/dev/null | wc -l)
  [ "$files" -gt 5 ] && echo "$files files: $msg"
done | sort -rn | head -10

# Feature branches
git branch -a --format='%(refname:short)' | grep -iE 'feat|feature|implement'
```

Cross-reference with existing `docs/prps/` to avoid duplicates.

### Step 6: Plan Refinement Detection (if --refinements or --all)

Find approach changes not documented:

```bash
# Reverts and reworks
git log --format='%H %s' -$DEPTH | grep -iE 'revert|redo|rework|rethink|redesign'

# "Actually" commits (approach corrections)
git log --format='%H %s' -$DEPTH | grep -iE 'actually|instead|better approach|try different'

# High-churn files (approach unclear, iterated heavily)
git log --format='' --name-only -$DEPTH | sort | uniq -c | sort -rn | head -15

# Short-lived implementations (created then significantly changed)
git log --format='%H %ai %s' -$DEPTH | grep -i 'refactor' | head -10
```

### Step 7: Generate Report

Compile findings into a prioritized report:

```markdown
## Documentation Gaps Report

Generated: <date>
Commits analyzed: <N>
Period: <first> to <last>

### High Priority
[Items with strong evidence and high impact]

### Medium Priority
[Items with moderate evidence]

### Low Priority
[Minor patterns or old history items]
```

### Step 8: Create Documents (unless --dry-run)

For each accepted finding:

**Rules**: Create/update `.claude/rules/<name>.md` with:
- Convention description
- Evidence from commits
- Examples

**PRD/ADR/PRP**: Generate skeleton documents in appropriate directories. If blueprint commands are available, suggest using:
- `/blueprint:prd` for PRDs
- `/blueprint:adr` for ADRs
- `/blueprint:prp-create` for PRPs

### Step 9: Summary

Report:
- Number of gaps found per category
- Documents created (if not --dry-run)
- Suggested next steps

## See Also

- **document-detection** skill (blueprint-plugin) for conversation-based detection
- `/docs:generate --changelog` for changelog generation from commits
