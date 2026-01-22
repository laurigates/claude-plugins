---
model: haiku
created: 2025-12-16
modified: 2025-12-26
reviewed: 2025-12-26
description: "Generate a continuation primer for agent handoff with todo list and context"
allowed-tools: Read, Grep, Glob, TodoWrite
---

# /workflow:primer

Generate a structured todo list and context primer so another agent can continue from the current state.

## Purpose

When work must be handed off between agent sessions (due to context limits, user request, or task transition), this command creates a compact summary that enables seamless continuation.

## Usage

```bash
/workflow:primer
```

## Output Structure

The primer includes:

### 1. Current State Summary
What has been accomplished in this session:
- Completed tasks
- Files modified
- Key decisions made

### 2. Remaining Todo List
Pending tasks in priority order:
- Blocking items first
- Clear, actionable descriptions
- File paths where applicable

### 3. Key Context
Critical information for continuation:
- Architecture decisions
- Constraints discovered
- Dependencies identified

### 4. Active Files
Files currently being worked on:
- Path and purpose
- Current state (draft/partial/complete)
- What remains to be done

### 5. Blockers/Issues
Known obstacles:
- Technical blockers
- Questions needing answers
- Dependencies on external factors

## Example Output

```markdown
# Agent Continuation Primer

## Session Summary
Implemented user authentication flow for the dashboard.
Modified 4 files, created 2 new components.

## Remaining Tasks
1. [BLOCKING] Add error handling to login form
   - File: src/components/LoginForm.tsx
   - Need: validation messages, network error states

2. [BLOCKING] Write unit tests for auth hook
   - File: src/hooks/useAuth.test.ts
   - Coverage: login, logout, token refresh

3. Add loading states to login button
   - File: src/components/LoginForm.tsx
   - Enhancement, not blocking

## Key Context
- Using React Query for server state
- JWT tokens stored in httpOnly cookies
- Auth state in React Context (not Redux)

## Active Files
- src/hooks/useAuth.ts - Complete, needs tests
- src/components/LoginForm.tsx - 80% done, needs error handling
- src/pages/Login.tsx - Complete

## Known Issues
- Token refresh endpoint returns 500 intermittently (backend issue)
- Need design input on error message styling
```

## When to Use

- Context window is filling up and work must continue in new session
- Handing off to a different specialized agent
- User requests a break in the session
- Long-running task needs checkpoint documentation

## Integration

This command works with the agent-handoff-markers skill for inline code markers that persist between sessions.

## See Also

- **Skills**: `agent-handoff-markers` for inline code markers
- **Skills**: `agent-coordination-patterns` for workflow patterns
- **Skills**: `multi-agent-workflows` for complex coordination
