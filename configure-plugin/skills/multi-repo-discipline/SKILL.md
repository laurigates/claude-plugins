---
name: multi-repo-discipline
description: |
  Advisory rules for working in a multi-repository workspace — read-only
  fixtures, upstream/downstream pairs, and authoritative repos that own
  shared specs. Covers when cross-repo edits are allowed during agent
  dispatch vs when commits in sibling repos require user confirmation.
  Use when starting work in a parent directory that contains multiple
  git repos, when dispatching agents that may touch sibling repos, when
  updating a spec in an authoritative repo with downstream consumers,
  or when a skill is about to edit a sibling's `CLAUDE.md` / `.claude/`.
allowed-tools: Bash(git rev-parse *), Bash(git status *), Bash(git branch *), Bash(git remote *), Bash(git log *), Read, Glob, Grep, TodoWrite
created: 2026-04-24
modified: 2026-04-24
reviewed: 2026-04-24
---

# Multi-Repo Discipline

Roles and commit boundaries when multiple repositories share a parent workspace. Pairs with `configure-plugin:config-sync` — that skill propagates mechanical config; this one defines the discipline layer that says who owns what and when a cross-repo commit needs user confirmation.

## When to Use This Skill

| Use this skill when… | Skip when… |
|---------------------|------------|
| The cwd is inside a parent directory that contains other git repos | Working in a single isolated repo |
| A sibling `CLAUDE.md` names the current repo | No cross-repo relationship exists |
| Dispatching agents whose scope could span sibling repos | Single-repo agent fan-out |
| Updating a shared spec that other repos consume | Internal change with no downstream |
| About to edit a sibling's `CLAUDE.md` or `.claude/` config | Edits confined to current repo |

## Detection Heuristic

Run before applying any discipline:

```bash
# Parent directory contains other git repos?
find "$(git rev-parse --show-toplevel)/.." -maxdepth 2 -name .git -type d

# Any sibling CLAUDE.md names this repo by directory name?
grep -l "$(basename "$(git rev-parse --show-toplevel)")" ../*/CLAUDE.md 2>/dev/null
```

If neither detector produces output, **exit silently** — the rule does
not apply to single-repo work. Do not load discipline that does not
apply.

## Workspace Roles

Classify every repository in the workspace into one of three roles.

### Read-only fixtures

Inputs the current project depends on but must never mutate:

- Licensed datasets (e.g. game data archives, ML training sets)
- Shipped third-party binaries used as reference
- Vendored upstream sources consulted for comparison only
- Historical snapshots of a migrated-away-from system

Discipline: treat as immutable. Never commit to a fixture. If an agent
proposes an edit, the edit is a misdirection — redirect to the working
repo.

### Upstream / downstream pair

Two repositories in the same domain where one derives from the other.
Examples:

| Upstream | Downstream |
|----------|-----------|
| Workbench / toolkit | Shipped native port |
| Schema-owning repo | Generated client library |
| Design tokens | Component library |
| Contract repo | Consumer service |

Discipline: the downstream may lag the upstream by design. Changes in
the upstream **do not** automatically propagate — the orchestrator
surfaces the required downstream diff and the human decides when to
land it.

### Authoritative repo

Single source of truth for shared specs, schemas, or interface
contracts. Sibling repos that carry copies of the same material are
explicitly downstream.

Discipline: updates to the authoritative surface are deliberate. The
authoritative repo's commit lands first; downstream updates follow in
their own PRs against the sibling repos.

## Commit Boundaries

### Same-repo commits

Follow the repo's own conventions. No cross-repo confirmation needed.

### Sibling-repo commits during agent dispatch

Cross-repo **edits** during a dispatched agent's run are acceptable when
the scope explicitly names the sibling path. Cross-repo **commits in
sibling repos require user confirmation** before they land.

The pattern:

1. Agent performs the edit in a worktree of the sibling repo.
2. Agent returns the diff in its Return Contract's `Orchestrator action
   needed` field (see `agent-patterns-plugin:parallel-agent-dispatch`
   §Verbatim patches).
3. Orchestrator surfaces the diff to the user and requests confirmation.
4. Human decides whether the downstream commit lands now or later.

Automatic downstream commits are the failure mode this rule prevents —
they drift schemas silently and the next reviewer cannot tell which
commit shipped the decision vs which shipped the propagation.

### Sibling's `CLAUDE.md` / `.claude/` / `docs/`

Never modify a sibling repo's `CLAUDE.md`, `.claude/` config, or `docs/`
as a **side-effect of unrelated work**. These are the sibling repo's
authoritative surfaces; touching them mid-unrelated-task is a side-effect
bug.

When a sibling's Claude configuration genuinely needs an update,
dispatch a targeted agent whose scope names the sibling's config
explicitly. `configure-plugin:config-sync` handles the mechanical
propagation; this rule sets the boundary.

## Authoritative → downstream propagation

When the current repo is authoritative and a change affects downstream
consumers:

1. Land the change in the authoritative repo first (its own PR, its own
   review).
2. In the Return Contract (or PR description), cite the downstream
   repos and the exact change each needs.
3. File follow-up issues or work-orders in the downstream repos — do
   not inline the propagation.
4. If multiple downstream repos consume the same change, each
   propagation is its own PR.

Checklists embedded in the authoritative PR description often get lost
when the PR merges. Prefer follow-up issues per downstream repo, linked
from the authoritative PR description.

## Quick Reference

### Decision table

| Scenario | Action |
|----------|--------|
| Edit in current repo | Normal commit |
| Agent edit in sibling worktree | OK; commit only with user confirmation |
| Sibling's `CLAUDE.md` changed as side-effect | Revert; redirect scope |
| Spec change in authoritative repo | Land here; file follow-up in downstream |
| Fixture repo edit proposed | Refuse; redirect |

### Checklist before cross-repo commit

- [ ] User confirmed the sibling-repo commit?
- [ ] Sibling's conventions followed (commit type, scope, PR title)?
- [ ] Downstream propagation handled in its own PR, not inlined?
- [ ] No unrelated sibling config files touched?

## Related

- `configure-plugin:config-sync` — mechanical propagation that this rule gates
- `agent-patterns-plugin:parallel-agent-dispatch` — Return Contract's "Orchestrator action needed" field carries cross-repo diffs
- `agent-patterns-plugin:agent-coworker-detection` — concurrent-writer detection in shared checkouts
- `.claude/rules/docs-currency.md` — same-commit discipline (applies to each repo individually)

> Evidence: multi-repo sessions where downstream propagation was auto-committed
> produced a week-long schema drift that took two follow-up PRs to reconcile.
> Surfacing the diff and letting the human decide when to land it avoided
> the drift entirely on the next cycle.
