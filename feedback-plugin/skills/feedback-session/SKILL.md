---
name: feedback-session
description: Analyze session for skill feedback and create GitHub issues. Use when a skill gave wrong guidance, a command failed, you found a better pattern, or a skill worked well.
args: "[--dry-run] [--bugs-only] [--enhancements-only] [--positive-only] [--target-repo <owner/repo>] [plugin-name]"
allowed-tools: Bash(gh issue *), Bash(gh label *), Bash(gh search *), Bash(git status *), Bash(git remote *), Read, Grep, Glob, AskUserQuestion, TodoWrite
model: opus
argument-hint: "--dry-run | --target-repo owner/repo | plugin-name"
created: 2026-02-18
modified: 2026-06-28
reviewed: 2026-06-28
---

# /feedback:session

Analyze the current session for skill feedback and create GitHub issues to track bugs, enhancements, and positive patterns.

## When to Use This Skill

| Use this skill when... | Use alternative when... |
|------------------------|------------------------|
| A skill gave wrong or outdated guidance | Want to update skills directly -> `session-plugin:session-distill` |
| A command failed due to skill advice | Need static skill quality analysis -> `/health:audit` |
| Discovered a better flag or pattern | Want to capture general learnings -> `session-plugin:session-distill` |
| A skill worked particularly well | Want to track command usage stats -> `/analytics-report` |
| End of session, want to file feedback | Need to fix a skill right now -> edit the SKILL.md directly |
| Feedback is about the plugin itself | Use `--target-repo laurigates/claude-plugins` to file against the plugin source |

## Known Limitations

**IaC-managed labels**: Some repositories manage GitHub labels declaratively via Terraform, Pulumi, or similar tools. In these repos, `gh label create` will either be forbidden or cause drift that the IaC tool destroys on the next apply. This skill detects this case and offers a graceful fallback (see Step 1).

**Default target repo**: By default, this skill files issues against the repository in the current working directory. If you are giving feedback about a plugin skill itself rather than the application code in the session, use `--target-repo <owner/repo>` to point at the plugin source repo.

**Dominant-source mismatch**: When the cwd has a git remote but the session's tool calls were dominated by a *different* plugin/source repo, this skill detects the mismatch and asks you to confirm which repo to file against — the cwd repo or the plugin source. See Step 1a for the full four-combination decision table.

## Context

Git remote and target-repo detection happens during Step 1a (execution), not
in this Context block. `git remote -v` and `gh repo view` both write to
stderr when invoked outside a git repository — and stderr from a Context
backtick aborts the skill before its body runs. `2>/dev/null` and `||` are
also blocked in Context commands (see `.claude/rules/agentic-permissions.md`),
so there is no fallback form that survives the no-git case. Step 1a's
dominant-source scan runs for both the cwd-with-remote and the no-remote
cases, and surfaces a mismatch-confirmation prompt when the session's plugin
activity points to a different repo than the cwd remote.

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
| `<freeform prose>` | Any non-flag, non-plugin-name text is treated as one or more **explicit seed findings** to file (see below) |

After parsing, set `$TARGET_REPO` to the value of `--target-repo`/`-R` if provided. Append `-R $TARGET_REPO` to all `gh` commands below when `$TARGET_REPO` is set.

**Freeform feedback prose is a first-class input.** After removing the
recognized flags and any leading `[plugin-name]` token from `$ARGUMENTS`, treat
whatever prose remains as one or more explicit findings the user wants filed —
not as a transcript to scan. Record this remainder as `$SEED_FINDINGS` and feed
it into Step 2. Flags and prose coexist: `--target-repo X "the skill should do
Y"` files finding "the skill should do Y" against repo `X`. A bare invocation
with no prose falls back to the transcript scan as before.

## Execution

Execute this session feedback workflow:

### Step 1: Resolve target repo and ensure labels exist

**1a. Determine target repo**

Use this four-combination decision table to resolve `$TARGET_REPO`:

| `--target-repo` set? | cwd has remote? | Dominant source found? | Action |
|----------------------|-----------------|------------------------|--------|
| Yes | any | any | Use `--target-repo` value. Done. |
| No | No | Yes (≥70%, ≥3 refs) | Prompt: accept dominant source or enter free-text. |
| No | No | No | Prompt: free-text entry or abort. |
| No | Yes | Agrees with cwd remote | Use cwd remote silently. |
| No | Yes | Differs from cwd remote | Prompt: offer dominant source AND cwd remote as named choices. |

Execute the steps below to implement this table.

**Step A: Check for explicit `--target-repo` / `-R`.**

If `--target-repo` or `-R` was passed in `$ARGUMENTS`, set `$TARGET_REPO` to that value and append `-R $TARGET_REPO` to every `gh` command in the remaining steps. Skip the rest of this sub-step.

**Step B: Run the dominant-source scan (always).**

Walk the conversation transcript and tool-call history collecting every reference of the form `<plugin>:<skill>` (skill invocations like `/blueprint:init`, agent IDs like `agents-plugin:security-audit`, and plugin names mentioned in skill bodies). For each match, look up the owning `<owner>/<repo>` by enumerating directories under `~/.claude/plugins/cache/<owner>/<repo>/` and matching `<plugin>` against the cached plugin manifests. Tally references per `<owner>/<repo>`.

