# workflow-orchestration-plugin

Workflow orchestration patterns for preflight checks, checkpoint-based refactoring, sequential-wave agent dispatch, and Workflow run recovery and budgeting. Addresses common friction in multi-branch operations, permission restrictions, and context limits.

## Flow

See [`docs/flow.md`](docs/flow.md) for a diagram of the preflight → checkpoint → refactor pipeline.

## Skills

| Skill | Command | Description |
|-------|---------|-------------|
| workflow-preflight | `/workflow:preflight` | Pre-work validation: check remote state, existing PRs, branch conflicts; `--recon` adds gh auth, merge gates and required secrets before an agent wave |
| workflow-checkpoint-refactor | `/workflow:checkpoint-refactor` | Multi-phase refactoring with persistent state across sessions |
| workflow-interrupted-run-recovery | — | Recover a `Workflow` run killed mid-flight: salvage killed agents' worktrees, resume without duplicating PRs the completed agents opened |
| workflow-scale-budget | — | Size a `Workflow` script's agent count before running it: cost per agent, per-item multipliers, theme grouping, re-drive design. `scripts/workflow-run-tally.sh` tallies a finished run's realised agents and tokens from its transcripts, and a session's total across its runs |
| workflow-implement-verify | — | `Workflow` templates: implement 2–5 units in worktrees with a fresh verifier each and at most one repair round, then open PRs sequentially; or close verifier findings on existing branches (`repair-round`) |
| workflow-bake-off | — | `Workflow` template: 2–5 independent attempts, 1–3 lens judges, a winner computed in JS (Borda or a metric rule, deterministic tiebreaks), then an optional refine that grafts runner-up ideas; plus a protocol for measured A/B arms |
| workflow-verify-before-filing | `/workflow:verify-before-filing` | Verify accumulated bug claims at upstream HEAD and dedup against trackers before filing issues |
| workflow-wave-dispatch | — | Sequential-wave dispatch for multi-agent work with cross-task dependencies, gating each wave on verification |

Parallel issue processing and the CI-fix pipeline moved out of this plugin:

- **Parallel issues** (formerly `/workflow:parallel-issues`) → `/git:issue --parallel` (git-plugin): issue to PR end-to-end, several issues at once.
- **CI fix** (formerly `/workflow:ci-fix`) → `/git:fix-pr` (git-plugin) to fix a PR's failing checks; `/github:workflow-auto-fix` (github-actions-plugin) to set up a CI workflow that fixes failures automatically.

## Usage

### Preflight Check

Run before starting any implementation work:

```
/workflow:preflight 42
/workflow:preflight feat/new-feature
```

### Checkpoint Refactoring

Large refactors that survive context limits:

```
/workflow:checkpoint-refactor --init
/workflow:checkpoint-refactor --continue
/workflow:checkpoint-refactor --status
/workflow:checkpoint-refactor --phase=3
```

## Design Principles

These skills were designed based on analysis of common workflow friction:

1. **Push delegation**: Sub-agents never push directly; the orchestrator handles all push/PR operations sequentially to avoid TLS errors and sandbox blocks
2. **Worktree isolation**: Parallel agents work in isolated worktrees to prevent branch conflicts
3. **Preflight validation**: Check remote state before starting work to avoid redundant effort
4. **Persistent state**: Large refactors write progress to plan files so work survives context limits and session boundaries
5. **Error recovery**: Interrupted `Workflow` runs and failed phases have documented recovery patterns

## Related Plugins

- [git-plugin](../git-plugin/) - Core git workflows, worktree patterns, commit/PR skills
- [github-actions-plugin](../github-actions-plugin/) - GitHub Actions CI/CD workflow analysis
- [testing-plugin](../testing-plugin/) - Test execution and TDD workflows
- [code-quality-plugin](../code-quality-plugin/) - Code review and refactoring patterns
