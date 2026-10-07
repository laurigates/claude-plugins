# Issue Selection Modes

Moved verbatim from `SKILL.md` § Mode Detection. Read when Step 0 counts zero refs (interactive), two or more refs (multiple), or `--auto` was passed.

### No Arguments → Interactive Mode

Use AskUserQuestion to prompt:

```yaml
questions:
  - header: "Issues"
    question: "How would you like to select issues to work on?"
    options:
      - label: "Let me choose specific issues"
        description: "Show issue list for manual selection"
      - label: "Claude decides priority"
        description: "Analyze issues and recommend which to tackle"
      - label: "Filter by label"
        description: "Select issues with a specific label"
```

**For "Let me choose specific issues":**
1. Fetch: `gh issue list --state open --json number,title,labels,assignees`
2. Present checkboxes with `multiSelect: true`

**For "Claude decides priority":**
- Analyze all open issues
- Score by clarity, scope, dependencies
- Present top recommendations

**For "Filter by label":**
- Present label selection from available labels
- Then show matching issues for selection

### Multiple Issues (`/git:issue 123 456 789`)

1. Analyze all issues for conflicts and parallelization
2. Group by dependencies
3. Process sequentially or spawn parallel agents

### Auto Mode (`/git:issue --auto`)

1. Fetch all open issues
2. Score and prioritize
3. Present recommendations for approval
4. Process approved issues
