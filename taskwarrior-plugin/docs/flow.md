# taskwarrior-plugin Flow

How the skills fit together as a coordination layer for multi-agent work.

```mermaid
flowchart TD
    ADD[/taskwarrior:task-add/]:::fix
    STATUS[/taskwarrior:task-status/]:::check
    COORD[/taskwarrior:task-coordinate/]:::check
    CLAIM[/taskwarrior:task-claim/]:::fix
    RELEASE[/taskwarrior:task-release/]:::fix
    DONE[/taskwarrior:task-done/]:::fix
    RECONCILE[/taskwarrior:task-reconcile/]:::fix

    GH{{GitHub remote?}}:::prompt
    STORE[(~/.task/)]
    COWORKER[/git:coworker-check/]:::check

    ADD --> GH
    GH -->|yes| GHISSUE[link ghid / create issue]:::fix
    GH -->|no| LOCAL[local-only task]:::fix
    GHISSUE --> STORE
    LOCAL --> STORE

    STORE --> STATUS
    STORE --> COORD
    COORD -->|next N unblocked + unclaimed| CLAIM
    CLAIM -->|+ACTIVE + identity UDAs| STORE
    CLAIM -->|writes session marker| COWORKER

    STORE -->|+ACTIVE claims| COWORKER

    CLAIM -->|pause / handoff| RELEASE
    RELEASE -->|stop, drain pid, drop marker| STORE
    RELEASE --> COORD

    CLAIM -->|work landed| DONE
    STATUS -->|drift / PR ready| DONE
    DONE -->|annotate commit, auto-stop| STORE
    DONE -->|optional| CLOSEGH[gh issue close / gh pr comment]:::fix

    STORE -->|ghid/ghpr tasks| RECONCILE
    GHSTATE{{issue/PR closed?}}:::prompt
    RECONCILE --> GHSTATE
    GHSTATE -->|yes| RCLOSE[bulk import / task done + annotate]:::fix
    GHSTATE -->|no| RKEEP[keep live]:::check
    RCLOSE --> STORE

    COORD -->|+READY wave of unclaimed| DISPATCH[parallel-agent-dispatch / workflow-wave-dispatch]:::router

    classDef router fill:#4a9eff,stroke:#222,color:#fff
    classDef check fill:#8fbc8f,stroke:#222,color:#000
    classDef fix fill:#ffa500,stroke:#222,color:#000
    classDef prompt fill:#dda0dd,stroke:#222,color:#000
```

## Legend

| Class | Fill | Meaning |
|-------|------|---------|
| router | Blue | Orchestrating skill (external — the parallel / wave dispatch that consumes coordinate output) |
| check | Green | Read-only diagnostic / query |
| fix | Orange | Mutates the task store or GitHub |
| prompt | Purple | Decision point |

## Scope map

| Skill | Scope |
|-------|-------|
| `task-add` | Create / link tasks |
| `task-claim` | Claim a pending task (sets `+ACTIVE` + identity UDAs + session marker) |
| `task-release` | Release an active claim without closing (handoff) |
| `task-done` | Close / annotate tasks (auto-stops `+ACTIVE`) |
| `task-status` | Read queue state, including in-flight + stale claims and `+OVERDUE` |
| `task-coordinate` | Query `+READY` + unclaimed candidates for a dispatch wave |
| `task-reconcile` | Close tasks whose linked GitHub issue/PR closed or merged (dry-run by default) |
| `install-native-hooks` | Opt-in installer for taskwarrior native on-add/on-modify hooks (not in the diagram — a one-off setup action, not part of the task lifecycle) |

## Claim lifecycle

The `task-claim` / `task-release` / `task-done` triple is the identity
layer that lets `task-coordinate` and `/git:coworker-check` reason about
in-flight work:

| Transition | Effect on store | Effect on `/git:coworker-check` |
|-----------|------------------|-------------------------------|
| `task-claim` | Task gains `+ACTIVE` + `agent` / `pid` / `host` / `branch` / `worktree` UDAs | Writes `.git/.claude-session-<pid>` and baseline snapshot |
| `task-release` | `+ACTIVE` cleared, `pid` drained, annotation appended; `agent` / `host` / `branch` / `worktree` retained for handoff context (unless `--clear-identity`) | Drops the matching session marker (unless `--no-coworker-marker`) |
| `task-done` | `+ACTIVE` auto-stopped, task closed, commit hash annotated | Drops the matching session marker (unless `--no-coworker-marker`) |
