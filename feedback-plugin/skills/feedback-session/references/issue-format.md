# feedback-session: issue format, finding format, and summary

**Labels** (when not `$SKIP_SESSION_LABELS`):
- Bugs: `session-feedback`, `bug`
- Enhancements: `session-feedback`, `enhancement`
- Positive: `positive-feedback`

**Labels** (when `$SKIP_SESSION_LABELS=true`):
- Bugs: `bug`
- Enhancements: `enhancement`
- Positive: *(no label — omit the `--label` flag)*

**The label is the routing key.** The weekly `friction-learner` agent
(`feedback-plugin/agents/friction-learner.md`, Step 0) fetches open
`session-feedback` issues as friction hypotheses and `positive-feedback` issues
as stability markers, in two separate queries. A positive finding therefore
carries `positive-feedback` alone; it does not need `session-feedback` to be
read. A positive issue filed with no label (`$SKIP_SESSION_LABELS=true`) is
invisible to that agent until the label is added.

**After filing, a positive issue closes on its own.** The next weekly
`friction-learner` run cites it in its PR's `## Fast-loop signal` section, then
closes it with a comment naming that PR (closed = processed). Later runs keep
reading positive issues in any state created in the last 6 months, so a closed
one still protects the behaviour it praises. Leave it open after filing; do not
close it by hand.

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
