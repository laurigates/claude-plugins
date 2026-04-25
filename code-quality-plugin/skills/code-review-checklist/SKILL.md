---
name: code-review-checklist
description: |
  Structured code review checklist covering security, correctness,
  performance, quality, and consistency. Use when the user asks for a code
  review, wants to check for hardcoded secrets or injection vulnerabilities,
  verify error handling and edge cases, audit for N+1 queries or resource
  leaks, or apply a priority-ordered review to a pull request.
user-invocable: false
allowed-tools: Read, Grep, Glob
created: 2025-12-27
modified: 2026-04-25
reviewed: 2026-04-25
---

# Code Review Checklist

Structured approach to reviewing code changes.

## When to Use This Skill

| Use this skill when... | Use something else instead when... |
|------------------------|------------------------------------|
| Walking a priority-ordered manual review checklist | Running a full delegated review pass → `code-review` |
| Hunting for hardcoded secrets, injection, or N+1 query patterns | Scanning specifically for anti-patterns → `code-antipatterns` |
| Verifying error handling and edge cases in a PR diff | Targeting swallowed errors directly → `code-error-swallowing` |
| Applying a deterministic checklist to a small change | Refactoring after the checklist surfaces issues → `code-refactor` |

## Review Priority Order

1. **Security** (Critical) - Vulnerabilities, secrets, injection
2. **Correctness** (High) - Logic errors, breaking changes
3. **Performance** (Medium) - Inefficiencies, resource leaks
4. **Quality** (Medium) - Maintainability, readability
5. **Style** (Low) - Formatting, naming (should be automated)

## Security Checklist

### Secrets & Credentials
- [ ] No hardcoded API keys, passwords, tokens
- [ ] No credentials in logs or error messages
- [ ] Secrets loaded from environment/vault

### Injection Vulnerabilities
- [ ] SQL queries use parameterized statements
- [ ] User input is sanitized before HTML output (XSS)
- [ ] Shell commands don't include user input (command injection)
- [ ] File paths are validated (path traversal)

### Authentication & Authorization
- [ ] Auth checks on all protected endpoints
- [ ] Proper session handling
- [ ] Secure password handling (hashing, not plaintext)

### Data Exposure
- [ ] Sensitive data not logged
- [ ] API responses don't leak internal details
- [ ] Error messages don't expose system info

## Correctness Checklist

### Logic
- [ ] Edge cases handled (null, empty, boundary values)
- [ ] Error conditions handled appropriately
- [ ] Async operations properly awaited
- [ ] Race conditions considered

### Breaking Changes
- [ ] API contracts maintained
- [ ] Database migrations are reversible
- [ ] Feature flags for risky changes

### Testing
- [ ] New code has tests
- [ ] Tests cover error paths, not just happy path
- [ ] Existing tests still pass

## Performance Checklist

### Efficiency
- [ ] No N+1 queries
- [ ] Appropriate data structures used
- [ ] No unnecessary loops or iterations
- [ ] Caching considered for expensive operations

### Resources
- [ ] Database connections closed/pooled
- [ ] File handles closed
- [ ] No memory leaks (event listeners removed, etc.)

### Scale
- [ ] Works with realistic data volumes
- [ ] Pagination for large result sets
- [ ] Timeouts on external calls

## Quality Checklist

### Readability
- [ ] Clear, descriptive names
- [ ] Functions do one thing
- [ ] No overly complex conditionals
- [ ] Comments explain "why", not "what"

### Maintainability
- [ ] DRY (no copy-paste duplication)
- [ ] Appropriate abstractions
- [ ] Dependencies are justified
- [ ] No dead code

### Consistency
- [ ] Follows project patterns
- [ ] Matches existing code style
- [ ] Uses established utilities/helpers

## Review Output Format

```markdown
## Review: [PR Title]

**Risk Level**: LOW | MEDIUM | HIGH | CRITICAL

### Critical Issues
1. [Category] Description (file:line)
   - Impact: What could go wrong
   - Fix: Specific recommendation

### Suggestions
1. [Category] Description (file:line)
   - Why: Reasoning
   - Consider: Alternative approach

### Positive Notes
- [Recognition of good patterns]
```

## Quick Checks

For fast reviews, at minimum check:
1. Any secrets or credentials?
2. Any SQL/command injection?
3. Are error cases handled?
4. Do tests exist for new code?
