---
name: feedback-session
description: |
  Analyze current session for skill feedback and create GitHub issues. Use when
  a skill gave wrong guidance, a command failed due to skill advice, you discovered
  a better pattern, or a skill worked particularly well. Creates labeled issues
  for tracking. Supports targeting a different repo (e.g. the plugin source repo)
  with --target-repo.
args: "[--dry-run] [--bugs-only] [--enhancements-only] [--positive-only] [--target-repo <owner/repo>] [plugin-name]"
allowed-tools: Bash(gh issue *), Bash(gh label *), Bash(gh search *), Bash(git status *), Bash(git remote *), Read, Grep, Glob, AskUserQuestion, TodoWrite
model: opus
argument-hint: "--dry-run | --target-repo owner/repo | plugin-name"
disable-model-invocation: true
created: 2026-02-18
modified: 2026-05-04
reviewed: 2026-04-25
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
| Feedback is about the plugin itself | Use `--target-repo laurigates/claude-plugins` to file against the plugin source |

## Known Limitations

**IaC-managed labels**: Some repositories manage GitHub labels declaratively via Terraform, Pulumi, or similar tools. In these repos, `gh label create` will either be forbidden or cause drift that the IaC tool destroys on the next apply. This skill detects this case and offers a graceful fallback (see Step 1).

**Default target repo**: By default, this skill files issues against the repository in the current working directory. If you are giving feedback about a plugin skill itself rather than the application code in the session, use `--target-repo <owner/repo>` to point at the plugin source repo.

**No-remote auto-suggest**: When the cwd has no git remote and `--target-repo` is not provided, this skill scans the session for plugin-skill references (e.g. `blueprint-plugin:blueprint-init`) and auto-suggests the dominant `<owner>/<repo>` from the plugin cache as the default — typically `laurigates/claude-plugins` for marketplace users. The user can accept the suggestion or override with a different `owner/repo`. See Step 1a.

## Context

- Git remotes: !`git remote -v`

Open feedback issues are fetched during Step 3 (deduplication), scoped to the
resolved `$TARGET_REPO`. They are not pre-fetched in context because
`gh issue list` without `-R` requires a configured remote and fails with
"no git remotes found" in repos that lack one.

## Parameters

Parse these from `$ARGUMENTS`:

| Parameter | Description |
|-----------|-------------|
| `--dry-run` | Show findings without creating issues |
| `--bugs-only` | Only report bugs (wrong/outdated guidance) |
| `--enhancements-only` | Only report enhancement opportunities |
| `--positive-only` | Only report positive feedback |
| `--target-repo <owner/repo>` | File issues against this repo instead of the cwd repo |
| `-R <owner/repo>` | Alias for `--target-repo` |
| `[plugin-name]` | Scope analysis to a specific plugin |

After parsing, set `$TARGET_REPO` to the value of `--target-repo`/`-R` if provided. Append `-R $TARGET_REPO` to all `gh` commands below when `$TARGET_REPO` is set.

## Execution

Execute this session feedback workflow:

### Step 1: Resolve target repo and ensure labels exist

**1a. Determine target repo**

If `--target-repo` or `-R` was passed in `$ARGUMENTS`, set `$TARGET_REPO` to that value and append `-R $TARGET_REPO` to every `gh` command in the remaining steps. Skip the rest of this sub-step.

Otherwise, infer the repo from the cwd: `gh repo view --json nameWithOwner -q '.nameWithOwner'`. If this succeeds, use the returned `owner/repo` as the implicit target (no `-R` flag needed since `gh` defaults to cwd) and continue to Step 1b.

If `gh repo view` fails (typically with `no git remotes found` in a repo without a remote), execute this fallback in order:

1. **Scan the session for plugin-skill references.** Walk the conversation transcript and tool-call history collecting every reference of the form `<plugin>:<skill>` (skill invocations like `/blueprint:init`, agent IDs like `agents-plugin:security-audit`, and plugin names mentioned in skill bodies). For each match, look up the owning `<owner>/<repo>` by enumerating directories under `~/.claude/plugins/cache/<owner>/<repo>/` and matching `<plugin>` against the cached plugin manifests. Tally references per `<owner>/<repo>`.

2. **Detect a dominant source.** Compute the share of references attributable to each `<owner>/<repo>`. If the top entry accounts for **more than ~70%** of total references **and** there are at least 3 references in total, treat it as dominant. Record the dominant `$SUGGESTED_REPO`, the reference count `$N`, and proceed to step 3. Otherwise, jump to step 4.

3. **Prompt with the suggestion as the default.** Use AskUserQuestion to ask:

   > **No git remote found.** Suggested target: `$SUGGESTED_REPO` (derived from $N plugin skills referenced this session). Accept, or enter a different `owner/repo`?

   Provide options:
   1. **Accept `$SUGGESTED_REPO`** — set `$TARGET_REPO` to the suggestion and append `-R $TARGET_REPO` to every `gh` command in the remaining steps.
   2. **Enter a different `owner/repo`** — open a free-text follow-up; validate the input matches `^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$` and set `$TARGET_REPO` accordingly.
   3. **Abort** — exit the skill.

   Continue to Step 1b once `$TARGET_REPO` is set.

