# feedback-plugin

Session feedback analysis — capture per-session skill bugs as GitHub issues, and learn recurring friction across a week of sessions via the `friction-learner` agent.

## Skills

| Skill | Description |
|-------|-------------|
| `/feedback:session` | Analyze session for skill feedback and create GitHub issues |

## Agents

| Agent | Description |
|-------|-------------|
| `friction-learner` | The **slow loop**: read open `session-feedback` issues as pre-registered signal, parse last week of transcripts, cluster interruptions/hook-blocks/rejections, corroborate/escalate clusters against the fast-loop issues, propose rule/skill/hook fixes, reproduce-and-verify each fix where safe, open one PR per target repo cross-linking the fast-loop issues |

## Hooks

| Hook | Event | Default |
|------|-------|---------|
| `check-open-pr.sh` | `PreToolUse: Bash` | Enabled |
| `skill-usage-log.sh` | `PreToolUse: Skill\|SlashCommand` + `UserPromptSubmit` | **Opt-in** |

### Skill-usage log (opt-in)

```bash
export CLAUDE_HOOKS_ENABLE_SKILL_USAGE_LOG=1
```

Appends one JSONL record per skill invocation to `~/.claude/skill-usage.jsonl`,
so usage history outlives transcript retention. Opt-in because every turn pays a
`UserPromptSubmit` fire and the log is only useful to someone who intends to
analyse it later; custom path via `CLAUDE_SKILL_USAGE_LOG`.

It fires on **two** events, because skills arrive by two different paths:

| Event | Path | Record `src` |
|-------|------|--------------|
| `PreToolUse` (`Skill`, `SlashCommand`) | The model invokes a skill | `tool` |
| `UserPromptSubmit` | The user types `/plugin:skill` | `slash` |

A user-typed slash command never reaches a tool — the client expands it into the
prompt itself — so a `PreToolUse` hook alone misses every one of them. In a
1,134-session transcript sweep, 11 of the 57 used skills appeared *only* by that
path.

Each record carries `ts`, `src`, `skill`, `plugin`, `args` (+ untruncated
`args_len`), `session`, `cwd`, `repo`, `branch`, `permission_mode`, `effort`.
The hook never writes to stdout — a `UserPromptSubmit` hook's stdout is injected
into the model's context — and rotates at 16 MB.

### Skill usage report

```bash
python3 feedback-plugin/scripts/skill_usage_report.py --since 30d --include-transcripts
```

Merges the durable log with the (expiring) transcripts and buckets the installed
catalog into `active` / `dormant` / `never`, emitting the `KEY=VALUE` diagnostic
convention plus `--json` for an agent. `friction-learner` Step 1b reads it to
decide **which** skills are worth analysing — see the caveats there; `never` is a
floor bounded by `COVERAGE_SINCE`, not a verdict.

### Friction learner

Spawn via the Agent tool or wire to a weekly cron:

```
Agent({
  subagent_type: "friction-learner",
  prompt: "Analyze the last 7 days of sessions. Target repo: laurigates/claude-plugins. Open a PR with proposed rule edits.",
})
```

Dry-run the pipeline manually:

```bash
python3 feedback-plugin/scripts/friction_parse.py --since 7d --out /tmp/frictions.jsonl
python3 feedback-plugin/scripts/friction_cluster.py --in /tmp/frictions.jsonl --min-count 3 \
  --render-pr-body /tmp/pr-body.md --out /tmp/clusters.json
python3 feedback-plugin/scripts/friction_open_prs.py \
  --clusters /tmp/clusters.json --pr-body /tmp/pr-body.md \
  --target-repo laurigates/claude-plugins --dry-run
```

Signatures currently recognized: `plan:entered-plan-mode`, `push:branch-has-open-pr`, `hook:pr-metadata`, `hook:branch-protection`, `hook:conventional-commit`, `hook:gitleaks`, `hook:pre-commit`, `error:<tool>:<class>`, `reject:<tool>`, `interrupt:user`.

