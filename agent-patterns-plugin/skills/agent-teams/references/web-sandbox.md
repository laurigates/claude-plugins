# Agent Teams — Sandbox Considerations

Moved verbatim from [SKILL.md](../SKILL.md). Open when the team runs in a web
session (`CLAUDE_CODE_REMOTE=true`).

## Sandbox Considerations

In web sessions (`CLAUDE_CODE_REMOTE=true`):

- Sub-agents (teammates) may encounter TLS errors on `git push` — delegate all push/PR operations to the lead.
- Each teammate runs in its own process context.
- Worktree isolation is recommended for independent filesystem changes.
