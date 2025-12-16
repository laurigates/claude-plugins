---
name: test-tier-selection
description: Automatic selection of appropriate test tiers based on change scope. Guides unit tests for small changes, full suite for larger changes. Use when running tests, discussing testing strategy, or after code modifications.
allowed-tools: Bash, Read, Glob, Grep
---

# Test Tier Selection

Automatic guidance for selecting appropriate test tiers based on change context and scope.

## Test Tier Definitions

| Tier | Duration | Scope | When to Run |
|------|----------|-------|-------------|
| **Unit** | < 30s | Single function/module | After every code change |
| **Integration** | < 5min | Component interactions | After feature completion |
| **E2E** | < 30min | Full user flows | Before commit/PR |

## Decision Matrix

### Change Type → Test Tier

| Change Type | Unit | Integration | E2E |
|-------------|------|-------------|-----|
| Single function fix | Required | Skip | Skip |
| New feature (1 file) | Required | Required | Skip |
| Multi-file feature | Required | Required | Required |
| Refactoring | Required | Required | Optional |
| API changes | Required | Required | Required |
| UI changes | Required | Optional | Required |
| Bug fix (isolated) | Required | Optional | Skip |
| Database changes | Required | Required | Required |
| Config changes | Required | Required | Optional |

## Escalation Signals

**Escalate to Integration when:**
- Changes span multiple files
- Business logic affected
- Service boundaries modified
- Database queries changed

**Escalate to E2E when:**
- User-facing features modified
- Authentication/authorization changes
- Critical path functionality
- Before creating PR

## Commands by Tier

```bash
# Tier 1: Unit (fast feedback)
/test:quick

# Tier 2: Integration (feature completion)
/test:full --coverage

# Tier 3: E2E (pre-commit)
/test:full
```

## Agent Consultation Triggers

**Consult `test-architecture` agent when:**
- New feature module created
- Coverage drops > 5%
- > 3 flaky tests detected
- Framework questions arise
- Test strategy needs adjustment

**Consult `test-runner` agent when:**
- Need test execution with analysis
- Multiple failures to diagnose
- Want concise failure summary

**Consult `system-debugging` agent when:**
- Integration test failures with unclear cause
- Environment/timing issues
- Flaky tests related to concurrency

## Quick Reference

### After Small Change
```
1. Run /test:quick
2. If pass: Continue working
3. If fail: Fix immediately
```

### After Feature Completion
```
1. Run /test:full --coverage
2. Check coverage targets met
3. If gaps: /test:consult coverage
```

### Before Commit/PR
```
1. Run /test:full
2. All tiers must pass
3. Review coverage report
```

### For New Features
```
1. /test:consult new-feature
2. Write tests (TDD)
3. Run /test:quick during development
4. Run /test:full before PR
```

## Activation Triggers

This skill auto-activates when:
- User mentions "test", "run tests", "testing"
- After code modification by Claude
- During TDD workflow
- When `/test:*` commands invoked
- When discussing test strategy
