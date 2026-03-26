---
created: 2026-03-26
modified: 2026-03-26
reviewed: 2026-03-26
paths:
  - "**/skills/**"
  - "**/SKILL.md"
  - "**/.claude/settings.json"
---

# Auto Mode

Claude Code auto mode delegates permission decisions to AI classifiers instead of requiring manual approval. It provides a middle ground between manual review and `--dangerouslySkipPermissions`.

## Permission Tiers

| Tier | What | Behavior |
|------|------|----------|
| **Tier 1 — Safe Allowlist** | Read, Grep, Glob, code navigation | Bypass classification entirely |
| **Tier 2 — In-Project** | Edit, Write within the project directory | Skip classification (reviewable via VCS) |
| **Tier 3 — Classifier** | Shell commands, web requests, credential access, subagent spawning, out-of-project filesystem | AI-classified per-request |

## Built-in Block Rules

Auto mode includes 20+ default block categories:

- Irreversible data loss (force-pushes, mass deletions)
- Security degradation (disabling logs, installing persistence)
- Cross-boundary violations (running external code, credential harvesting)
- Shared infrastructure risks (production deploys, direct main pushes)

Inspect defaults with `claude auto-mode defaults`. Customize with allow exceptions for project-specific needs.

## Interaction with `allowed-tools`

`allowed-tools` in skill frontmatter defines the **subagent permission boundary**. When a skill runs as a subagent (via `agent:` field or `Task` tool), only the tools listed in `allowed-tools` are available.

| Context | `allowed-tools` effect |
|---------|----------------------|
| Main session (auto mode) | Redundant — auto mode classifies tools directly |
| Main session (manual mode) | Active — defines what the skill can use without prompting |
| Subagent execution | Active — defines the subagent's tool boundary |

**Keep `allowed-tools` in skill frontmatter** for subagent correctness and intent documentation, even when auto mode handles the main session.

## Interaction with `.claude/settings.json`

With auto mode enabled, granular `Bash(command *)` patterns in `settings.json` `allow` lists are unnecessary — the Tier 3 classifier handles them.

**Keep in `settings.json`:**
- MCP tool permissions (`mcp__*`) — not covered by auto mode tiers
- Domain-scoped `WebFetch` permissions — explicit trust signals
- Any tool the classifier consistently gets wrong for your project

**Remove from `settings.json`:**
- `Bash(git *)`, `Bash(gh *)`, `Bash(npm *)` patterns — handled by Tier 3
- `Bash(ls *)`, `Bash(rg *)`, `Bash(fd *)` — handled by Tier 1/3

## Interaction with PermissionRequest Hooks

Auto mode's Tier 3 classifier largely replaces `PermissionRequest` hooks for approve/deny logic. The classifier runs before hooks in auto mode.

| Use auto mode when... | Use PermissionRequest hooks when... |
|---|---|
| AI-powered classification is sufficient | Deterministic, auditable rules are required |
| Built-in block rules cover your needs | Enterprise compliance needs explicit deny lists |
| You want zero-config permission handling | Custom project-specific policies beyond defaults |
| You accept ~0.4% false positive rate | You need 0% false positives on specific commands |

Both can coexist — hooks provide a secondary layer when auto mode is enabled.

## Migration Checklist

When adopting auto mode for a project:

- [ ] Remove granular `Bash(*)` patterns from `.claude/settings.json` `allow` list
- [ ] Keep MCP tool and `WebFetch` permissions in `settings.json`
- [ ] Keep `allowed-tools` in skill frontmatter (subagent boundary)
- [ ] Review `PermissionRequest` hooks — remove if auto mode covers the use case
- [ ] Run `claude auto-mode defaults` to review and customize block/allow rules
- [ ] Test that critical workflows (commit, push, test, lint) work without interruption

## Guidance for New Skills

With auto mode as the expected permission model:

- `Bash` (broad) is acceptable in `allowed-tools` — auto mode classifies safety per-request
- Granular patterns like `Bash(git status *)` still work but add verbosity without benefit in auto mode
- Continue listing non-Bash tools (`Read, Grep, Glob, Edit, TodoWrite`) for subagent completeness
- Use `:ask` suffix for genuinely dangerous operations that should always prompt, regardless of mode

## Deny-and-Continue Behavior

When auto mode's classifier blocks an action:
1. The agent receives feedback about why the action was denied
2. The agent attempts a safer alternative automatically
3. After 3 consecutive denials or 20 total in a session, the system escalates to the user

This means skills do not need to handle permission denials explicitly — the agent adapts.

## Related Rules

- `.claude/rules/agentic-permissions.md` — granular permission syntax and standard sets (manual mode)
- `.claude/rules/skill-development.md` — skill creation patterns and `allowed-tools` usage
- `.claude/rules/hooks-reference.md` — hook events including `PermissionRequest`
