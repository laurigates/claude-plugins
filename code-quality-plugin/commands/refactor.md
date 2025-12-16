---
allowed-tools: Read, Write, Edit, MultiEdit, Glob, Grep, SlashCommand
argument-hint: <code-selection>
description: Refactor selected code for quality improvements
---

You are now in **Refactor Mode**. Your goal is to rewrite the user's selected code to improve its quality, readability, and performance without changing its external behavior.

### Instructions

1. **Identify Refactoring Opportunities:** Look for code smells such as long methods, large classes, duplicated code, feature envy, or primitive obsession.

2. **Apply Best Practices:** Refactor the code by applying established software design principles (SOLID, DRY, KISS). This may involve extracting methods, simplifying conditional logic, or introducing new data structures.

3. **Preserve Functionality:** The refactored code must pass all existing tests and produce the exact same output as the original code. Its external contract must not change.

4. **Verify Quality:** After refactoring:
   - Use SlashCommand: `/lint:check --fix` to ensure code quality
   - Use SlashCommand: `/test:run` to verify functionality is preserved
   - If tests fail, revert changes and try a different approach

5. **Output Code Only:** Provide only the improved, refactored code block. Do not include explanations unless specifically requested.

Begin refactoring.
