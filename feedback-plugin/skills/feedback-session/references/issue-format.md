# feedback-session: issue format, finding format, and summary

**Every issue carries the type label of its `## Category`**: Bug → `bug`,
Enhancement → `enhancement`, Positive feedback → `positive-feedback`. The
filer sets it because nothing else can: git-plugin's `issue-labels.py` derives
no type from a `feedback(<plugin>): …` title (#3783), since the same title
form carries defects, enhancements and success reports, and its weekly audit
reports an issue with no type label.

**Labels** (when not `$SKIP_SESSION_LABELS`):
- Bugs: `session-feedback`, `bug`
- Enhancements: `session-feedback`, `enhancement`
- Positive: `positive-feedback`

**Labels** (when `$SKIP_SESSION_LABELS=true`):
- Bugs: `bug`
- Enhancements: `enhancement`
- Positive: `positive-feedback` when the repo already has it
  (`gh label list --limit 500 --json name --jq '.[].name'` lists it);
  otherwise no label, and omit the `--label` flag

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

## Processing

<Keep the block for this issue's category and delete the other.>

<Bug or Enhancement:>
- **Processed by:** the weekly `friction-learner` run reads it as corroboration; the fix lands as an ordinary PR.
- **Completed means:** a PR that fixes it has merged, or it was closed with a stated reason.
- **Closes:** when that PR merges (`Fixes #N`).

<Positive feedback:>
- **Processed by:** the weekly `friction-learner` run, which cites it under `## Fast-loop signal` in its PR.
- **Completed means:** that PR cites it.
- **Closes:** `friction-learner` closes it after citing it, and keeps reading it as a stability marker for 6 months while closed.
```

The `## Processing` section puts the issue's lifecycle in the issue itself, so
whoever opens it can tell who acts on it and when it closes without knowing the
feedback loop.

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
