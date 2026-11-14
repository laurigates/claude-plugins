# Issue Selection Modes

Moved from `SKILL.md` § Mode Detection. Read when Step 0 counts zero refs (interactive), two or more refs (multiple), or `--auto` was passed.

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
- Run the already-implemented check (Auto Mode, step 2) and set its hits aside
- Score the rest by clarity, scope, dependencies
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
2. **Run the already-implemented check before scoring.** An issue stays open
   when the PR that implemented it carried no closing keyword, so an open
   issue is not proof the work is undone. For each issue, search merged work
   by its title and one or two key phrases from its body:
   `gh pr list --state merged --search "<issue title> in:title" --json number,title,mergedAt`
   and `git log --oneline -i --grep "<key phrase>" origin/main`. Present a hit as
   "already done: verify and close" with the PR or commit it names, and route
   it to the [Verification-Only Flow](verification-only.md) instead of the
   scored list. A hit is a lead, not a verdict: a PR with a similar title may
   cover only part of the issue, so the flow checks each criterion at HEAD.
3. Score and prioritize the remaining issues
4. Present recommendations for approval
5. Process approved issues
