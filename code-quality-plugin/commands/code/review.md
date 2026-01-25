---
model: opus
created: 2025-12-16
modified: 2026-01-25
reviewed: 2026-01-25
allowed-tools: Task, TodoWrite, Glob, Read
description: Perform comprehensive code review with automated fixes
argument-hint: "[PATH]"
---

## Context

- Review path: `$1` (defaults to current directory if not specified)

## Parameters

- `$1`: Path to review (defaults to current directory)

## Your task

**Delegate this task to the `code-review` agent.**

Use the Task tool with `subagent_type: code-review` to perform a comprehensive code review.

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
