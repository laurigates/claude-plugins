---
model: haiku
created: 2025-12-16
modified: 2026-02-05
reviewed: 2025-12-16
name: command-context-patterns
description: |
  Write the context section of Claude Code slash commands correctly. Use when you
  are creating a new slash command and need to add dynamic context using backtick
  shell expressions, your command's context section is failing or returning empty
  results, or you need to safely detect files and project state in command frontmatter.
---

# Command Context Patterns

Best practices for writing context expressions in Claude Code slash command files.

## Activation

Use this skill when:
- Creating or editing slash command files (`.claude/commands/**/*.md`)
- Writing context sections with backtick expressions (`!`...``)
- Debugging command execution failures related to bash expressions

## Safe Patterns

Context expressions must use commands that **always exit 0** regardless of results.

[Rest of content continues...]
