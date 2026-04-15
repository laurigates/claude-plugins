# Configure Plugin Flow

```mermaid
flowchart TD
    U[User] -->|/configure:all<br/>--check-only --fix| R["/configure:all<br/>(router)"]
    U -->|/configure:status| STATUS[configure-status<br/>read-only compliance report]
    U -->|/configure:select| SELECT[configure-select<br/>AskUserQuestion<br/>pick domains]

    R --> MODE{--fix or<br/>--check-only?}
    SELECT --> MODE

    MODE --> CI[CI / Workflows<br/>• configure-workflows<br/>• configure-reusable-workflows<br/>• configure-release-please<br/>• configure-argocd-automerge<br/>• configure-github-pages<br/>• configure-claude-plugins]

    MODE --> CONT[Containers & Deploy<br/>• configure-dockerfile<br/>• configure-container<br/>• configure-skaffold]

    MODE --> TEST[Testing<br/>• configure-tests<br/>• configure-coverage<br/>• configure-api-tests<br/>• configure-integration-tests<br/>• configure-load-tests<br/>• configure-memory-profiling<br/>• configure-ux-testing]

    MODE --> QUAL[Lint / Format / Dead code<br/>• configure-linting<br/>• configure-formatting<br/>• configure-dead-code<br/>• configure-pre-commit]

    MODE --> SEC[Security<br/>• configure-security<br/>• claude-security-settings]

    MODE --> DOCS[Docs<br/>• configure-docs<br/>• configure-readme]

    MODE --> FF[Feature flags<br/>• configure-feature-flags<br/>• openfeature<br/>• go-feature-flag]

    MODE --> PKG[Package management<br/>• configure-package-management<br/>• configure-cache-busting]

    MODE --> EDIT[Editor / Dev env<br/>• configure-editor<br/>• configure-mcp<br/>• configure-makefile<br/>• configure-justfile<br/>• configure-web-session<br/>• configure-sentry]

    CI & CONT & TEST & QUAL & SEC & DOCS & FF & PKG & EDIT --> RPT[Consolidated report<br/>per-domain compliance]

    RPT --> FIXQ{--fix?}
    FIXQ -->|no| DONE[Done]
    FIXQ -->|yes| APPLY[Each domain skill<br/>writes config files]
    APPLY --> DONE

    SYNC[config-sync<br/>cross-repo propagation] -.->|reference<br/>implementation| MODE

    classDef router fill:#4a9eff,stroke:#1a6ecc,color:#fff
    classDef check fill:#8fbc8f,stroke:#556b55,color:#000
    classDef fix fill:#ffa500,stroke:#b37400,color:#000
    classDef prompt fill:#dda0dd,stroke:#8b5a8b,color:#000

    class R router
    class STATUS,CI,CONT,TEST,QUAL,SEC,DOCS,FF,PKG,EDIT,SYNC check
    class APPLY fix
    class SELECT prompt
```

## Legend

| Node style | Meaning |
|------------|---------|
| Blue | Router skill (`/configure:all`) |
| Green | Read-only audit / domain group (`--check-only`) |
| Orange | Fix application (`--fix` writes config files) |
| Purple | Interactive `AskUserQuestion` prompt |

## Domain → Skill mapping

| Domain | Skills |
|--------|--------|
| CI / Workflows | `configure-workflows`, `configure-reusable-workflows`, `configure-release-please`, `configure-argocd-automerge`, `configure-github-pages`, `configure-claude-plugins`, `ci-workflows`, `release-please-standards` |
| Containers & Deploy | `configure-dockerfile`, `configure-container`, `configure-skaffold`, `skaffold-standards` |
| Testing | `configure-tests`, `configure-coverage`, `configure-api-tests`, `configure-integration-tests`, `configure-load-tests`, `configure-memory-profiling`, `configure-ux-testing` |
| Lint / Format / Dead code | `configure-linting`, `configure-formatting`, `configure-dead-code`, `configure-pre-commit`, `pre-commit-standards` |
| Security | `configure-security`, `claude-security-settings` |
| Docs | `configure-docs`, `configure-readme`, `readme-standards` |
| Feature flags | `configure-feature-flags`, `openfeature`, `go-feature-flag` |
| Package management | `configure-package-management`, `configure-cache-busting` |
| Editor / Dev env | `configure-editor`, `configure-mcp`, `configure-makefile`, `configure-justfile`, `configure-web-session`, `configure-sentry` |
| Orchestration | `configure-all` (router), `configure-select` (interactive), `configure-status` (read-only), `config-sync` (cross-repo) |
