---
created: 2025-12-16
modified: 2026-09-02
compatibility: claude-code
reviewed: 2026-09-02
allowed-tools: Read, Write, Edit, MultiEdit, Glob, Grep, TodoWrite
model: opus
args: <project-path>
argument-hint: <project-path>
description: Copy, generalize, or merge a project's .claude/{agents,commands} into user-scoped configuration. Use when assimilating another project's Claude setup or generalizing an agent.
name: meta-assimilate
---

# Assimilate Command

## When to Use This Skill

| Use this skill when... | Use custom-agent-definitions instead when... |
|---|---|
| Examining another project's `.claude/{agents,commands}` to copy or generalise into user scope | Authoring a brand-new agent definition without an external source |
| Merging a project-specific agent into an existing user-scoped agent | Configuring tool access or context-fork for a single agent file |
| Deciding whether to adopt, generalise, or skip another project's Claude setup | Auditing existing agent definitions for security or completeness (use meta-audit) |

Examine the `.claude/{agents,commands}` of the project at [path] and decide, for each one, whether it is worth adopting into the user-scoped agents and commands — by copying and generalising it, or by folding it into an existing user-scoped agent or command that already covers the same job.
