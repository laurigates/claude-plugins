# Claude Code Changelog Review: 0.0.0 → 2.1.7

> **Note**: Create this as a GitHub issue with labels: `changelog-review`, `enhancement`

## Summary

| Category | Count |
|----------|-------|
| High-impact changes | 8 |
| Medium-impact changes | 12 |
| Plugins potentially affected | 6 |

**Review Date**: 2026-01-14
**Source**: [Claude Code Changelog](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)

---

## High-Impact Changes Requiring Action

### 1. hooks-plugin - Hook System Evolution

**Changes:**
- **v2.1.0**: Hooks now supported in skill/command frontmatter
- **v2.0.43**: `SubagentStart` hook event added with `agent_id` and `agent_transcript_path` fields
- **v2.0.30**: `SessionEnd` hooks introduced; prompt-based stop hooks added
- **v2.0.10**: PreToolUse hooks can now modify tool inputs via `updatedInput`

**Suggested Actions:**
- [ ] Update `SKILL.md` to document new hook events (SubagentStart, SessionEnd)
- [ ] Add examples for input modification in PreToolUse hooks
- [ ] Document frontmatter hook support for skills/commands
- [ ] Create example hooks for new events

---

### 2. agent-patterns-plugin - Agent Capabilities

**Changes:**
- **v2.1.0**: `context: fork` in skill frontmatter enables forked sub-agent context
- **v2.1.0**: `agent` field in skills to specify agent type
- **v2.0.30**: `disallowedTools` field for custom agent definitions
- **v2.0.28**: Plan Mode uses new Plan subagent; subagents can be dynamically resumed

**Suggested Actions:**
- [ ] Add documentation for `context: fork` pattern
- [ ] Document `disallowedTools` for agent definitions
- [ ] Update multi-agent workflow patterns for subagent resume capability
- [ ] Add examples using the new `agent` field in skills

---

### 3. All Plugins - Skills/Commands Merged

**Changes:**
- **v2.1.3**: Skills and slash commands merged, simplifying mental model
- **v2.1.0**: Automatic skill hot-reload from skill directories
- **v2.1.0**: `SlashCommand` tool - Claude can invoke custom slash commands
- **v2.0.28**: Slash commands can invoke skills

**Suggested Actions:**
- [ ] Review all skill/command descriptions for consistency with merged model
- [ ] Document hot-reload behavior in skill development guide
- [ ] Consider adding SlashCommand tool invocation examples

---

### 4. configure-plugin - Permission System Updates

**Changes:**
- **v2.1.7**: Security fix - wildcard permission rules with shell operators
- **v2.1.0**: Wildcard pattern matching for bash permissions using `*` at any position
- **v2.0.70**: `mcp__server__*` wildcard for MCP tool permissions
- **v2.1.6**: Permission bypass detection via shell line continuation

**Suggested Actions:**
- [ ] Review and update permission rule documentation
- [ ] Add examples for new wildcard patterns
- [ ] Document security considerations for shell operators
- [ ] Add MCP wildcard permission examples

---

### 5. agent-patterns-plugin - MCP Improvements

**Changes:**
- **v2.1.7**: MCP tool search auto mode enabled by default
- **v1.0.27**: Streamable HTTP and SSE MCP servers supported
- **v2.0.54**: MCP SSE server configs support custom headers
- **v2.0.12**: Enterprise managed MCP allowlist/denylist

**Suggested Actions:**
- [ ] Update MCP management skill with new capabilities
- [ ] Document SSE server configuration patterns
- [ ] Add examples for custom headers in MCP configs

---

### 6. SDK Changes - agent-patterns-plugin

**Changes:**
- **v2.0.25**: Legacy SDK entrypoint removed - migrate to `@anthropic-ai/claude-agent-sdk`
- **v2.0.34**: Custom tools as callbacks support
- **v1.0.109**: Partial message streaming via `--include-partial-messages`

**Suggested Actions:**
- [ ] Verify SDK references use new package name
- [ ] Document callback-based custom tools
- [ ] Add streaming examples where relevant

---

## Medium-Impact Opportunities

### New Features Worth Documenting

| Feature | Version | Potential Use |
|---------|---------|---------------|
| LSP tool | v2.0.74 | Code intelligence in skills |
| Named sessions | v2.0.64 | Session management patterns |
| `/config` search | v2.1.6 | Configuration discovery |
| Context window info | v2.0.65 | Status line customization |
| Thinking mode default | v2.0.67 | Opus 4.5 patterns |

### Environment Variables to Document

| Variable | Purpose |
|----------|---------|
| `CLAUDE_CODE_TMPDIR` | Override temp directory |
| `CLAUDE_CODE_SHELL` | Override shell detection |
| `FORCE_AUTOUPDATE_PLUGINS` | Plugin auto-update control |

---

## Recommended Action Plan

### Immediate (High Priority)
1. [ ] Update hooks-plugin with new hook events and input modification
2. [ ] Add `context: fork` and `disallowedTools` to agent-patterns-plugin
3. [ ] Review permission documentation in configure-plugin

### Next Sprint
4. [ ] Document skill/command merged model across plugins
5. [ ] Update MCP patterns with new capabilities
6. [ ] Add environment variable documentation

### Backlog
7. [ ] Add LSP tool examples to relevant skills
8. [ ] Document new status line fields
9. [ ] Review for deprecated patterns to remove

---

## Version Tracking

The changelog review system has been set up:
- **Tracking file**: `.claude-code-version-check.json`
- **Automated workflow**: `.github/workflows/changelog-review.yml` (weekly)
- **Manual command**: `/changelog:review`

Future reviews will only show changes since v2.1.7.

---

*Delete this file after creating the GitHub issue.*
