# Codebase Attributes Plugin Flow

```mermaid
flowchart TD
    SRC[Source code<br/>README, tests, CI,<br/>lockfiles, SCA config]
    SRC -->|scan file:line signals| COL["/attributes:collect<br/>(collector)"]

    COL -->|emit structured JSON| STORE[(Attribute data store<br/>id • category • severity<br/>description • source • actions)]

    STORE --> ROUTE["/attributes:route<br/>(router)"]
    ROUTE --> SEV{severity<br/>+ category}

    SEV -->|critical / high<br/>category=security| SEC[security-audit agent]
    SEV -->|high / medium<br/>category=tests| TST[test agent]
    SEV -->|medium / low<br/>category=docs| DOC[documentation agent]
    SEV -->|medium<br/>category=quality| QUAL[code-review agent]
    SEV -->|info / low<br/>category=ci| CI[cicd agent]

    STORE --> DASH["/attributes:dashboard<br/>(visualizer)<br/>render severity counts,<br/>top findings, remediation hints"]

    SEC & TST & DOC & QUAL & CI -->|remediation actions| OUT[Fixes / PRs / issues]
    DASH --> TERM[Terminal-style<br/>health overview]

    classDef router fill:#4a9eff,stroke:#1a6ecc,color:#fff
    classDef check fill:#8fbc8f,stroke:#556b55,color:#000
    classDef fix fill:#ffa500,stroke:#b37400,color:#000
    classDef store fill:#e8e8e8,stroke:#666,color:#000
    classDef prompt fill:#dda0dd,stroke:#8b5a8b,color:#000

    class COL,DASH check
    class ROUTE router
    class STORE store
    class SEC,TST,DOC,QUAL,CI fix
    class SEV prompt
```

## Legend

| Node style | Meaning |
|------------|---------|
| Blue | Router skill (`/attributes:route`) |
| Green | Read-only collector / visualizer skill |
| Orange | Downstream agent that may mutate code |
| Grey | Shared attribute data store (JSON) |
| Purple | Routing decision (severity + category) |

## Stage → Skill mapping

| Stage | Skill / Agent | Input | Output |
|-------|---------------|-------|--------|
| Collect | `/attributes:collect` | Source tree (README, tests, CI, lockfiles, linter config) | Attribute JSON: `{id, category, severity, description, source, actions}` keyed by `file:line` |
| Store | (in-memory / file artefact) | Collector output | Normalised attribute list consumed by router + dashboard |
| Route | `/attributes:route` | Attribute JSON | Agent delegations keyed by `(category, severity)` |
| Act | `security-audit`, `test`, `documentation`, `code-review`, `cicd` agents | Routed attributes + remediation `actions` | Fixes, PRs, issues |
| Visualize | `/attributes:dashboard` | Attribute JSON | Terminal health dashboard grouped by category and severity |

## Data contract

Attributes flowing between stages carry:

- **Location** — `file:line` (plus optional column) so downstream agents can jump straight to the offending site
- **Category** — `docs` · `tests` · `security` · `quality` · `ci`
- **Severity** — `critical` · `high` · `medium` · `low` · `info` (drives routing priority and dashboard colouring)
- **Actions** — array of `{agent, command, rationale}` entries; the router uses `agent` as its dispatch key

Integration: the `git-repo-agent` Python tool emits the same JSON schema, so it can substitute for `/attributes:collect` without changing downstream stages.
