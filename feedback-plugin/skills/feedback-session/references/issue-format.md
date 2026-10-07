# feedback-session: issue format, finding format, and summary

**Labels** (when not `$SKIP_SESSION_LABELS`):
- Bugs: `session-feedback`, `bug`
- Enhancements: `session-feedback`, `enhancement`
- Positive: `positive-feedback`

**Labels** (when `$SKIP_SESSION_LABELS=true`):
- Bugs: `bug`
- Enhancements: `enhancement`
- Positive: *(no label — omit the `--label` flag)*

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

## Step 4 finding format

Format each finding as:
```
[BUG] plugin-name/skill-name: brief description
[ENH] plugin-name/skill-name: brief description
[POS] plugin-name/skill-name: brief description
```

## Step 6 summary table

Print a summary:

| Metric | Count |
|--------|-------|
| Findings identified | N |
| Duplicates skipped | N |
| Issues created | N |
| Skipped by user | N |
