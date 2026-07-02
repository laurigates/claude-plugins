---
name: task-reconcile
description: Close taskwarrior tasks whose linked GitHub issue/PR closed or merged. Use when stale trackers pile up, after a PR-merge sweep, or auditing queue drift.
args: "[--apply] [--project=<name>] [--all]"
allowed-tools: Bash(task *), Bash(gh issue *), Bash(gh pr *), Bash(jq *), Bash(bash *), Bash(git rev-parse *), Read, TodoWrite
argument-hint: optional --apply to close (default dry-run preview)
created: 2026-06-20
modified: 2026-07-02
reviewed: 2026-07-02
---

# /taskwarrior:task-reconcile

Close the tasks that have gone stale because the GitHub issue or PR they
mirror has closed or merged. `task-status` *detects* this drift; this skill
*acts* on it, so the queue does not silently fill with trackers for work that
already shipped.

A task is "linked" whether it carries a `ghid`/`ghpr` UDA **or** references an
issue/PR in its description/annotation text (a `#N`, an `owner/repo#N`, or a
`github.com/owner/repo/(issues|pull)/N` URL) — so tasks filed with a plain
`#N` in the description are reconciled too, and a cross-repo `owner/repo#N` is
checked against *that* repo, not the current one.

## When to Use This Skill

| Use this skill when... | Use a sibling skill instead when... |
|---|---|
| Stale tasks (`ghid`/`ghpr` UDA **or** a `#N`/`owner/repo#N`/URL in the description) have piled up after issues/PRs closed | Auditing queue health without mutating it — use `task-status` |
| Sweeping the queue after a batch of PRs merged | Closing one specific task by ID with a landing commit — use `task-done` |
| Reconciling the local queue against GitHub as the source of record | Filing a new linked task — use `task-add` |

## Context

- Task CLI available: !`task --version`
- Git repo detected: !`find . -maxdepth 1 -name '.git' -print -quit`
- GH auth: !`gh auth status`

GitHub-mode and project resolution run in the body (Step 1) via the bundled
scripts, where stderr suppression and exit-code handling are available — git /
gh probes in a Context backtick abort the skill in a no-git/no-remote cwd.

## Parameters

Parse `$ARGUMENTS`:

- `--apply` — perform the close. Without it the skill runs a **dry-run preview**
  first, then asks once before closing.
- `--project=<name>` — override the auto-detected project filter.
- `--all` — reconcile across every project (rare; usually you want one repo).
- `--limit=N` — cap how many linked tasks are inspected (default 200).

## Execution

Execute this reconciliation workflow:

### Step 1: Resolve scope

Run the shared project resolver (handles `--project` / `--all` / git-toplevel /
cwd, with no stderr-emitting git probes):

```bash
bash "${CLAUDE_SKILL_DIR}/../../scripts/resolve-project.sh" --project-dir "$(pwd)"
```

Read `PROJECT=` from the output. GitHub mode must be on (an authenticated `gh`
plus a remote) — the reconcile script reports `GH_AVAILABLE=false` and exits
cleanly if not.

### Step 2: Dry-run classification

Run the reconcile script **without** `--apply` to classify every linked task:

```bash
bash "${CLAUDE_SKILL_DIR}/scripts/reconcile.sh" --project=PROJECT --project-dir "$(pwd)"
```

It emits one `TASK ...` line per linked task with its `refs` count, `upstream`
state(s), a `verdict` (`live` / `issue-closed` / `pr-merged` / `pr-closed`), and
the close `method` it would use (`bulk` / `done` / `keep`). A task with several
refs is stale only when **every** ref is done — any open ref keeps it `live`,
any unreadable ref keeps it (uncertain), and a `pr-closed` among them makes the
aggregate `pr-closed` (kept out of the bounded auto-apply set). Render the stale
set as a table for the user, and read the `STALE_COUNT` / `BULK_COUNT` /
`DONE_COUNT` summary.

### Step 3: Confirm and apply

If `STALE_COUNT` is 0, report "queue is in sync" and stop.

If `--apply` was passed in `$ARGUMENTS`, skip straight to running with `--apply`.
Otherwise confirm once with **AskUserQuestion** (never a freeform "y/n" — see
`.claude/rules/skill-execution-structure.md`): "Close N stale task(s)?" with
options to proceed, review the table again, or cancel.

On confirmation, re-run with `--apply`:

```bash
bash "${CLAUDE_SKILL_DIR}/scripts/reconcile.sh" --apply --project=PROJECT --project-dir "$(pwd)"
```

Each closed task is annotated with the reason (`reconcile: PR #45 merged`).
Leaf tasks close via a bulk `task import` round-trip; tasks that block others
close via per-task `task done` so taskwarrior's dependency auto-unblock fires
(see [REFERENCE.md](REFERENCE.md) for why the two paths differ).

### Step 4: Report

Print `CLOSED_COUNT`, the per-task verdicts, and any `UNKNOWN_UPSTREAM` count
(tasks whose issue/PR could not be fetched — left untouched, never closed on
uncertainty). Suggest `/taskwarrior:task-status` to confirm the queue is clean.

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Dry-run classify | `bash scripts/reconcile.sh --project=PROJECT` |
| Apply the close | `bash scripts/reconcile.sh --apply --project=PROJECT` |
| Cross-project sweep | `bash scripts/reconcile.sh --all` |
| UDA-linked snapshot (description refs also matched by the script) | `task project:PROJECT status:pending export \| jq '[.[] \| select(.ghid != null or .ghpr != null)]'` |
| Issue state | `gh issue view N --json state --jq '.state'` |
| PR state (per gh-json-fields) | `gh pr view N --json state --jq '.state'` |
| Cross-repo ref state | `gh pr view N -R owner/repo --json state --jq '.state'` |
| Skip empty-filter failures | Always `export \| jq`, never `list` |

## Quick Reference

| Flag | Default | Purpose |
|------|---------|---------|
| `--apply` | off (dry-run) | Perform the close |
| `--project=<name>` | repo basename | Override the project filter |
| `--all` | off | Reconcile across every project |
| `--limit=N` | 200 | Max linked tasks to inspect |
| `--only-verdicts=<csv>` | unset (all stale closeable) | Restrict the apply set to these verdicts (e.g. `pr-merged,issue-closed`); other stale verdicts (notably `pr-closed`) are reported `method=keep` but never closed. Used by the scheduled bounded auto-apply (`scripts/scheduled-reconcile.sh --apply`) |

| Verdict | Meaning | Close method |
|---------|---------|--------------|
| `live` | A referenced issue/PR is still open (or a ref was unreadable) | keep |
| `issue-closed` | Every referenced issue is CLOSED (no merged/closed PR among them) | bulk / done |
| `pr-merged` | A referenced PR is MERGED and no referenced item is still open | bulk / done |
| `pr-closed` | A referenced PR is CLOSED unmerged (ambiguous — abandoned vs superseded) | bulk / done |

## Related

- `/taskwarrior:task-status` — detects the drift this skill resolves
- `/taskwarrior:task-done` — close one task with a landing commit
- `/taskwarrior:task-add` — file the linked tasks this skill later reconciles
- `.claude/rules/gh-json-fields.md` — `state`/`mergedAt` (never a `merged` field)
- `.claude/rules/parallel-safe-queries.md` — the `export | jq` idiom
- `taskwarrior-plugin/skills/task-reconcile/REFERENCE.md` — bulk-vs-done routing, `task import` caveats
