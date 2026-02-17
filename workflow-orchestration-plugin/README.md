# workflow-orchestration-plugin

Workflow orchestration patterns for parallel agents, CI pipelines, preflight checks, and checkpoint-based refactoring. Addresses common friction in multi-branch operations, permission restrictions, and context limits.

## Skills

| Skill | Command | Description |
|-------|---------|-------------|
| workflow-preflight | `/workflow:preflight` | Pre-work validation: check remote state, existing PRs, branch conflicts |
| workflow-parallel-issues | `/workflow:parallel-issues` | Process multiple GitHub issues in parallel with worktree isolation |
| workflow-ci-fix-pipeline | `/workflow:ci-fix` | Autonomous CI failure diagnosis and fix across PRs |
| workflow-checkpoint-refactor | `/workflow:checkpoint-refactor` | Multi-phase refactoring with persistent state across sessions |

## Usage

### Preflight Check

Run before starting any implementation work:

```
/workflow:preflight 42
/workflow:preflight feat/new-feature
```

### Parallel Issue Processing

Process multiple issues simultaneously:

```
/workflow:parallel-issues 12 15 23
/workflow:parallel-issues --all-open
/workflow:parallel-issues --label=bug
```

### CI Fix Pipeline

Fix failing CI checks across PRs:

```
/workflow:ci-fix 45
/workflow:ci-fix --failing
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
2. **Worktree isolation**: Parallel agents always work in isolated worktrees to prevent branch conflicts
3. **Preflight validation**: Check remote state before starting work to avoid redundant effort
4. **Persistent state**: Large refactors write progress to plan files so work survives context limits and session boundaries
5. **Error recovery**: Every workflow includes recovery patterns for common failure modes
6. **Body-file for PRs**: PR bodies are written to temp files to avoid heredoc escaping issues

## Related Plugins

- [git-plugin](../git-plugin/) - Core git workflows, worktree patterns, commit/PR skills
- [github-actions-plugin](../github-actions-plugin/) - GitHub Actions CI/CD workflow analysis
- [testing-plugin](../testing-plugin/) - Test execution and TDD workflows
- [code-quality-plugin](../code-quality-plugin/) - Code review and refactoring patterns
