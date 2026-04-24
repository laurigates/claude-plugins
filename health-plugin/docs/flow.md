# Health Plugin Flow

```mermaid
flowchart TD
    U[User] -->|/health:check<br/>--scope --fix --dry-run| R["/health:check<br/>(router)"]
    U -->|/health:skill-audit| SA[health-skill-audit<br/>skill-to-skill overlap<br/>split-pressure<br/>consolidation candidates]

    R --> ENV[Step 1: Environment checks]
    ENV --> CP[check-plugins.sh]
    ENV --> CS[check-settings.sh]
    ENV --> CH[check-hooks.sh]
    ENV --> CM[check-mcp.sh]

    R --> SCOPE{scope?}
    SCOPE -->|registry<br/>or all| REG[check-registry.sh<br/>• orphaned projectPath<br/>• stale enabledPlugins<br/>• marketplace drift]
    SCOPE -->|stack<br/>or all| STK[health-audit<br/>enabled plugins vs.<br/>project tech stack]
    SCOPE -->|agentic<br/>or all| AGT[health-agentic-audit<br/>skill optimisation<br/>compliance]

    CP & CS & CH & CM & REG & STK & AGT --> RPT[Step 3: Consolidated report<br/>grouped by scope]

    RPT --> FIX{--fix?}
    FIX -->|no| DONE[Done]
    FIX -->|yes, multi-scope| ASK[AskUserQuestion<br/>pick scopes to fix]
    FIX -->|yes, single scope| DELEGATE
    ASK --> DELEGATE{selected scope}

    DELEGATE -->|registry| FR[fix-registry.sh<br/>backup settings.json<br/>prune orphans<br/>jq del enabledPlugins<br/>RESTART_REQUIRED=true]
    DELEGATE -->|stack| FS[health-audit --fix<br/>disable irrelevant<br/>install missing]
    DELEGATE -->|agentic| FA[health-agentic-audit --fix<br/>add optimisation tables<br/>update reviewed dates]

    FR & FS & FA --> VER[Step 5: Verify<br/>re-run checks]
    VER --> DONE

    classDef router fill:#4a9eff,stroke:#1a6ecc,color:#fff
    classDef check fill:#8fbc8f,stroke:#556b55,color:#000
    classDef fix fill:#ffa500,stroke:#b37400,color:#000
    classDef prompt fill:#dda0dd,stroke:#8b5a8b,color:#000

    class R router
    class CP,CS,CH,CM,REG,STK,AGT,SA check
    class FR,FS,FA fix
    class ASK prompt
```

## Legend

| Node style | Meaning |
|------------|---------|
| Blue | Router skill (`/health:check`) |
| Green | Read-only diagnostic script |
| Orange | Fix script (writes files, backs up first) |
| Purple | Interactive `AskUserQuestion` prompt |

## Scope → Skill mapping

| `--scope` | Check | Fix |
|-----------|-------|-----|
| `registry` | `health-plugins/scripts/check-registry.sh` | `health-plugins/scripts/fix-registry.sh` |
| `stack` | `health-audit/` workflow | `health-audit/` `--fix` flow |
| `agentic` | `health-agentic-audit/` workflow | `health-agentic-audit/` `--fix` flow |
| `all` | All of the above + environment checks | `AskUserQuestion` to pick scopes |

## Sibling skills (not scoped under `/health:check`)

| Skill | Invocation | Purpose |
|-------|------------|---------|
| `health-skill-audit` | `/health:skill-audit [--plugin X] [--strict]` | Skill-to-skill overlap, split-pressure, and consolidation candidates (read-only; report-only; writes `tmp/skill-audit/`). |
