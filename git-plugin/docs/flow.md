# Git Plugin Flow

```mermaid
flowchart TD
    U[User] -->|/git:commit<br/>--push --pr| START[Start]

    START --> DETECT[git-repo-detection<br/>git-cli-agentic<br/>gh-cli-agentic]
    DETECT --> BRANCH[Stage 1: Branch<br/>git-branch-naming<br/>git-branch-pr-workflow]
    BRANCH --> SEC[Stage 2: Security checks<br/>git-security-checks<br/>pre-commit / gitleaks]
    SEC --> COMMIT[Stage 3: Commit<br/>git-commit<br/>git-commit-workflow<br/>git-commit-trailers]
    COMMIT --> PUSH[Stage 4: Push<br/>git-push]
    PUSH --> PR[Stage 5: Pull Request<br/>git-pr / git-api-pr<br/>github-pr-title<br/>github-labels]
    PR --> MON[Stage 6: Monitor<br/>gh-workflow-monitoring<br/>git-fix-pr<br/>git-pr-feedback]
    MON --> CONF{conflicts?}
    CONF -->|yes| RES[git-conflicts<br/>git-resolve-conflicts]
    CONF -->|no| DONE[Merged]
    RES --> PUSH

    %% Issues side branch
    COMMIT -.-> ISS[Issues side branch<br/>git-issue<br/>git-issue-manage<br/>git-issue-hierarchy<br/>github-issue-writing<br/>github-issue-autodetect]
    ISS -.-> BRANCH

    %% Release-please side branch
    PR -.-> RP[release-please side branch<br/>release-please-configuration<br/>release-please-protection<br/>release-please-pr-workflow]
    RP -.-> DONE

    %% Rebase / fork side branch
    BRANCH -.-> RBF[Rebase & fork patterns<br/>git-rebase-patterns<br/>git-fork-workflow<br/>git-upstream-pr<br/>git-maintain<br/>git-derive-docs]
    RBF -.-> PUSH

    classDef router fill:#4a9eff,stroke:#1a6ecc,color:#fff
    classDef check fill:#8fbc8f,stroke:#556b55,color:#000
    classDef fix fill:#ffa500,stroke:#b37400,color:#000
    classDef prompt fill:#dda0dd,stroke:#8b5a8b,color:#000

    class DETECT,SEC,MON check
    class BRANCH,COMMIT,PUSH,PR,RES,RP,ISS,RBF fix
    class CONF prompt
```

## Legend

| Node style | Meaning |
|------------|---------|
| Green | Read-only diagnostic / detection (repo detection, security scan, workflow monitoring) |
| Orange | Writes state (branch create, commit, push, PR, release-please, issue ops) |
| Purple | Decision / interactive prompt |
| Dashed edge | Side branch — invoked situationally, not every run |

## Stage → Skill mapping

| Stage | Skills |
|-------|--------|
| Detect | `git-repo-detection`, `git-cli-agentic`, `gh-cli-agentic` |
| Branch | `git-branch-naming`, `git-branch-pr-workflow` |
| Security | `git-security-checks` |
| Commit | `git-commit`, `git-commit-workflow`, `git-commit-trailers` |
| Push | `git-push` |
| Pull Request | `git-pr`, `git-api-pr`, `github-pr-title`, `github-labels` |
| Monitor | `gh-workflow-monitoring`, `git-fix-pr`, `git-pr-feedback` |
| Conflicts | `git-conflicts`, `git-resolve-conflicts` |
| Issues (side) | `git-issue`, `git-issue-manage`, `git-issue-hierarchy`, `github-issue-writing`, `github-issue-autodetect` |
| Release-please (side) | `release-please-configuration`, `release-please-protection`, `release-please-pr-workflow` |
| Rebase / fork (side) | `git-rebase-patterns`, `git-fork-workflow`, `git-upstream-pr`, `git-maintain`, `git-derive-docs` |
