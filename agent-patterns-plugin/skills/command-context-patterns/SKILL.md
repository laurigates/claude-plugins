---
model: haiku
created: 2025-12-16
modified: 2026-02-05
reviewed: 2025-12-16
name: command-context-patterns
description: |
  Write the context section of Claude Code skill templates correctly. Use when
  you are creating a new skill and need dynamic variables using backtick shell
  expressions, your skill's context section is failing or returning empty results,
  or you need to safely detect files and project state in skill frontmatter.
---

# Command Context Patterns

Best practices for writing context expressions in Claude Code slash command files.

## Activation

Use this skill when:
- Creating or editing slash command/skill files (`.claude/skills/**/*.md`)
- Writing context sections with backtick expressions (`!`...``)
- Debugging command execution failures related to bash expressions

## Safe Patterns

Context expressions must use commands that **always exit 0** regardless of results.

[Rest of content continues...]
