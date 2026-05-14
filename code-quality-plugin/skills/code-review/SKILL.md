---
created: 2025-12-16
modified: 2026-05-09
reviewed: 2026-04-25
allowed-tools: Task, TodoWrite, Glob, Read
model: opus
description: Code review for quality, security, performance, and architecture. Use when reviewing code, auditing OWASP, checking SOLID, or finding perf bottlenecks and test gaps.
args: "[PATH]"
argument-hint: "[PATH]"
name: code-review
agent: general-purpose
---

## When to Use This Skill

| Use this skill when... | Use something else instead when... |
|------------------------|------------------------------------|
| Running an end-to-end review across quality, security, perf, and tests | Walking a manual security/correctness checklist → `code-review-checklist` |
| Auditing a directory or PR delta with delegated agent analysis | Specifically scanning for code smells → `code-antipatterns` |
| Spotting missing test cases or weak assertions | Auditing test code quality on its own → `code-test-quality` |
| Producing a consolidated review report | Refactoring after the review surfaces issues → `code-refactor` |

## Context

- Review path: `$1` (defaults to current directory if not specified)

## Parameters

- `$1`: Path to review (defaults to current directory)

## Your task

**Delegate this task to the `code-review` agent.**

Use the Agent tool with `subagent_type: code-review` to perform a comprehensive code review.

First, use the Glob tool to discover source files to review:
- `**/*.py`, `**/*.js`, `**/*.ts`, `**/*.go`, `**/*.rs` for source files
- `**/*test*` patterns for test files
Then pass the discovered files to the agent.

The code-review agent should:

1. **Analyze code quality**:
   - Naming conventions and readability
   - Code structure and maintainability
   - SOLID principles adherence

2. **Security assessment**:
   - Input validation vulnerabilities
   - Authentication and authorization issues
   - Secrets and sensitive data exposure

3. **Performance evaluation**:
   - Bottlenecks and inefficiencies
   - Memory usage patterns
   - Optimization opportunities

4. **Architecture review**:
   - Design patterns usage
   - Component coupling
   - Dependency management

5. **Test coverage gaps**:
   - Missing test cases
   - Edge cases not covered
   - Integration test needs

6. **Apply fixes** where appropriate and safe

7. **Generate report** with:
   - Summary of issues found/fixed
   - Remaining manual interventions needed
   - Improvement recommendations

Provide the agent with:
- The review path from context
- Project type (language/framework)
- Any specific focus areas requested

The agent has expertise in:
- Multi-language code analysis (Python, TypeScript, Go, Rust)
- LSP integration for accurate diagnostics
- Security vulnerability patterns (OWASP)
- Performance analysis and optimization

## Agent Teams (Optional)

For comprehensive review of large codebases, spawn specialized review teammates in parallel:

| Teammate | Focus | Value |
|----------|-------|-------|
| Security reviewer | OWASP, secrets, auth flaws | Deep security analysis without blocking quality review |
| Performance reviewer | N+1 queries, algorithmic complexity, resource leaks | Performance-focused review in parallel |
| Correctness reviewer | Logic errors, edge cases, type safety | Functional correctness in parallel |

This is optional — the skill works without agent teams for standard reviews.

## Related Configure Skills

- If security scanning not configured → `/configure:security`
- If linting not set up → `/configure:linting`
- If test coverage not tracked → `/configure:coverage`
