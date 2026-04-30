---
created: 2026-04-29
modified: 2026-04-29
reviewed: 2026-04-29
paths:
  - "**/skills/**"
  - "**/SKILL.md"
  - "**/.claude/settings.json"
---

# Auto Mode

Auto mode lets Claude Code execute without permission prompts. A separate classifier model reviews each action before it runs, blocking anything that escalates beyond the user's request, targets unrecognized infrastructure, or appears driven by hostile content.

Authoritative reference: [Choose a permission mode](https://code.claude.com/docs/en/permission-modes#eliminate-prompts-with-auto-mode). This rule summarises the parts that affect how plugin skills, settings, and hooks should be authored.

## Availability

Auto mode is conditional on every row of this table. If any row is unmet, auto mode is unavailable on the user's machine.

| Requirement | Value |
|-------------|-------|
| Claude Code version | `v2.1.83` or later |
| Plan | Max, Team, Enterprise, or API (not Pro) |
| Model | Sonnet 4.6, Opus 4.6, Opus 4.7 (Team / Enterprise / API); Opus 4.7 only on Max |
| Provider | Anthropic API (not Bedrock, Vertex, or Foundry) |
| Admin | On Team / Enterprise, an admin must enable it in Claude Code admin settings |

Admins can lock it off project-wide by setting `permissions.disableAutoMode: "disable"` in [managed settings](https://code.claude.com/docs/en/permissions#managed-settings).

A "Auto mode unavailable" message means a requirement above is unmet — it is not a transient outage. A "cannot determine the safety of an action" message is a separate transient classifier outage.

## How the Classifier Decides

Each tool call walks a fixed decision order. The first matching step wins:

1. Actions matching the user's `allow` or `deny` rules resolve immediately
2. Read-only actions and file edits inside the working directory are auto-approved (except writes to [protected paths](https://code.claude.com/docs/en/permission-modes#protected-paths))
3. Everything else goes to the classifier
4. If the classifier blocks, Claude receives the reason and tries an alternative

The classifier sees user messages, tool calls, and `CLAUDE.md` content. Tool results are stripped, so hostile content in a fetched page or read file cannot manipulate the classifier directly. A separate server-side probe scans incoming tool results for suspicious content before Claude reads them.

## What the Classifier Blocks by Default

| Blocked by default | Allowed by default |
|--------------------|---------------------|
| Downloading and executing code (`curl \| bash`) | Local file operations in the working directory |
| Sending sensitive data to external endpoints | Installing dependencies declared in lockfiles or manifests |
| Production deploys and migrations | Reading `.env` and sending credentials to the matching API |
| Mass deletion on cloud storage | Read-only HTTP requests |
| Granting IAM or repo permissions | Pushing to the branch the session started on or one Claude created |
| Modifying shared infrastructure | |
| Irreversibly destroying files that existed before the session | |
| Force push, or pushing directly to `main` | |

Sandbox network access requests are routed through the classifier rather than allowed by default. Run `claude auto-mode defaults` to see the live rule lists. Administrators can extend the trust set for specific repos, buckets, and services via the `autoMode.environment` setting — see [Configure auto mode](https://code.claude.com/docs/en/auto-mode-config).

## What Happens to Allow Rules on Entering Auto Mode

Auto mode **drops broad allow rules** that would otherwise grant arbitrary code execution. They are restored when leaving auto mode.

| Pattern | Behaviour in auto mode |
|---------|------------------------|
| `Bash(*)`, `PowerShell(*)` | Dropped |
| Wildcarded interpreters: `Bash(python*)`, `Bash(node*)`, etc. | Dropped |
| Package-manager run wildcards (e.g. broad `Bash(npm *)` ish patterns granting arbitrary scripts) | Dropped |
| `Agent` allow rules | Dropped |
| **Narrow rules**: `Bash(npm test)`, `Bash(git status *)`, `Bash(gh pr *)` | **Carried over** — skip the classifier round-trip |

**Implication for skill authors**: granular `Bash(<command> *)` patterns in skill `allowed-tools` and project `settings.json` are *more* valuable under auto mode, not less — they bypass the classifier and avoid latency. Broad `Bash(*)` is not a shortcut; it is dropped at runtime.

## Conversation-Stated Boundaries

The classifier treats boundaries the user states in the conversation as block signals. "Don't push", "wait until I review before deploying", and similar instructions block matching actions even when default rules would allow them. A boundary stays in force until the user lifts it in a later message; Claude's own judgement that the condition was met does not lift it.

Boundaries are read from the transcript on each check, so context compaction can drop them. For a hard guarantee, use a [deny rule](https://code.claude.com/docs/en/permissions#permission-rule-syntax) instead of relying on a stated boundary.

## Protected Paths

Writes to protected paths are never auto-approved in any mode. Under auto mode they route to the classifier rather than being silently allowed.

Protected directories: `.git`, `.vscode`, `.idea`, `.husky`, `.claude` (except `.claude/commands`, `.claude/agents`, `.claude/skills`, `.claude/worktrees`).

Protected files: `.gitconfig`, `.gitmodules`, `.bashrc`, `.bash_profile`, `.zshrc`, `.zprofile`, `.profile`, `.ripgreprc`, `.mcp.json`, `.claude.json`.

## Subagents Under Auto Mode

The classifier checks subagent work at three points:

1. **Spawn**: the delegated task description is evaluated; a dangerous-looking task is blocked at spawn time.
2. **Each action**: every tool call goes through the classifier with the same rules as the parent session.
3. **Return**: the subagent's full action history is reviewed; flagged concerns prepend a security warning to the subagent's results.

Crucially, **`permissionMode` in subagent frontmatter is ignored** in auto mode. Skill authors should not rely on per-subagent permission overrides under auto mode; rely on `allowed-tools` for the subagent's tool boundary instead.

## Deny-and-Continue Behaviour

When the classifier blocks an action:

1. The action is denied and a notification surfaces in `/permissions` under "Recently denied"
2. The user can press `r` to retry it with a manual approval
3. Claude receives the reason and tries an alternative

If blocking happens **3 times in a row** or **20 times total** in a session, auto mode pauses and Claude Code resumes prompting. Approving the prompted action resumes auto mode. Any allowed action resets the consecutive counter; the total counter persists for the session and only resets when its own threshold triggers a fallback. These thresholds are not configurable.

In `-p` (non-interactive) mode there is no user to prompt — repeated blocks abort the session.

## Cost and Latency

Each classifier check adds a round-trip and consumes tokens against the user's quota. Reads and working-directory edits skip the classifier, so the overhead lands mainly on shell commands and network operations. Narrow `allow` rules in `settings.json` and skill `allowed-tools` reduce that overhead by short-circuiting step 1 of the decision order.

## Authoring Guidance for Plugin Skills

| Skill area | Guidance under auto mode |
|------------|--------------------------|
| `allowed-tools` in frontmatter | Keep narrow `Bash(<command> *)` patterns. They carry over, skip the classifier round-trip, and remain the subagent tool boundary. Broad `Bash(*)` is dropped at runtime — do not rely on it. |
| `:ask` suffix | Still useful for genuinely dangerous operations the user should always confirm regardless of mode. |
| Hostile-content surface | Tool results are stripped from classifier input, but skill-emitted text the user reads is not. Continue to validate web fetches and untrusted file content as usual. |
| Subagent skills | Do not rely on `permissionMode` in subagent frontmatter under auto mode — it is ignored. Lean on narrow `allowed-tools` and `allow`/`deny` rules. |
| Stated boundaries | If a skill's prompts ask the user to set a boundary ("I won't push until you say so"), document that the boundary can be lost on context compaction; suggest a deny rule for hard guarantees. |
| Project `settings.json` | Keep narrow `Bash(git *)`, `Bash(gh *)`, `Bash(fd *)`, etc. patterns. They are not redundant under auto mode. |

## Project `settings.json` Recommendation

Under auto mode, narrow allow rules still earn their keep:

```json
{
  "permissions": {
    "allow": [
      "Bash(git status *)",
      "Bash(git diff *)",
      "Bash(gh pr *)",
      "WebFetch(domain:your-docs-site.com)",
      "mcp__your-mcp-server"
    ]
  }
}
```

Avoid broad patterns such as `Bash(*)` — they are dropped on entering auto mode and provide no benefit while reducing safety in other modes.

## PermissionRequest Hooks Under Auto Mode

The auto-mode classifier handles approve/deny logic for most cases that previously needed a `PermissionRequest` hook. Hooks remain valuable for:

- Deterministic, auditable rules where the classifier's probabilistic answer is unsuitable
- Enterprise compliance requirements that need explicit deny lists
- Project-specific policies beyond the default trust set
- Cases where a 0% false-positive guarantee on a specific command matters

`PermissionRequest` hooks coexist with auto mode. See [`hooks-plugin/skills/hooks-permission-request-hook`](../../hooks-plugin/skills/hooks-permission-request-hook/SKILL.md) for the generator and [`.claude/rules/hooks-reference.md`](hooks-reference.md) for hook event reference.

## Mode Interaction Summary

| Permission mode | Auto-approves | Notes |
|-----------------|---------------|-------|
| `default` | Reads only | Permission prompts for everything else |
| `acceptEdits` | Reads, file edits, common filesystem commands | Edits scoped to working dir / `additionalDirectories` |
| `plan` | Reads only; no source edits | Approve-from-plan can transition into `auto` |
| `auto` | Everything that survives classifier review | Subject to availability matrix above |
| `dontAsk` | Pre-approved tools only | Auto-denies anything that would prompt |
| `bypassPermissions` | Everything (except protected paths) | No safety classifier; isolated environments only |

## Related Rules

- `.claude/rules/agentic-permissions.md` — granular permission syntax and standard sets
- `.claude/rules/skill-development.md` — skill creation patterns and `allowed-tools` usage
- `.claude/rules/hooks-reference.md` — hook event reference, including `PermissionRequest`
