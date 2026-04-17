# ADR-0004: Safety hooks block writes to vault-internal paths

- Status: Accepted
- Date: 2026-04-17

## Context

An LLM-backed subagent could decide that "fixing the vault" includes:

- Editing `.obsidian/workspace.json` (Obsidian state)
- Editing `.claude/commands/*.md` (user's Claude Code config)
- Deleting files under `Files/` (attachments)
- Running `git push` (no remote, but the command would still try)
- Running `rm -rf /vault/Zettelkasten` (catastrophic)

None of these are what we want. The safety hook is the last line of defense before a destructive operation reaches the filesystem.

## Decision

`hooks/safety.py` implements `validate_tool_use(tool_name, tool_input)` returning a `SafetyDecision`. Registered as a SDK `PreToolUse` hook on every agent run.

Blocked path segments (Write / Edit / NotebookEdit):

- `.obsidian/`, `.claude/`, `.git/`, `node_modules/`, `_site/`, `__pycache__/`, `Files/`

Blocked Bash patterns:

- `git push` (no remote — always a mistake)
- `git reset --hard`, `git checkout -- .`, `git clean -f*`
- `rm -rf` unless the target is under `tmp/`, `__pycache__/`, or `Inbox/ChatExport_*/processed/`

A block returns `EXIT_HOOK_BLOCKED` (exit code 4) from `non_interactive.py`.

## Consequences

- Safety is enforced by a pure-Python function that's unit-testable without the SDK (see `tests/test_safety.py` — 13 unit tests).
- The rules are transparent and live alongside the code they protect.
- False positives are possible (a legitimate `rm -rf` outside allowlisted dirs would be blocked). The user can bypass by running the command themselves.

## Related

- git-repo-agent ADR-004 uses the same pattern for code repositories.
