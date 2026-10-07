---
name: feedback-session
description: Analyze session for skill feedback and create GitHub issues. Use when a skill gave wrong guidance, a command failed, you found a better pattern, or a skill worked well.
args: "[--dry-run] [--bugs-only] [--enhancements-only] [--positive-only] [--target-repo <owner/repo>] [plugin-name]"
allowed-tools: Bash(gh issue *), Bash(gh label *), Bash(gh search *), Bash(git status *), Bash(git remote *), Read, Grep, Glob, AskUserQuestion, TodoWrite
model: opus
argument-hint: "--dry-run | --target-repo owner/repo | plugin-name"
created: 2026-02-18
modified: 2026-07-18
compatibility: claude-code
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

## Context

Detection runs at execution time (Steps 1a, 3); why, and known limitations: [references/design-notes.md](references/design-notes.md).

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

Steps A–D implement the decision table in [references/target-repo-resolution.md](references/target-repo-resolution.md).

**Step A: Check for explicit `--target-repo` / `-R`.**

If `--target-repo` or `-R` was passed in `$ARGUMENTS`, set `$TARGET_REPO` to that value and append `-R $TARGET_REPO` to every `gh` command in the remaining steps. Skip the rest of this sub-step.

**Step B: Run the dominant-source scan (always).**

Walk the conversation transcript and tool-call history collecting every reference of the form `<plugin>:<skill>` (skill invocations like `/blueprint:init`, agent IDs like `agents-plugin:security-audit`, and plugin names mentioned in skill bodies). For each match, look up the owning `<owner>/<repo>` by enumerating directories under `~/.claude/plugins/cache/<owner>/<repo>/` and matching `<plugin>` against the cached plugin manifests. Tally references per `<owner>/<repo>`.

Compute the share per entry. If the top entry accounts for **more than ~70%** of total references **and** there are at least 3 references in total, treat it as dominant: record `$SUGGESTED_REPO` and `$N`.

**Step C: Attempt cwd remote detection.**

Run `gh repo view --json nameWithOwner -q '.nameWithOwner'`. If it succeeds, record the result as `$CWD_REPO`.

**Step D: Branch on the combination.**

- **No `$CWD_REPO`** — prompt per [references/target-repo-resolution.md](references/target-repo-resolution.md#step-d-branches-when-the-cwd-has-no-git-remote), then continue to Step 1b.

- **`$CWD_REPO` present, no dominant source OR dominant source == `$CWD_REPO`** — use `$CWD_REPO` silently as the implicit target (`gh` defaults to cwd; no `-R` needed). Continue to Step 1b.

- **`$CWD_REPO` present AND dominant source differs from `$CWD_REPO`** — the session's plugin activity pointed mostly at a different repo than the cwd remote. Use AskUserQuestion to ask:

  > **Mismatch detected.** The session's tool calls were dominated by **`$SUGGESTED_REPO`** ($N references), but the current directory's git remote points to **`$CWD_REPO`**. Which repo should receive the feedback?

  Options:
  1. **`$SUGGESTED_REPO`** (plugin/skill source — dominant this session) — set `$TARGET_REPO` to `$SUGGESTED_REPO` and append `-R $TARGET_REPO` to all remaining `gh` commands.
  2. **`$CWD_REPO`** (cwd git remote — the application repo) — use `$CWD_REPO` silently (no `-R` needed).
  3. **Enter a different `owner/repo`** — free-text follow-up; validate and set `$TARGET_REPO`.
  4. **Abort** — exit the skill.

  Continue to Step 1b once the choice is resolved.

Thresholds and evidence: [references/target-repo-resolution.md](references/target-repo-resolution.md) — read before editing this step.

**1b–1c. Check IaC-managed labels, then create missing labels**

Follow [references/labels.md](references/labels.md): detect IaC-managed labels (may set `$SKIP_SESSION_LABELS=true`), then create any missing feedback labels.

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

Categories (**bug**, **enhancement**, **positive**) and their signals: [references/finding-signals.md](references/finding-signals.md).

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

Use the one-line finding format in [references/issue-format.md](references/issue-format.md#step-4-finding-format).

Let the user select which findings to file as issues (use multiSelect).

If `--dry-run`, present findings and stop here.

**Auto mode does not skip this step.** Filing a GitHub issue is not reversible via `git restore` — closing an issue leaves noise in the issue tracker and notifies subscribers. Always confirm the selection set before Step 5, regardless of mode. To skip the prompt entirely, the user can pass `--dry-run` and re-run after reviewing.

**In plan mode**: do not file issues; follow [references/plan-mode.md](references/plan-mode.md).

### Step 5: Create approved issues

For each approved finding, create a GitHub issue in `$TARGET_REPO`:

**Title format**: `feedback(<plugin-name>): <description>`

Labels and body template: [references/issue-format.md](references/issue-format.md).

Create each issue:
```
gh issue create --title "feedback(<plugin>): <desc>" --label "<labels>" --body "<body>"
```

Append `-R $TARGET_REPO` when set. Omit `--label` if no labels apply (positive + `$SKIP_SESSION_LABELS`).

### Step 6: Report summary

Print the summary table in [references/issue-format.md](references/issue-format.md#step-6-summary-table).

List created issue numbers with links. If `$SKIP_SESSION_LABELS=true`, remind the user to add `session-feedback` and `positive-feedback` to their IaC label definition.

## Agentic Optimizations

Compact `gh` commands and flag reference: [references/command-reference.md](references/command-reference.md).

