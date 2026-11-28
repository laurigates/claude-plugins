---
name: session-workflow-capture
description: "Workflow-tool scripts and workflow friction from this session, filed as issues here or in the plugins repo. Use when a session ran Workflow scripts."
allowed-tools: Bash(bash ${CLAUDE_SKILL_DIR}/../../scripts/workflow-capture-survey.sh *), Bash(bash ${CLAUDE_SKILL_DIR}/../../scripts/check-issue-draft.sh *), Bash(mktemp *), Bash(gh issue list *), Bash(gh issue create *), Bash(gh label list *), Bash(gh label create *), Bash(gh repo list *), mcp__github__list_issues, mcp__github__get_label, mcp__github__issue_write, Read, Write, Skill, AskUserQuestion
argument-hint: "--dry-run | --orchestrated | --plugins-repo owner/name | --usage"
args: "[--dry-run] [--orchestrated] [--plugins-repo <owner/name>] [--usage [--all-projects]]"
created: 2026-11-14
modified: 2026-11-28
reviewed: 2026-11-14
---

# session-workflow-capture

Turn what this session learned about Claude Code dynamic workflows (the
Workflow tool) into issues: a reusable script becomes a proposal to save or
template it, a misbehaving workflow becomes a fix request. Repo-specific
findings go to the calling repository; generic ones go to the plugins
repository, stripped of anything that points at this machine, session or
project.

## When to Use This Skill

| Use this skill when... | Use the sibling instead when... |
|---|---|
| The session authored or adapted a Workflow script and its shape is reusable | A multi-step procedure ran without a Workflow script → `session-plugin:session-distill` (`--process`) |
| A saved or plugin-bundled workflow needed rework, reruns or a resume | A skill body misbehaved → `feedback-plugin:feedback-session` (plugin-workflow friction is filed here in its title and label shape) |
| You want to know how often saved workflows actually run (`--usage`) | Loose threads and follow-up tasks → `session-plugin:session-wrap` |
| `session-plugin:session-end` qualified the Workflow capture pass | Designing or running a new workflow → `workflow-orchestration-plugin:workflow-bake-off` and its siblings |

## Context

- Saved project workflows: !`find . -maxdepth 3 -path '*/.claude/workflows/*' -name '*.js' -not -path '*/node_modules/*'`

## Parameters

| Parameter | Meaning |
|---|---|
| `--dry-run` | Draft and gate every issue, file none, print the drafts' paths and verdicts |
| `--orchestrated` | Set by `session-plugin:session-end`. File what passed its gates without any `AskUserQuestion`; return every other draft as a `DEFERRED: <tracker> — <title> — <why> — <draft path>` line |
| `--plugins-repo <owner/name>` | Override the tracker for generic patterns; the default is the survey's `PLUGINS_REPO` ([how it is chosen](references/collector-digest.md#session-mode-sections)) |
| `--usage` | Report how Workflow calls split across inline scripts, `scriptPath` reruns and saved or plugin workflows run by name, over recent transcripts (`--all-projects` widens it). Files nothing |

## Execution

Execute this capture. A public draft files only after both Step 5 gates pass.

### Step 1: Survey the session's workflow runs

```sh
bash "${CLAUDE_SKILL_DIR}/../../scripts/workflow-capture-survey.sh" --session-id "${CLAUDE_SESSION_ID}"
```

It lists every script the harness persisted this session, each run's agent
counts, and whether a script matches a saved or bundled workflow byte-for-byte
(`verbatim`), by `meta.name` only (`adapted`), or not at all (`authored`);
fields in [references/collector-digest.md](references/collector-digest.md).
Reuse a digest session-end already passed.

With `--usage`, run `workflow-capture-survey.sh --usage` (add `--all-projects`),
report the `WORKFLOW USAGE` counts, and stop.

On `STATUS=SKIP` (no transcript) or `WARN` (layout moved; report the `REASON`),
judge from the conversation alone. If the session ran no Workflow and no
workflow caused friction, say so in one line and end.

### Step 2: Judge the findings

Read the latest script of each `authored` or `adapted` workflow and the
conversation around its runs. Keep two kinds of finding:

- **Pattern**: a whole script, a stage, a schema or a verification shape that
  another task could reuse. It must pass all three reusability questions; one
  "no" means it stays a one-off, reported as skipped with the reason.