Compute the share per entry. If the top entry accounts for **more than ~70%** of total references **and** there are at least 3 references in total, treat it as dominant: record `$SUGGESTED_REPO` and `$N`.

**Step C: Attempt cwd remote detection.**

Run `gh repo view --json nameWithOwner -q '.nameWithOwner'`. If it succeeds, record the result as `$CWD_REPO`.

**Step D: Branch on the combination.**

- **No `$CWD_REPO` and no dominant source** — Use AskUserQuestion to ask the user to enter an `owner/repo` free-text. Validate against `^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$`, set `$TARGET_REPO`, and continue to Step 1b. If the user declines, exit the skill.

- **No `$CWD_REPO` and dominant source found** — Use AskUserQuestion to ask:

  > **No git remote found.** Suggested target: `$SUGGESTED_REPO` (derived from $N plugin skills referenced this session). Accept, or enter a different `owner/repo`?

  Options:
  1. **Accept `$SUGGESTED_REPO`** — set `$TARGET_REPO` to the suggestion and append `-R $TARGET_REPO` to every remaining `gh` command.
  2. **Enter a different `owner/repo`** — free-text follow-up; validate and set `$TARGET_REPO`.
  3. **Abort** — exit the skill.

  Continue to Step 1b once `$TARGET_REPO` is set.

- **`$CWD_REPO` present, no dominant source OR dominant source == `$CWD_REPO`** — use `$CWD_REPO` silently as the implicit target (`gh` defaults to cwd; no `-R` needed). Continue to Step 1b.

- **`$CWD_REPO` present AND dominant source differs from `$CWD_REPO`** — the session's plugin activity pointed mostly at a different repo than the cwd remote. Use AskUserQuestion to ask:

  > **Mismatch detected.** The session's tool calls were dominated by **`$SUGGESTED_REPO`** ($N references), but the current directory's git remote points to **`$CWD_REPO`**. Which repo should receive the feedback?

  Options:
  1. **`$SUGGESTED_REPO`** (plugin/skill source — dominant this session) — set `$TARGET_REPO` to `$SUGGESTED_REPO` and append `-R $TARGET_REPO` to all remaining `gh` commands.
  2. **`$CWD_REPO`** (cwd git remote — the application repo) — use `$CWD_REPO` silently (no `-R` needed).
  3. **Enter a different `owner/repo`** — free-text follow-up; validate and set `$TARGET_REPO`.
  4. **Abort** — exit the skill.

  Continue to Step 1b once the choice is resolved.

#### Dominant-source detection: parameters and tiering

The thresholds and prompt order above are deliberate. Keep them aligned when editing this step.

| Parameter | Value | Why |
|-----------|-------|-----|
| Dominance threshold | **> 70%** of total references | Lower thresholds risk wrong defaults on mixed sessions; higher would suppress correct suggestions on small ones |
| Minimum sample size | **≥ 3** references | Two references can both come from one stray skill mention; three is the smallest sample that survives one outlier |
| Prompt tiering | suggestion → free-text → abort | The user can correct a wrong guess in one keystroke without redoing the scan, and `Abort` is always one selection away |
| Mismatch prompt | named choices (dominant / cwd / free-text / abort) | Both repos are plausible; naming them saves the user a copy-paste and makes the choice explicit |

Evidence: issue #1207 (positive feedback) reported the first end-to-end exercise of this fallback in a no-remote cwd. The 3/3 100%-dominant case auto-suggested `laurigates/claude-plugins`, the user accepted on the first prompt, and the free-text tier never fired — confirming the "Recommended" affordance lands the suggestion cleanly when the heuristic is well-tuned. Issue #1425 extended the dominant-source scan to the cwd-with-remote branch so the mismatch is surfaced rather than silently dropped.

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

### Step 2: Collect findings (seed prose first, then conversation history)

**2a. Seed findings from freeform prose.** If `$SEED_FINDINGS` is non-empty
(see Parameters), each distinct statement in it is an **explicit finding** the
user asked to file. Split it into one finding per concern (the user may pass
several, e.g. "two things. firstly… also…"). For each, infer the category
(bug / enhancement / positive) from the wording; if a finding's category is
ambiguous, ask via AskUserQuestion rather than guessing. These seed findings
flow through dedup (Step 3), the confirmation prompt (Step 4), and issue
creation (Step 5) exactly like scanned findings. When `$SEED_FINDINGS` is
present, the transcript scan in 2b is **optional context**, not the primary
source — do not let inference override what the user explicitly stated.

**2b. Scan the conversation history.** When `$SEED_FINDINGS` is empty (a bare
invocation), this scan is the primary source of findings.

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

**In plan mode**: neither `AskUserQuestion` nor the subsequent `gh issue create` call is permitted — the harness disallows non-readonly tool calls except writes to the active plan file. Write the categorized findings to the active plan file as a single coherent block (one section per finding with category, plugin/skill, description, evidence, and proposed title/body), then call `ExitPlanMode` to surface for user approval. Do not file issues directly. After the user approves the plan, fall back to the default flow: present the selection prompt via `AskUserQuestion` (Step 4) and create the approved issues (Step 5). The `--dry-run` flag remains the fastest way to preview findings without entering plan mode.

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
| `<freeform prose>` | Explicit seed finding(s) to file; coexists with flags |
