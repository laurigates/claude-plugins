---
allowed-tools: Task, TodoWrite
argument-hint: [--api] [--readme] [--changelog]
description: Update project documentation from code annotations
---

## Context

- Project type: !`ls -la pyproject.toml package.json Cargo.toml go.mod 2>/dev/null | head -1`
- Existing docs: !`ls -la README.md docs/ 2>/dev/null`
- Source files: !`find . -type f \( -name "*.py" -o -name "*.ts" -o -name "*.js" \) | head -10`
- Docstrings sample: !`grep -r "\"\"\"" --include="*.py" -l 2>/dev/null | head -3`

## Parameters

- `--api`: Generate API reference documentation
- `--readme`: Update README.md based on code analysis
- `--changelog`: Update CHANGELOG.md from git history

## Your task

**Delegate this task to the `documentation` agent.**

Use the Task tool with `subagent_type: documentation` to generate or update project documentation. Pass all the context gathered above and the parsed parameters to the agent.

The documentation agent should:

1. **Analyze codebase**:
   - Extract docstrings and type annotations
   - Identify public API surface
   - Map module structure and dependencies
   - Find usage examples in tests

2. **Generate requested documentation**:

   If `--api`:
   - Create API reference from docstrings
   - Document function signatures and types
   - Include usage examples
   - Generate module hierarchy

   If `--readme`:
   - Update project description
   - Document installation steps
   - Add usage examples
   - Update feature list
   - Ensure badges are current

   If `--changelog`:
   - Parse conventional commits
   - Group by version/release
   - Categorize by type (feat, fix, docs, etc.)
   - Include breaking changes prominently

   If no flags: Generate all documentation

3. **Follow documentation standards**:
   - Clear, concise language
   - Consistent formatting
   - Working code examples
   - Accurate cross-references

4. **Output summary**:
   - Files created/updated
   - Documentation coverage metrics
   - Suggested improvements

Provide the agent with:
- All context from the section above
- The parsed parameters
- Detected documentation framework (if any)

The agent has expertise in:
- Multi-language documentation extraction
- API reference generation
- README best practices
- Changelog automation from commits
- GitHub Pages integration
