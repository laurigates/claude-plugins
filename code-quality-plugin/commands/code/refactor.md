---
allowed-tools: Task, TodoWrite
argument-hint: <file-path|directory>
description: Refactor code following SOLID principles and best practices
---

## Context

- Target path: !`echo "$1"`
- File type: !`file "$1" 2>/dev/null || echo "directory or not found"`
- Lines of code: !`wc -l "$1" 2>/dev/null || find "$1" -type f \( -name "*.py" -o -name "*.js" -o -name "*.ts" \) -exec wc -l {} + 2>/dev/null | tail -1`

## Parameters

- `$1`: Required file path or directory to refactor

## Your task

**Delegate this task to the `code-refactoring` agent.**

Use the Task tool with `subagent_type: code-refactoring` to refactor the specified code. Pass all the context gathered above to the agent.

The code-refactoring agent should:

1. **Identify refactoring opportunities**:
   - Long methods that should be extracted
   - Large classes that need decomposition
   - Duplicated code patterns
   - Feature envy and primitive obsession
   - Complex conditional logic

2. **Apply SOLID principles**:
   - Single Responsibility Principle
   - Open/Closed Principle
   - Liskov Substitution Principle
   - Interface Segregation Principle
   - Dependency Inversion Principle

3. **Apply best practices**:
   - DRY (Don't Repeat Yourself)
   - KISS (Keep It Simple)
   - Extract methods for clarity
   - Introduce meaningful abstractions

4. **Preserve functionality**:
   - Ensure all existing tests pass
   - Maintain the external API contract
   - No behavioral changes

5. **Output the refactored code** with clear structure

Provide the agent with:
- The target file or directory path
- The detected programming language
- Any style guide examples from the project

The agent has expertise in:
- Behavior-preserving code transformations
- Design pattern application
- Code smell detection and remediation
- Semantic code search for similar patterns
