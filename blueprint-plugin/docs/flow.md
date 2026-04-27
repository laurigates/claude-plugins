# Blueprint Plugin Flow

```mermaid
flowchart TD
    U[User] -->|/blueprint:execute| EX["/blueprint:execute<br/>(router: detects repo state)"]

    EX --> INIT[blueprint-init<br/>scaffold docs/blueprint/<br/>prds/ adrs/ prps/]

    subgraph DERIVE["Derive from existing code (optional side-path)"]
        direction TB
        DP[blueprint-derive-prd]
        DA[blueprint-derive-adr]
        DPL[blueprint-derive-plans]
        DR[blueprint-derive-rules]
        DT[blueprint-derive-tests]
    end

    INIT -.->|brownfield| DERIVE

    INIT --> PRD[Stage 1: PRD<br/>docs/prds/PRD-NNN]
    DERIVE --> PRD

    PRD --> ADR[Stage 2: ADR<br/>docs/adrs/ADR-NNNN<br/>blueprint-adr-validate<br/>adr-relationships]

    ADR --> PRP[Stage 3: PRP<br/>blueprint-prp-create<br/>+ confidence-scoring<br/>+ blueprint-curate-docs]

    PRP --> WO[blueprint-work-order<br/>isolated task package]

    WO --> RUN[Stage 4: Execute<br/>blueprint-prp-execute<br/>TDD RED->GREEN->REFACTOR]

    RUN --> TRACK[feature-tracking<br/>blueprint-feature-tracker-sync<br/>blueprint-feature-tracker-status]

    subgraph AUDIT["Story-audit loop (closes intent <-> reality gap)"]
        direction TB
        SA[blueprint-story-audit<br/>capability map x stories x tests<br/>writes docs/blueprint/audits/]
        SR[blueprint-story-reconcile<br/>marks PRDs with drift status<br/>+ Known Drift section]
    end

    TRACK -.->|periodic| SA
    SA -.->|drift report| SR
    SR -.->|updated PRD| PRD
    SA -.->|Tier-1 gap rows| WO

    subgraph META["Cross-cutting management"]
        direction TB
        SID[blueprint-sync-ids<br/>assign IDs,<br/>traceability registry]
        SYNC[blueprint-sync<br/>blueprint-claude-md<br/>blueprint-generate-rules]
        PROM[blueprint-promote<br/>child -> root rollup]
        LIST[blueprint-docs-list<br/>blueprint-adr-list<br/>blueprint-status]
        UPG[blueprint-upgrade<br/>blueprint-migration<br/>blueprint-workspace-scan]
    end

    PRD -.-> SID
    ADR -.-> SID
    PRP -.-> SID
    SID -.-> SYNC
    TRACK -.-> PROM

    EX -.->|idempotent<br/>check state| LIST
    EX -.->|format drift| UPG

    subgraph VALID["Validation hooks (PreToolUse)"]
        direction TB
        VA[validate-adr-frontmatter.sh]
        VP[validate-prp-frontmatter.sh]
        CR[check-prp-readiness.sh<br/>confidence >= 7/10]
    end

    ADR -.->|on Write/Edit| VA
    PRP -.->|on Write/Edit| VP
    RUN -.->|on Skill invoke| CR

    classDef router fill:#4a9eff,stroke:#1a6ecc,color:#fff
    classDef check fill:#8fbc8f,stroke:#556b55,color:#000
    classDef fix fill:#ffa500,stroke:#b37400,color:#000
    classDef prompt fill:#dda0dd,stroke:#8b5a8b,color:#000

    class EX router
    class DP,DA,DPL,DR,DT,LIST,VA,VP,CR,SA check
    class INIT,PRD,ADR,PRP,WO,RUN,TRACK,SID,SYNC,PROM,UPG,SR fix
```

## Legend

| Node style | Meaning |
|------------|---------|
| Blue | Router skill (`/blueprint:execute`) |
| Green | Read-only analysis / listing / validation |
| Orange | Skills that create or mutate blueprint artefacts |
| Purple | Interactive `AskUserQuestion` prompt (none currently) |

Solid arrows are the main spine (PRD -> ADR -> PRP -> execute).
Dotted arrows are optional side-paths and cross-cutting concerns.

## Stage -> Skill mapping

| Stage | Skills |
|-------|--------|
| Bootstrap | `blueprint-init`, `blueprint-execute` (router) |
| Derive (brownfield) | `blueprint-derive-prd`, `blueprint-derive-adr`, `blueprint-derive-plans`, `blueprint-derive-rules`, `blueprint-derive-tests` |
| PRD | `blueprint-development`, `document-detection`, `document-linking` |
| ADR | `blueprint-adr-validate`, `blueprint-adr-list`, `adr-relationships` |
| PRP | `blueprint-prp-create`, `blueprint-curate-docs`, `confidence-scoring` |
| Execute | `blueprint-work-order`, `blueprint-prp-execute` |
| Feature tracking | `feature-tracking`, `blueprint-feature-tracker-sync`, `blueprint-feature-tracker-status` |
| Cross-cutting: IDs | `blueprint-sync-ids` |
| Cross-cutting: sync | `blueprint-sync`, `blueprint-claude-md`, `blueprint-generate-rules`, `blueprint-rules` |
| Cross-cutting: promote | `blueprint-promote` (child -> root monorepo rollup) |
| Cross-cutting: listing/status | `blueprint-docs-list`, `blueprint-adr-list`, `blueprint-status` |
| Cross-cutting: migration | `blueprint-upgrade`, `blueprint-migration`, `blueprint-workspace-scan` |
| Cross-cutting: docs hygiene | `blueprint-docs-currency` (advisory: same-commit code+docs landing) |
| Validation | `validate-prp-frontmatter.sh`, `validate-adr-frontmatter.sh`, `check-prp-readiness.sh` |
| Story-audit loop | `blueprint-story-audit` (read-only audit), `blueprint-story-reconcile` (PRD-only mutate) |