- **Friction**: an existing workflow, saved or bundled, that cost the session
  something. The collector's `SIGNALS` (`reran`, `unfinished_agents`,
  `resumed`, `adapted_known`) point at candidates; the conversation supplies
  the cause (a schema rejection, a scale-guard prompt, a wrong instruction in
  a template's framing section, an agent budget that did not match). An
  `unfinished_agents` run is reported, not recovered: recovery belongs to
  `workflow-orchestration-plugin:workflow-interrupted-run-recovery`.

| Reusability question | A "no" looks like |
|---|---|
| Is the fan-out width enumerable by something other than the model (a file list, a script's rows, the caller's args)? | The script invents its own N ("6 lenses x 4 agents") |
| If it has a barrier, does a later stage need all earlier results at once? | The barrier only collects what one agent could have summarised inline |
| Is every loop bound decided by a script or a constant that survives a re-run? | The bound is a JS local that resets when the run is re-driven |

A `verbatim` run with no friction is not a finding, nor is a pattern
`session-plugin:session-distill` already proposed as a `[PROMOTE]` PR this
session. Cost a pattern whose agent count grows with the input with
`workflow-orchestration-plugin:workflow-scale-budget`.

### Step 3: Route each finding to one tracker

| Finding | Tracker | Audience |
|---|---|---|
| A pattern that depends on this repo's files, data or domain; friction in a workflow saved in this repo | `CALLING_REPO` | `project` |
| A pattern reusable in any repository | `--plugins-repo`, else `PLUGINS_REPO` | `public` |
| Friction in a plugin-bundled or plugin-registered workflow (`MATCH` names a `bundled` or `plugin` workflow) | `WORKFLOW_n_MATCH_REPO`, in feedback-session's `feedback(<plugin>):` / `session-feedback` shape so its weekly friction review reads it | `public` |
| Friction in a user's own saved workflow (`MATCH` is `user:`) | none: report it | — |

A finding with a generic kernel inside a repo-specific script goes to the
plugins repository only if the kernel survives stripping every repo detail;
otherwise it is a `project` finding. When `CALLING_REPO` equals the plugins
repository, both kinds go there and generic drafts still use `public`. With
`CALLING_REPO=unknown` (no remote, or a host other than GitHub), report
`project` findings instead of filing them.

### Step 4: Draft each issue

Write one draft per finding into a directory from `mktemp -d`, using the
title and body shapes in [references/issue-format.md](references/issue-format.md).
A `public` draft is a rewrite, not a redaction: placeholders for paths and
names, a skeleton in place of the script, the outcome stated without the
project it happened in.

### Step 5: Gate every draft

1. Scan it. For a `public` draft, first write a deny file of literal terms:
   the calling owner's private repository names (`gh repo list <owner>
   --visibility private --json name --jq '.[].name' --limit 1000`, when `gh`
   can list them) plus people, hosts, codenames and in-repo paths the session
   mentioned. The scan has no rule for those, only the deny file.

   ```sh
   bash "${CLAUDE_SKILL_DIR}/../../scripts/check-issue-draft.sh" --draft <file> --audience <public|project> --target-repo <owner/name> --deny-file <terms-file>
   ```

   `STATUS=ERROR`: rewrite the flagged lines and scan once more; a second
   ERROR means the draft is never filed and is reported as blocked.
   `STATUS=WARN`: fix each row or keep it with a stated reason.
2. Cold-read every `public` draft with `agent-patterns-plugin:cold-read-gate`,
   adding one item to the reader's brief: "list every name, host, id, ticket,
   channel, path or person that identifies a specific organisation or
   project". Any item listed, or a needs-revision verdict, fails the draft.
   Revise once. If the gate is unavailable or still fails, the draft goes to
   the Ask lane; that overrides the gate's own publish-anyway fallback.

### Step 6: Deduplicate and file

Search the tracker's open issues for the same workflow and problem:
`gh issue list -R <repo> --state open --search "<workflow name> in:title" --json number,title,url --limit 20`
(plugin-workflow friction: add `--label session-feedback`), or the GitHub MCP
`list_issues` tool where `gh` is REST-only. A duplicate is skipped and its URL
reported; this skill does not comment. A draft whose dedup could not run is
deferred, never filed blind.

Apply labels per [references/issue-format.md](references/issue-format.md#labels);
a missing label is created only where the tracker's labels are not managed as
code.

| Mode | What is filed |
|---|---|
| `--dry-run` | Nothing; report each draft's path and gate verdicts |
| `--orchestrated` | Every `project` draft whose scan passed, and every `public` draft that passed both gates. All others become `DEFERRED:` lines |
| Standalone | One `AskUserQuestion`: up to 4 questions grouped by tracker, each `multiSelect`, one option per draft whose scan passed; then file the selection |

File with `gh issue create -R <repo> --title "<title>" --body-file <draft> --label <label>`
(`workflow-capture`, or `session-feedback` plus `bug` or `enhancement` for
plugin-workflow friction, each where it exists).
Where `gh` cannot create issues (a cloud session's REST-only `gh api`), file
through the GitHub MCP `issue_write` tool with the draft's text as the body.

### Step 7: Report

List filed issues with URLs (the plugin-workflow friction ones marked, so
session-end's feedback pass does not file them again), `DEFERRED:` lines,
duplicates with their URLs, drafts blocked by the scan, and skipped candidates
with the failed question or reason.