Before opening a PR, the agent reproduces each actionable failure and runs the
proposed fix's prescribed substitution where it is safe and read-only (hook
blocks are safe by construction — the blocked command never executes). Clusters
that no longer reproduce are downgraded to watch items, and each PR body
carries a `## Verification` table with one verdict per cluster
(`REPRODUCED_FIX_VERIFIED` / `REPRODUCED_FIX_UNVERIFIED` / `NOT_REPRODUCED` /
`NOT_REPRODUCIBLE`).

**Two-speed feedback (fast ↔ slow).** `friction-learner` is the *slow loop*; the
*fast loop* is the `/feedback:session` skill, which files per-session,
human-authored issues under the shared `session-feedback` / `positive-feedback`
labels. At the start of its weekly run the agent reads the open `session-feedback`
issues as **pre-registered signal**, corroborates or escalates them against its
quantitative transcript clusters (a human-noticed pain confirmed by the data is
the highest-confidence deliverable; a reported pain below the count threshold is
escalated as a watch item), and cross-links the issue numbers in the PR body's
`## Fast-loop signal` section. See `docs/archive/session-plugin-workflow.md` for the full
architecture.

## Hooks

| Hook | Event | Purpose |
|------|-------|---------|
| `check-open-pr.sh` | `PreToolUse` (Bash) | Prompt before `git push` to a branch that already has an open PR. Include `[force-push-ok]` in the last commit message to bypass. |

## Usage

```bash
# Analyze full session
/feedback:session

# Dry run - see findings without creating issues
/feedback:session --dry-run

# Only bugs
/feedback:session --bugs-only

# Only for a specific plugin
/feedback:session git-plugin

# Only positive feedback
/feedback:session --positive-only

# File feedback against the plugin source repo (not the cwd repo)
/feedback:session --target-repo laurigates/claude-plugins

# Short form
/feedback:session -R laurigates/claude-plugins
```

## Labels

The plugin creates and uses these GitHub labels:

| Label | Color | Purpose |
|-------|-------|---------|
| `session-feedback` | Purple | Bugs and enhancements from session analysis |
| `positive-feedback` | Green | Skills that worked well (stability markers) |

> **IaC-managed labels**: If your repository manages labels declaratively (Terraform, Pulumi, etc.), the skill detects this and offers to proceed without `session-feedback`/`positive-feedback` labels, or to target a different repo. Add the two labels to your IaC definition to restore full labeling. See the [Known Limitations](#known-limitations) section for details.

## Issue Format

Issues are created with conventional title format:

```
feedback(<plugin-name>): <description>
```

This integrates with the project's conventional commit workflow.

## Workflow

1. Use skills during a session
2. At end of session, run `/feedback:session`
3. Review categorized findings
4. Select which to file as issues
5. Issues are created with appropriate labels and body
6. Use `session-plugin:session-distill` to actually update the skills based on filed issues

## Known Limitations

### IaC-managed labels

Some repositories manage GitHub labels declaratively using Terraform, Pulumi, CDK, or similar tools. Creating labels out-of-band with `gh label create` in these repos causes two problems:

1. **Drift**: The IaC tool destroys the manually-created label on the next apply.
2. **Policy**: Many org-level IaC setups explicitly forbid direct label creation.

The skill detects IaC label management by:
- Scanning existing label descriptions for keywords like `terraform`, `pulumi`, `managed by`, `iac`
- Looking for `labels.tf` or `labels.yaml` files in the working tree

When detected, the skill offers three options:
1. **Proceed without `session-feedback` labels** — issues are created with only `bug`/`enhancement` labels
2. **Use a different target repo** — file the issue against a repo where labels can be created freely
3. **Abort**

### Default target repo

By default, issues are filed against the repository in the current working directory. When giving feedback about a plugin skill itself (rather than the application code in the session), use `--target-repo <owner/repo>` to point at the plugin source repo (e.g. `laurigates/claude-plugins`).
