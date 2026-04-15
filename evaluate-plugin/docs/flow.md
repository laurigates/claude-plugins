# Evaluate Plugin Flow

```mermaid
flowchart TD
    U[User] -->|/evaluate:skill<br/>plugin/skill| ES["/evaluate:skill<br/>(single-skill pipeline)"]
    U -->|/evaluate:plugin<br/>plugin-name| EB["/evaluate:plugin<br/>(batch router)"]

    %% Single-skill pipeline
    ES --> RUN[Run eval cases<br/>against SKILL.md<br/>capture transcripts]
    RUN --> GRADE[eval-grader agent<br/>score vs. assertions<br/>cite evidence]
    GRADE --> CMP{--baseline?}
    CMP -->|yes| COMP[eval-comparator agent<br/>blind with-skill vs.<br/>baseline comparison]
    CMP -->|no| BENCH
    COMP --> BENCH[Write benchmark.json<br/>history.json<br/>grading.json]

    BENCH --> IMP[/evaluate:improve<br/>plugin/skill/]
    IMP --> ANA[eval-analyzer agent<br/>diagnose failure patterns<br/>propose SKILL.md edits]
    ANA --> APPLY{--apply?}
    APPLY -->|yes| EDIT[Apply edits to<br/>SKILL.md]
    APPLY -->|no| SUGG[Print suggestions]
    EDIT --> RPT
    SUGG --> RPT

    RPT[/evaluate:report<br/>render benchmark/<br/>history as markdown/]
    RPT --> DONE[Done]

    %% Batch side-branch
    EB --> DISC[Discover skills/*/evals.json]
    DISC --> FAN{{fan out per skill}}
    FAN --> ES
    ES -.batch aggregate.-> AGG[aggregate_benchmark.sh<br/>merge per-skill results]
    AGG --> RPT

    classDef router fill:#4a9eff,stroke:#1a6ecc,color:#fff
    classDef check fill:#8fbc8f,stroke:#556b55,color:#000
    classDef fix fill:#ffa500,stroke:#b37400,color:#000

    class ES,EB,FAN router
    class RUN,GRADE,COMP,BENCH,ANA,RPT,AGG,DISC check
    class EDIT,IMP,APPLY fix
```

## Legend

| Node style | Meaning |
|------------|---------|
| Blue | Router / orchestrator skill (`/evaluate:skill`, `/evaluate:plugin`) |
| Green | Read-only run, grading, analysis, or reporting step |
| Orange | Mutating step (applies edits to `SKILL.md`) |

## Stage → Skill/Agent mapping

| Stage | Skill | Agent |
|-------|-------|-------|
| Evaluate | `/evaluate:skill` (`evaluate-skill/`) | `eval-grader` (grade), `eval-comparator` (blind with-skill vs. baseline) |
| Improve | `/evaluate:improve` (`evaluate-improve/`) | `eval-analyzer` (diagnose + propose edits) |
| Report | `/evaluate:report` (`evaluate-report/`) | — |
| Batch | `/evaluate:plugin` (`evaluate-plugin-batch/`) | fans out to `/evaluate:skill` per skill, then `aggregate_benchmark.sh` merges results into a single report |