4. **Fall back to free-text prompt (no dominant source detected).** Use AskUserQuestion to ask the user to enter an `owner/repo`. Validate the input matches `^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$`, set `$TARGET_REPO`, and continue to Step 1b. If the user declines to provide a target, exit the skill.

> **Bonus / future work**: when `$SUGGESTED_REPO` is also cloned at `~/.claude/plugins/cache/<owner>/<repo>/<version>/`, that path could be used by Step 1b's `labels.tf`/`labels.yaml` Glob detection instead of cwd, so IaC-managed labels are detected correctly even when the skill runs outside the plugin checkout. This Step 1b plumbing is intentionally out of scope for this PR — track as a separate issue. For now, Step 1b continues to scan the cwd.

**1b. Check whether labels are IaC-managed**

Run: `gh label list -R $TARGET_REPO --json name,description --jq '.[].description'` (omit `-R` if no explicit target).

Scan the output for IaC indicators in any label description:
- Keywords: `terraform`, `pulumi`, `cdk`, `managed by`, `do not create`, `iac`, `infrastructure`

Also check for labels.tf in the cwd: look for files matching `**/labels.tf` or `**/labels.yaml` patterns using Glob.

If IaC indicators are found **or** `labels.tf` / `labels.yaml` exist in the working tree:
- Display a warning:
  ```
  ⚠ IaC-managed labels detected in <repo>.
  The `session-feedback` and `positive-feedback` labels cannot be created
  via `gh label create` — they are managed declaratively and creating them
  out-of-band would cause drift.
  ```
- Use AskUserQuestion to ask: **How would you like to proceed?**
  Options:
  1. **Proceed without session-feedback labels** — issues will be created with only `bug`/`enhancement` labels; add the two labels to your IaC definition to backfill.
  2. **Use a different target repo** — enter an `owner/repo` where you can create labels freely (e.g. `laurigates/claude-plugins`).
  3. **Abort** — stop here.

  If user chooses option 2, set `$TARGET_REPO` to their input and re-run step 1b for the new repo.
  If user chooses option 3, exit.
  If user chooses option 1, set `$SKIP_SESSION_LABELS=true` and continue.

**1c. Create missing labels (only when not IaC-managed)**

Skip this step if `$SKIP_SESSION_LABELS=true`.

1. Check if `session-feedback` exists: `gh label list --json name --jq '.[].name' | grep -q session-feedback`
2. If missing: `gh label create session-feedback --description "Feedback from session analysis" --color "d876e3"`
3. Check if `positive-feedback` exists similarly.
4. If missing: `gh label create positive-feedback --description "Skills that worked well" --color "0e8a16"`

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

For each finding, search for existing issues in `$TARGET_REPO`:

```
gh issue list --label session-feedback --search "<skill-name> <key-phrase>" --json number,title --jq '.[].title'
```

Skip findings that match an existing open issue title. Note skipped items for the summary.

If `$SKIP_SESSION_LABELS=true`, search without labels: `gh issue list --search "feedback(<plugin>)" --json number,title --jq '.[].title'`

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

**Auto mode does not skip this step.** Filing a GitHub issue is not reversible via `git restore` — closing an issue leaves noise in the issue tracker and notifies subscribers. Always confirm the selection set before Step 5, regardless of mode. To skip the prompt entirely, the user can pass `--dry-run` and re-run after reviewing.

### Step 5: Create approved issues

For each approved finding, create a GitHub issue in `$TARGET_REPO`:

**Title format**: `feedback(<plugin-name>): <description>`

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

Create each issue:
```
gh issue create --title "feedback(<plugin>): <desc>" --label "<labels>" --body "<body>"
```

Append `-R $TARGET_REPO` when set. Omit `--label` if no labels apply (positive + `$SKIP_SESSION_LABELS`).

### Step 6: Report summary

Print a summary:

| Metric | Count |
|--------|-------|
| Findings identified | N |
| Duplicates skipped | N |
| Issues created | N |
| Skipped by user | N |

List created issue numbers with links. If `$SKIP_SESSION_LABELS=true`, remind the user to add `session-feedback` and `positive-feedback` to their IaC label definition.

## Agentic Optimizations

| Context | Command |
|---------|---------|
| List feedback issues | `gh issue list --label session-feedback --json number,title,labels -q '.[]'` |
| Search for duplicates | `gh issue list --label session-feedback --search "keyword" --json title -q '.[].title'` |
| Detect IaC label signals | `gh label list --json name,description --jq '.[].description'` |
| Check label exists | `gh label list --json name -q '.[].name'` |
| Create label | `gh label create name --description "desc" --color "hex"` |
| Create issue (with target) | `gh issue create -R owner/repo --title "t" --label "l1,l2" --body "b"` |
| Create issue (no labels) | `gh issue create -R owner/repo --title "t" --body "b"` |
| Infer current repo | `gh repo view --json nameWithOwner -q '.nameWithOwner'` |

## Quick Reference

| Flag | Description |
|------|-------------|
| `--dry-run` | Show findings without creating issues |
| `--bugs-only` | Only bug reports |
| `--enhancements-only` | Only enhancement suggestions |
| `--positive-only` | Only positive feedback |
| `--target-repo <owner/repo>` | File issues against a different repo (e.g. plugin source) |
| `-R <owner/repo>` | Alias for `--target-repo` |
| `[plugin-name]` | Scope to specific plugin |
