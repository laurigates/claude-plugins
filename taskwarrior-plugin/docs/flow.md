# taskwarrior-plugin Flow

How the skills fit together as a coordination layer for multi-agent work.

```mermaid
flowchart TD
    ADD[/taskwarrior:task-add/]:::fix
    STATUS[/taskwarrior:task-status/]:::check
    COORD[/taskwarrior:task-coordinate/]:::check
    DONE[/taskwarrior:task-done/]:::fix

    GH{{GitHub remote?}}:::prompt
    STORE[(~/.task/)]

    ADD --> GH
    GH -->|yes| GHISSUE[link ghid / create issue]:::fix
    GH -->|no| LOCAL[local-only task]:::fix
    GHISSUE --> STORE
    LOCAL --> STORE

    STORE --> STATUS
    STORE --> COORD
    COORD -->|next N unblocked| DISPATCH[parallel-agent-dispatch / workflow-wave-dispatch]:::router

    STATUS -->|drift detected| DONE
    DONE -->|annotate commit| STORE
    DONE -->|optional| CLOSEGH[gh issue close / gh pr comment]:::fix

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
| `task-done` | Close / annotate tasks |
| `task-status` | Read queue state |
| `task-coordinate` | Query candidate agents for a dispatch wave |
