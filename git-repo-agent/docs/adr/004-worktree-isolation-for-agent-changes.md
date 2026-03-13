# ADR-004: Worktree Isolation for Agent Changes

## Status

Accepted

## Context

When git-repo-agent makes changes to a target repository (onboard, maintain --fix, maintain interactive), those changes are made directly in the working copy. This creates conflicts when:

- Other agents are working in the same repository simultaneously
- The user has uncommitted work in progress
- Multiple maintenance runs overlap

The Claude Code CLI supports `--worktree` for agent isolation, but the Claude Agent SDK's `ClaudeAgentOptions` does not expose this parameter.

## Decision

Manage git worktrees in Python before launching the agent:

1. **Before agent runs**: Create a worktree at `<repo>/.worktrees/<branch-name>` with a dedicated branch
2. **Set `cwd`**: Point the agent's working directory to the worktree
3. **Agent commits**: Agent commits directly to the worktree branch (no branch creation)
4. **After agent finishes**: Python prompts user to create a PR via `gh pr create`
5. **No-change cleanup**: If agent made no commits, worktree is cleaned up automatically

### Worktree location

Worktrees are created under `<repo>/.worktrees/` with the branch name as directory name. This keeps them co-located with the target repo for easy discovery.

### Branch naming

| Workflow | Branch Pattern |
|----------|----------------|
| Onboard | `setup/onboard` (customizable via `--branch`) |
| Maintain | `maintain/YYYY-MM-DD` |

### Report-only mode

Report-only mode does not create a worktree (no changes are made). Instead, the orchestrator collects the agent's text output and offers to create GitHub issues for findings marked as "report-only".

## Consequences

- Agent changes are isolated from the main working copy
- Multiple agents can work on the same repo without conflicts
- Users are prompted before any remote-visible actions (push, PR creation)
- The `.worktrees/` directory should be in `.gitignore` of target repos
- Worktree creation adds ~1s of startup overhead

## Alternatives Considered

1. **SDK worktree support**: `ClaudeAgentOptions` does not have a `worktree` parameter
2. **Manual branch in agent**: Agent creates branches itself — harder to control, can conflict with existing work
3. **Stash-based isolation**: `git stash` before/after — fragile and doesn't support parallel agents
