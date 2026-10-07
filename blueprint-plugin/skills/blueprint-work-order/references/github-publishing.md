# blueprint-work-order — GitHub Publishing

Read unless `--no-publish` is set.

## Step 7 — create the issue and capture its number

```bash
gh issue create \
  --title "[WO-NNN] [Task Name]" \
  --body "## Work Order: [Task Name]

**ID**: WO-NNN
**Local Context**: \`docs/blueprint/work-orders/NNN-task-name.md\`

### Related Documents
- **Implements**: {PRP-NNN or PRD-NNN}
- **Related ADRs**: {list of ADR-NNNN}

### Objective
[One-line objective from work order]

### TDD Requirements
- [ ] Test 1: [description]
- [ ] Test 2: [description]

### Success Criteria
- [ ] [Criterion 1]
- [ ] [Criterion 2]

---
*AI-assisted development work order. See linked file for full execution context.*" \
  --label "work-order"
```

Capture issue number and update work-order file:
```bash
# Extract issue number from gh output
gh issue create ... 2>&1 | grep -oE '#[0-9]+' | head -1
```

## GitHub integration notes

### Completion Flow
1. Work completed on work-order
2. PR created with `Fixes #N` in body/title
3. Work-order moved to `completed/` directory
4. Issue auto-closes when PR merges

### Label Convention
The `work-order` label identifies issues created from this workflow. Create it in your repo if it doesn't exist:
```bash
gh label create work-order --description "AI-assisted work order" --color "0E8A16"
```

### Offline Mode
Use `--no-publish` when:
- Working offline
- Private experimentation
- Issue visibility not needed

Can publish later by manually creating issue and updating work-order file.
