---
created: 2025-12-16
modified: 2026-04-25
reviewed: 2026-04-25
allowed-tools: Task, TodoWrite
args: "[--api] [--readme] [--changelog]"
argument-hint: "[--api] [--readme] [--changelog]"
description: |
  Generate or update project documentation from code annotations, docstrings, type signatures,
  and git history. Use when the user wants to generate API reference docs, update the README
  from code analysis, produce a CHANGELOG from conventional commits, or mentions "generate
  docs", "update documentation", "API reference", or "regenerate changelog". Delegates to the
  documentation agent for multi-language extraction.
name: docs-generate
agent: general-purpose
---

## When to Use This Skill

| Use this skill when... | Use docs-sync instead when... |
|---|---|
| Generating fresh API reference docs from docstrings, type signatures, and module structure | Reconciling existing skill/command/agent catalogs with the current codebase |
| Updating README.md from code analysis (installation steps, feature list, badges) | Fixing wrong counts or stale entries in CLAUDE.md / README catalogs |
| Producing a CHANGELOG from conventional-commit history | Preparing a service teardown checklist (use docs-decommission) |
| Building documentation pages that will be served via GitHub Pages or similar | Converting Markdown to print-ready PDF (use docs-latex) |

## Context

- Project files: !`find . -maxdepth 1 \( -name 'pyproject.toml' -o -name 'package.json' -o -name 'Cargo.toml' -o -name 'go.mod' \)`
- Existing docs: !`find . -maxdepth 1 \( -name 'README.md' -o -type d -name 'docs' \)`
- Source files: !`find . -type f \( -name "*.py" -o -name "*.ts" -o -name "*.js" \)`
- Python with docstrings: !`grep -r "\"\"\"" --include="*.py" -l`

## Parameters

- `--api`: Generate API reference documentation
- `--readme`: Update README.md based on code analysis
- `--changelog`: Update CHANGELOG.md from git history

## Your task

**Delegate this task to the `documentation` agent.**

Use the Agent tool with `subagent_type: documentation` to generate or update project documentation. Pass all the context gathered above and the parsed parameters to the agent.

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

## Agent Teams (Optional)

For large projects, spawn teammates for parallel documentation generation:

| Teammate | Focus | Value |
|----------|-------|-------|
| API docs teammate | Extract and generate API reference | Parallel with README generation |
| README teammate | Update project README and guides | Parallel with API docs |
| Changelog teammate | Generate changelog from git history | Independent of other doc tasks |

This is optional — the skill works with a single agent for most projects.
