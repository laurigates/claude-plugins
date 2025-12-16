---
allowed-tools: Task, TodoWrite
description: Perform comprehensive code review with automated fixes
argument-hint: "[PATH]"
---

## Context

- Review path: !`echo "${1:-.}"`
- Files to review: !`find ${1:-.} -type f \( -name "*.py" -o -name "*.js" -o -name "*.ts" -o -name "*.go" -o -name "*.rs" \) 2>/dev/null | head -20`
- Test files: !`find ${1:-.} -type f -name "*test*" 2>/dev/null | wc -l`
- Project size: !`find ${1:-.} -type f -name "*.py" -o -name "*.js" -o -name "*.ts" -o -name "*.go" -o -name "*.rs" | xargs wc -l 2>/dev/null | tail -1`

## Parameters

- `$1`: Path to review (defaults to current directory)

## Your task

**Delegate this task to the `code-review` agent.**

Use the Task tool with `subagent_type: code-review` to perform a comprehensive code review. Pass all the context gathered above to the agent.

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
