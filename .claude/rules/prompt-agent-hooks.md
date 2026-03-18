---
paths:
  - ".claude/hooks/**"
  - "**/.claude-plugin/plugin.json"
  - ".claude/settings*.json"
---

# Prompt-Based and Agent-Based Hooks

When to use LLM-powered hooks (`type: "prompt"` and `type: "agent"`), HTTP hooks (`type: "http"`), or deterministic command hooks (`type: "command"`).

## Hook Type Decision

| Choose... | When... | Example |
|-----------|---------|---------|
| `type: "command"` | Logic is deterministic: regex, field presence, exit codes | Frontmatter validation, anti-pattern regex, git stash check |
| `type: "http"` | Logic is deterministic but handled by a **remote service** | Centralized policy enforcement, external audit logging, webhook integrations |
| `type: "prompt"` | Decision requires **judgment** and the hook input data is sufficient | Task completeness evaluation, prompt classification, output quality |
| `type: "agent"` | Decision requires judgment **and** inspecting files or running commands | Test verification, code review, implementation quality checks |

### Quick Decision Tree

```
Does the check have a deterministic rule?
├─ Yes →
│   Is the logic handled by a remote service?
│   ├─ Yes → type: "http" (webhook, centralized policy)
│   └─ No → type: "command" (regex, field check, exit code)
└─ No, requires judgment →
    Does verification need to read files or run commands?
    ├─ No, hook input data is enough → type: "prompt"
    └─ Yes, needs filesystem/tool access → type: "agent"
```

## Supported Events

Not all events support prompt/agent hooks.

### Events supporting all three types

| Event | Typical Use |
|-------|-------------|
| `PreToolUse` | Block unsafe tool calls based on context |
| `PostToolUse` | Evaluate tool output quality |
| `PostToolUseFailure` | Decide whether to retry or abort |
| `PermissionRequest` | Auto-approve/deny based on intent |
| `Stop` | Task completeness gates |
| `SubagentStop` | Subagent output quality verification |
| `TaskCompleted` | Implementation completeness checks |
| `UserPromptSubmit` | Prompt classification, context injection |
| `Elicitation` | Auto-accept/decline MCP input requests |
| `ElicitationResult` | Override MCP input results before sending |

### Events supporting only `type: "command"`

| Event | Reason |
|-------|--------|
| `SessionStart` | Environment setup is mechanical |
| `SessionEnd` | Cleanup is mechanical |
| `PreCompact` | Context preservation is data extraction |
| `SubagentStart` | Prompt injection is mechanical |
| `TeammateIdle` | Task assignment is mechanical |
| `WorktreeCreate` | Dependency installation is mechanical |
| `WorktreeRemove` | Cleanup is mechanical |
| `ConfigChange` | Audit logging is mechanical |
| `Notification` | Notification routing is mechanical |

## Configuration Schema

### Prompt Hook

Single-turn LLM evaluation. Haiku by default, 30-second timeout.

```json
{
  "type": "prompt",
  "prompt": "Evaluate whether... $ARGUMENTS",
  "model": "haiku",
  "timeout": 30
}
```

| Field | Required | Default | Description |
|-------|----------|---------|-------------|
| `type` | Yes | — | `"prompt"` |
| `prompt` | Yes | — | Prompt text. `$ARGUMENTS` is replaced with hook input JSON |
| `model` | No | Fast model (Haiku) | Model for evaluation |
| `timeout` | No | 30s | Seconds before canceling |
| `statusMessage` | No | — | Custom spinner message while running |

### Agent Hook

Multi-turn subagent with tool access (Read, Grep, Glob, Bash). 60-second default timeout.

```json
{
  "type": "agent",
  "prompt": "Verify that... $ARGUMENTS",
  "model": "haiku",
  "timeout": 60
}
```

| Field | Required | Default | Description |
|-------|----------|---------|-------------|
| `type` | Yes | — | `"agent"` |
| `prompt` | Yes | — | Prompt describing what to verify. `$ARGUMENTS` is replaced with hook input JSON |
| `model` | No | Fast model (Haiku) | Model for the agent |
| `timeout` | No | 60s | Seconds before canceling |
| `statusMessage` | No | — | Custom spinner message while running |

## Response Schema

Both prompt and agent hooks return the same JSON:

```json
{"ok": true}
```

```json
{"ok": false, "reason": "Explanation of what's wrong or what remains"}
```

- `ok: true` → action proceeds
- `ok: false` → action is blocked; `reason` is fed back to Claude as feedback

## Stop Hook Loop Prevention

Stop hooks fire **every time** Claude finishes responding, including after it acts on a Stop hook's feedback. Prevent infinite loops by checking the `stop_hook_active` field:

