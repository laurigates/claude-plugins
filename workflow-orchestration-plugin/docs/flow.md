# Workflow Orchestration Plugin Flow

Pipeline: **preflight → checkpoint → refactor**. Validate remote state before committing to work, then execute large refactors through persistent, resumable phases.

```mermaid
flowchart TD
    U[User] -->|/workflow:preflight<br/>issue# or branch| PF["/workflow:preflight<br/>(gate)"]

    PF --> FETCH[Step 1: git fetch --prune<br/>sync remote state]
    FETCH --> EXIST[Step 2: Check existing work<br/>gh pr list / gh issue view]
    EXIST --> EXGATE{existing PR?}
    EXGATE -->|merged| STOP[Stop:<br/>already addressed]
    EXGATE -->|open| ASKPR[AskUserQuestion<br/>continue on branch<br/>or start fresh?]
    EXGATE -->|none| BRANCH[Step 3: Verify branch<br/>ahead/behind, dirty tree]
    ASKPR --> BRANCH
    BRANCH --> CONF[Step 4: Conflict probe<br/>git merge-tree dry-run]
    CONF --> SUM[Step 5: Summary report<br/>+ recommendations]

    SUM --> READY{state clean<br/>& refactor scope?}
    READY -->|small change| DIRECT[Direct edit<br/>out of scope]
    READY -->|10+ files,<br/>multi-phase| CR["/workflow:checkpoint-refactor<br/>(pipeline)"]

    CR --> MODE{mode flag}
    MODE -->|--init| INIT[Step 1: Analyze scope<br/>Write REFACTOR_PLAN.md<br/>record base commit]
    MODE -->|--status| STAT[Step 3: Parse plan<br/>print phase table]
    MODE -->|--continue| RESUME[Step 2: Find next<br/>pending phase]
    MODE -->|--phase=N| PICK[Select phase N]

    INIT --> EXEC[Step 4: Execute phase<br/>read files, apply edits]
    RESUME --> EXEC
    PICK --> EXEC

    EXEC --> BIG{phase has<br/>7+ files?}
    BIG -->|yes| SUB[Step 5: Task sub-agent<br/>delegated edits]
    BIG -->|no| VAL[Validate: tsc / test /<br/>cargo check]
    SUB --> VAL

    VAL --> OK{validation}
    OK -->|pass| DONE_PH[Mark phase done<br/>git commit refactor phase N<br/>update plan]
    OK -->|fail| REV[Mark needs-review<br/>WIP commit with<br/>error details]

    DONE_PH --> MORE{more phases?}
    MORE -->|yes| SUG[Suggest --continue<br/>or auto-proceed]
    MORE -->|no| FIN[Refactor complete]
    REV --> SUG

    classDef router fill:#4a9eff,stroke:#1a6ecc,color:#fff
    classDef check fill:#8fbc8f,stroke:#556b55,color:#000
    classDef fix fill:#ffa500,stroke:#b37400,color:#000
    classDef prompt fill:#dda0dd,stroke:#8b5a8b,color:#000

    class PF,CR router
    class FETCH,EXIST,BRANCH,CONF,SUM,STAT,RESUME,PICK,VAL check
    class INIT,EXEC,SUB,DONE_PH,REV fix
    class ASKPR prompt
```

## Legend

| Node style | Meaning |
|------------|---------|
| Blue | Router / pipeline-stage skill (`/workflow:preflight`, `/workflow:checkpoint-refactor`) |
| Green | Read-only diagnostic / validation step |
| Orange | Mutating step (writes plan file, commits, edits code) |
| Purple | Interactive `AskUserQuestion` prompt |

## Stage to Skill mapping

| Stage | Skill | Produces | Gates |
|-------|-------|----------|-------|
| Preflight | `workflow-preflight/` | Summary report: remote freshness, existing PRs, branch divergence, conflicts | Whether to proceed at all (blocks on merged PRs, dirty tree, detected conflicts) |
| Checkpoint (init) | `workflow-checkpoint-refactor/` `--init` | `REFACTOR_PLAN.md` with phased file groups, acceptance criteria, base commit | Entry point for refactors spanning 10+ files |
| Refactor (execute) | `workflow-checkpoint-refactor/` `--continue` / `--phase=N` | Per-phase commits (`refactor phase N: ...`), plan status updates, optional `needs-review` markers | Survives context limits — each phase reads/writes the plan file so sessions resume cleanly |

## Pipeline rationale

- **Preflight is a gate, not a step** — it produces no code change, only a go/no-go signal. Skipping it is the common cause of wasted refactor effort (duplicate PRs, rebase surprises mid-phase).
- **Checkpoint is the orchestrator** — `--init` defines the contract (`REFACTOR_PLAN.md`), subsequent invocations consume and mutate it.
- **Refactor phases are the atoms** — each phase is an independently committable, validatable unit. Failure marks `needs-review` rather than blocking the pipeline.
