# Agents Plugin Flow

```mermaid
flowchart TD
    U[User / Workflow] -->|attribute data<br/>.claude/attributes.json| R[attribute-router<br/>load → filter → prioritize]

    R --> PRI{severity<br/>weights<br/>crit=4 high=3<br/>med=2 low=1}

    PRI -->|security<br/>critical/high| SEC[security-audit<br/>OWASP, CVEs]
    PRI -->|deps<br/>any| DEP[dependency-audit<br/>CVE scan, licenses]
    PRI -->|quality<br/>high+| REF[refactor<br/>SOLID, restructure]
    PRI -->|quality<br/>medium| REV[review<br/>code review]
    PRI -->|bugs<br/>any| DBG[debug<br/>diagnose, fix]
    PRI -->|tests<br/>any| TST[test<br/>scaffold, run]
    PRI -->|performance<br/>any| PRF[performance<br/>profile, bench]
    PRI -->|docs<br/>any| DOC[docs<br/>fill gaps]
    PRI -->|ci<br/>any| CI[ci<br/>pipelines]
    PRI -->|research<br/>needed| RES[research<br/>docs, APIs]
    PRI -->|bulk edits| SR[search-replace<br/>cross-file rename]

    SEC & DEP & REV & PRF & DOC & RES --> SUM[Routing Summary<br/>addressed vs remaining]
    REF & DBG & TST & CI & SR --> SUM

    classDef router fill:#4a9eff,stroke:#1a6ecc,color:#fff
    classDef check fill:#8fbc8f,stroke:#556b55,color:#000
    classDef fix fill:#ffa500,stroke:#b37400,color:#000
    classDef prompt fill:#dda0dd,stroke:#8b5a8b,color:#000

    class R router
    class SEC,DEP,REV,PRF,DOC,RES check
    class REF,DBG,TST,CI,SR fix
    class PRI prompt
```

## Legend

| Node style | Meaning |
|------------|---------|
| Blue | Router agent (`attribute-router`) |
| Green | Read-only analysis agent (audit, review, profile, research, docs) |
| Orange | Write-capable agent (mutates code, tests, CI config) |
| Purple | Severity / category decision point |

## Category → Agent mapping

| Attribute category | Severity threshold | Agent | Role |
|--------------------|--------------------|-------|------|
| `security` | critical / high | `security-audit` | Analysis |
| `dependencies` | any | `dependency-audit` | Analysis |
| `quality` | high+ | `refactor` | Write |
| `quality` | medium | `review` | Analysis |
| `bugs` | any | `debug` | Write |
| `tests` | any | `test` | Write |
| `performance` | any | `performance` | Analysis |
| `docs` | any | `docs` | Analysis |
| `ci` | any | `ci` | Write |
| `research` | any | `research` | Analysis |
| `bulk-edit` | any | `search-replace` | Write |

Priority = sum of severity weights (critical=4, high=3, medium=2, low=1) across findings routed to each agent; higher totals run first.