```json
{
  "type": "prompt",
  "prompt": "First check: if stop_hook_active is true in the input, respond with {\"ok\": true} immediately — Claude is already addressing a previous stop hook. Otherwise, evaluate whether all tasks are complete. $ARGUMENTS"
}
```

For command hooks, check the field in your script:
```bash
if [ "$(echo "$INPUT" | jq -r '.stop_hook_active')" = "true" ]; then
  exit 0
fi
```

## Writing Effective Prompts

### Prompt Hook Prompts

Keep prompts focused on a single judgment call. The model receives the hook input JSON via `$ARGUMENTS`.

**Effective pattern:**
```
You are evaluating whether [specific condition]. Context: $ARGUMENTS

Check if:
1. [Specific criterion]
2. [Specific criterion]

Respond with {"ok": true} if [condition met], or {"ok": false, "reason": "what's wrong"}.
```

**Avoid:**
- Vague instructions ("check if things look good")
- Multiple unrelated checks in one prompt
- Instructions that require filesystem access (use agent hooks instead)

### Agent Hook Prompts

Give the agent clear verification steps and tell it what tools to use.

**Effective pattern:**
```
Verify [condition] by:
1. Read [specific files]
2. Check [specific conditions]
3. Run [specific command] if needed

Context: $ARGUMENTS

Respond with {"ok": true} if [all checks pass], or {"ok": false, "reason": "specific failures"}.
```

## Cost and Latency Considerations

| Hook Type | Latency | Cost | Use When |
|-----------|---------|------|----------|
| `command` | ~10ms | Free | Deterministic checks |
| `http` | ~50-500ms | Free (self-hosted) | Remote/centralized deterministic checks |
| `prompt` | ~1-3s | Low (Haiku) | Judgment on hook input data |
| `agent` | ~5-60s | Medium | Verification needing file/tool access |

### Optimization Tips

- Default to `command` hooks — free and instant
- Convert `agent` hooks to `command` hooks when the logic is deterministic (e.g., test verification: `git diff` + test runner detection is a bash script, not an LLM task)
- Use `prompt` hooks sparingly on high-frequency events (`PreToolUse` fires often)
- Reserve `agent` hooks for checks that genuinely require LLM judgment AND tool access
- Set appropriate timeouts (don't use 120s when 30s suffices)
- Use the `model` field to pick the cheapest model that works

### Anti-Patterns

- **SessionEnd hooks that mutate git state**: Hooks that run `git switch main`, `git pull`, or auto-commit affect every repository and cause unintended side effects across unrelated sessions. Keep SessionEnd hooks to cleanup only (temp files, logs).

## Plugin Integration Patterns

### Layered Validation

Combine command hooks (fast/free structural checks) with prompt/agent hooks (judgment-based quality checks):

```json
{
  "PreToolUse": [
    {
      "matcher": "Skill(prp-execute)",
      "hooks": [
        {
          "type": "command",
          "command": "bash ${CLAUDE_PLUGIN_ROOT}/hooks/check-prp-readiness.sh",
          "timeout": 10
        },
        {
          "type": "agent",
          "prompt": "Read the PRP file and evaluate content quality...",
          "timeout": 30
        }
      ]
    }
  ]
}
```

The command hook runs first (fast structural validation). If it passes, the agent hook evaluates content quality. Both must pass for the action to proceed.

### Event-Specific Patterns

| Event | Recommended Type | Pattern |
|-------|-----------------|---------|
| `Stop` | `prompt` | Task completeness evaluation |
| `Stop` | `command` | Test suite verification (deterministic: `git diff` → detect test runner → run tests) |
| `SubagentStop` | `prompt` | Output completeness check |
| `TaskCompleted` | `agent` | Implementation quality gate |
| `UserPromptSubmit` | `prompt` | Intent classification, safety check |
| `PreToolUse` | `command` + `prompt` | Structural check + judgment |

## Checklist for New Prompt/Agent Hooks

- [ ] Event supports `type: "prompt"` or `type: "agent"` (see Supported Events)
- [ ] Hook type matches the decision complexity (see Decision Tree)
- [ ] Prompt includes `$ARGUMENTS` placeholder for hook input
- [ ] Stop hooks check `stop_hook_active` to prevent infinite loops
- [ ] Timeout is set explicitly and appropriate for the task
- [ ] Prompt is specific and includes clear success/failure criteria
- [ ] Agent hooks describe what files to read or commands to run
- [ ] Model is appropriate (Haiku for simple judgment, Sonnet for complex)
- [ ] High-frequency events prefer `command` or `prompt` over `agent`

## Related Rules

- `.claude/rules/hooks-reference.md` — Complete hook event reference and schemas
- `.claude/rules/handling-blocked-hooks.md` — How to respond when hooks block actions
- `.claude/rules/agentic-permissions.md` — Granular tool permission patterns
- `.claude/rules/agent-development.md` — Agent configuration patterns
