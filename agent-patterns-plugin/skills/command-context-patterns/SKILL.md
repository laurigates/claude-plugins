---
name: command-context-patterns
description: |
  Write safe context expressions in Claude Code slash command files. Covers
  backtick expressions, find vs ls patterns, and commands that always exit 0.
  Use when creating slash commands, writing context sections with backtick
  expressions, or debugging command execution failures.
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
