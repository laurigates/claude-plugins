---
created: 2025-12-16
modified: 2026-07-04
reviewed: 2026-07-04
allowed-tools: Task, TodoWrite, Glob, Read
model: opus
description: Code review for quality, security, performance, and architecture. Use when reviewing code, auditing OWASP, checking SOLID, or finding perf bottlenecks and test gaps.
args: "[PATH]"
argument-hint: "[PATH]"
name: code-review
agent: general-purpose
context: fork
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

7. **Re-verify each candidate finding** (false-positive gate — run BEFORE reporting):
   For every candidate finding from steps 1–5, re-read the cited code at the
   reported `file:line` and confirm the claim actually holds against the current
   source — not against a remembered or assumed shape. A finding survives only if
   the re-read confirms it; drop the rest. See "Re-verification Pass" below.

8. **Score every surviving finding** against the anchors below:
   - Assign a **severity** (Critical/High/Medium/Low) using the "Severity Rubric".
   - Assign a **confidence** (High/Medium/Low) using the "Confidence Scale", and
     drop or explicitly flag findings below the reporting threshold.

9. **Generate report** with:
   - Surviving findings ranked most-severe first, each carrying its
     `severity`, `confidence`, and verified `file:line`
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

## Severity Rubric

Score every surviving finding against these anchors. Rank the report
most-severe first.

| Severity | Criteria |
|----------|----------|
| **Critical** | Exploitable security hole, data loss/corruption, or a crash on a common path. Ship-blocker — must fix before merge. |
| **High** | A real correctness bug that misbehaves on realistic input, a serious perf regression (N+1, unbounded growth), or an auth/validation gap without a known exploit. Fix before merge. |
| **Medium** | Bug on an edge case, missing error handling, a test gap over important behavior, or a maintainability problem that will bite soon. Fix or file a follow-up. |
| **Low** | Style, naming, minor readability, or a nit with no behavioral impact. Optional. |

## Confidence Scale

Assign each finding a confidence and let it gate what reaches the report. A
finding whose defect you cannot demonstrate from the code in front of you is a
guess, and guesses erode trust in the review.

| Confidence | Meaning | Reporting rule |
|------------|---------|----------------|
| **High** | The defect is provable from the cited code — you can name the input and the wrong result. | Report. |
| **Medium** | The defect is likely but depends on context you could not fully see. | Report, labeled as needing confirmation. |
| **Low** | Speculative — a hunch not grounded in the code as read. | Drop, or downgrade to a one-line "consider checking X" note; never present as a defect. |

The reporting threshold is **Medium**: report High and Medium findings; do not
present Low-confidence hunches as findings.

## Re-verification Pass

Before the report step, re-check every candidate finding against the actual
code. This kills false positives mechanically rather than trusting the initial
read:

1. Re-open the finding's `file:line` with `Read` and confirm the cited code
   still says what the finding claims (line numbers drift; assumptions decay).
2. Confirm the failure the finding describes is reachable — name the concrete
   input or state that triggers it. If you cannot, it is Low confidence.
3. Keep only findings that survive both checks. Every reported finding must
   carry a verified `file:line`, a severity, and a confidence.

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
