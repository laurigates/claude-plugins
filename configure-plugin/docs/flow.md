# Configure Plugin Flow

The component roster and domain grouping below are generated from the
authoritative manifest
[`skills/configure-all/components.yaml`](../skills/configure-all/components.yaml).
`scripts/check-configure-components.sh` (repo root) fails CI when this file
and the manifest disagree — update the manifest first.

```mermaid
flowchart TD
    U[User] -->|/configure:all<br/>--check-only --fix| R["/configure:all<br/>(router)"]
    U -->|/configure:status| STATUS[configure-status<br/>read-only compliance report]
    U -->|/configure:select| SELECT[configure-select<br/>AskUserQuestion<br/>pick domains]
    U -->|/configure:repo| REPO[configure-repo<br/>end-to-end onboarding driver]

    R --> LIST[list-components.sh<br/>roster from components.yaml]
    SELECT --> LIST
    STATUS --> LIST
    REPO --> R

    LIST --> MODE{--fix or<br/>--check-only?}

    MODE --> D1[CI/CD & Version Control]
    MODE --> D2[Git Metadata]
    MODE --> D3[Containers & Deploy]
    MODE --> D4[Testing]
    MODE --> D5[Code Quality]
    MODE --> D6[Security]
    MODE --> D7[Documentation]
    MODE --> D8[Feature Flags]
    MODE --> D9[Package Management]
    MODE --> D10[Editor & Dev Environment]
    MODE --> D11[Instrumentation & Observability]

    D1 & D2 & D3 & D4 & D5 & D6 & D7 & D8 & D9 & D10 & D11 --> RPT[Consolidated report<br/>per-domain compliance]

    RPT --> FIXQ{--fix?}
    FIXQ -->|no| DONE[Done]
    FIXQ -->|yes| APPLY[Each component skill<br/>writes config files]
    APPLY --> DONE

    SYNC[config-sync<br/>cross-repo propagation] -.->|reference<br/>implementation| MODE

    classDef router fill:#4a9eff,stroke:#1a6ecc,color:#fff
    classDef check fill:#8fbc8f,stroke:#556b55,color:#000
    classDef fix fill:#ffa500,stroke:#b37400,color:#000
    classDef prompt fill:#dda0dd,stroke:#8b5a8b,color:#000

    class R,REPO router
    class STATUS,LIST,D1,D2,D3,D4,D5,D6,D7,D8,D9,D10,D11,SYNC check
    class APPLY fix
    class SELECT prompt
```

## Legend

| Node style | Meaning |
|------------|---------|
| Blue | Router / driver skill (`/configure:all`, `/configure:repo`) |
| Green | Read-only audit / domain group (`--check-only`) |
| Orange | Fix application (`--fix` writes config files) |
| Purple | Interactive `AskUserQuestion` prompt |

## Domain → Skill mapping

Component columns mirror `components.yaml`; reference skills
(`user-invocable: false` knowledge bases) are listed with their domain.

| Domain | Component skills | Reference skills |
|--------|------------------|------------------|
| CI/CD & Version Control | `configure-workflows`, `configure-reusable-workflows`, `configure-release-please`, `configure-pre-commit`, `configure-github-pages`, `configure-argocd-automerge`, `configure-claude-plugins` | `ci-workflows`, `release-please-standards`, `pre-commit-standards` |
| Git Metadata | `configure-gitattributes`, `configure-gitignore`, `configure-worktreeinclude` | |
| Containers & Deploy | `configure-dockerfile`, `configure-container`, `configure-skaffold` | `skaffold-standards` |
| Testing | `configure-tests`, `configure-coverage`, `configure-api-tests`, `configure-integration-tests`, `configure-load-tests`, `configure-memory-profiling`, `configure-ux-testing` | |
| Code Quality | `configure-linting`, `configure-formatting`, `configure-dead-code` | |
| Security | `configure-security` | `claude-security-settings` |
| Documentation | `configure-docs`, `configure-readme`, `configure-surface` | `readme-standards` |
| Feature Flags | `configure-feature-flags` | `openfeature`, `go-feature-flag` |
| Package Management | `configure-package-management`, `configure-mise`, `configure-cache-busting` | |
| Editor & Dev Environment | `configure-editor`, `configure-mcp`, `configure-makefile`, `configure-justfile`, `configure-web-session` | |
| Instrumentation & Observability | `configure-instrumentation`, `configure-sentry` | |
| Orchestration | `configure-all` (router), `configure-select` (interactive), `configure-status` (read-only), `configure-repo` (onboarding driver), `config-sync` (cross-repo) | `multi-repo-discipline` (advisory) |
