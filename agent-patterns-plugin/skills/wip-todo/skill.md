---
name: WIP TODO Comments
description: |
  Mark incomplete work with TODO(wip) comments so the next agent or developer can continue.
  Use when you cannot finish a task in the current session, need to leave breadcrumbs for
  a follow-up agent, or want to annotate partially implemented code so it is easy to find
  and resume later.
allowed-tools: Bash, Read, Edit, Write, Grep, Glob, TodoWrite
created: 2025-01-24
modified: 2026-02-05
reviewed: 2025-01-24
---

# WIP TODO Comments

Leave standard `TODO(wip)` comments in code when work is incomplete. These serve as breadcrumbs for the next agent session or human developer to pick up where you left off.

## Core Principle

Write TODOs that any developer would understand without special knowledge. The comment should explain *what's incomplete* and *what remains* in plain language.

## When to Leave a TODO(wip)

- Stopping mid-implementation (context limit, user interrupt, task switch)
- Stubbing out a function that needs real implementation
- Partially completing a multi-step change across files
- Identifying work that can't be done right now (missing dependency, needs design input)

## When to Remove a TODO(wip)

- The described work is complete
- The TODO is obsolete (approach changed, feature dropped)
- Converting to a permanent TODO or issue (the work is deferred intentionally)

## Format

### Minimal (one-liner)

```typescript
// TODO(wip): Implement error boundary for this component tree.
```

### With Context (multi-line)

```typescript
// TODO(wip): Registration form validation incomplete.
// Status: email format check done, renders error messages
// Remaining: password strength rules, async username uniqueness check
// Context: part of user onboarding flow (issue #34)
```

### Optional Fields

| Field | Purpose |
|-------|---------|
| `Status:` | What's already done |
| `Remaining:` | Specific items left to do |
| `Context:` | Why this matters, links to issues/PRs |
| `Blocked:` | What's preventing completion |

Fields are optional. Use only what's helpful. A clear one-liner is often enough.

## Language-Specific Comment Styles

```typescript
// TODO(wip): TypeScript/JavaScript style
```

```python
# TODO(wip): Python style
```

```rust
// TODO(wip): Rust style
```

```go
// TODO(wip): Go style
```

```html
<!-- TODO(wip): HTML/template style -->
```

## Examples

### Stubbed Function

```typescript
function calculateShipping(cart: Cart): ShippingResult {
  // TODO(wip): Implement shipping calculation.
  // Status: function signature and types defined
  // Remaining: weight-based rates, free shipping threshold, international zones
  return { cost: 0, method: 'standard' };
}
```

### Partial Migration

```python
# TODO(wip): Migrate remaining endpoints to new auth middleware.
# Status: /users and /products done
# Remaining: /orders, /payments, /webhooks
# Context: auth migration tracking in JIRA-567
```

### Blocked Work

```typescript
// TODO(wip): Add real-time notifications via WebSocket.
// Blocked: WebSocket server not deployed yet (infra ticket INFRA-89)
// Status: client-side hook written, falls back to polling
```

### Multi-File Coordination

When work spans multiple files, leave a TODO in each with cross-references:

```typescript
// src/hooks/usePayment.ts
// TODO(wip): Connect to Stripe checkout session.
// Remaining: create session on submit, handle redirect, poll for completion
// See also: src/pages/Checkout.tsx (UI side of this flow)
```

```typescript
// src/pages/Checkout.tsx
// TODO(wip): Wire up payment form to usePayment hook.
// Status: form layout done, validation working
// Remaining: submit handler, loading state, error display
// See also: src/hooks/usePayment.ts (hook implementation)
```

## Scanning for WIP TODOs

```bash
# Find all WIP TODOs in codebase
rg "TODO\(wip\)" -n

# With surrounding context
rg "TODO\(wip\)" -A 3

# Count by file
rg "TODO\(wip\)" -c

# Find stale ones (combine with git blame)
rg "TODO\(wip\)" -l | xargs -I{} git blame {} | grep "TODO(wip)"
```

## Lifecycle

```
Work starts → implement partially → leave TODO(wip) → session ends
                                                            ↓
New session starts → scan for TODO(wip) → resume work → remove TODO(wip)
```

## Guidelines

1. **Write for humans first** - The comment should make sense to any teammate
2. **Be specific** - "validation incomplete" is better than "not done yet"
3. **Include what's done** - Helps the next person avoid redoing work
4. **Keep it short** - 1-4 lines is ideal, not a design document
5. **Clean up after yourself** - Remove the TODO when the work is complete
6. **Don't over-tag** - Only leave TODOs for genuinely incomplete work, not aspirational improvements

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Find all WIP items | `rg "TODO\(wip\)" -n` |
| WIP with context | `rg "TODO\(wip\)" -A 3` |
| Count WIP items | `rg "TODO\(wip\)" -c` |
| WIP in specific dir | `rg "TODO\(wip\)" src/ -n` |
