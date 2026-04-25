---
created: 2025-12-16
modified: 2026-04-25
reviewed: 2026-04-25
allowed-tools: Read, Write, Edit, MultiEdit, Glob, Grep, TodoWrite
args: <project-path>
argument-hint: <project-path>
description: |
  Analyze and assimilate project-specific Claude configurations into user-scoped agents and
  commands. Use when you want to examine a project's .claude/{agents,commands} directory and
  either copy, generalize, or merge useful agents and commands into your personal configuration,
  when the user mentions assimilating or adopting another project's Claude setup, or when
  looking to generalize a project-specific agent into a reusable one.
name: meta-assimilate
---

# Assimilate Command

## When to Use This Skill

| Use this skill when... | Use custom-agent-definitions instead when... |
|---|---|
| Examining another project's `.claude/{agents,commands}` to copy or generalise into user scope | Authoring a brand-new agent definition without an external source |
| Merging a project-specific agent into an existing user-scoped agent | Configuring tool access or context-fork for a single agent file |
| Deciding whether to adopt, generalise, or skip another project's Claude setup | Auditing existing agent definitions for security or completeness (use meta-audit) |

Examine the .claude/{agents,commands} of the project at path [path] and think deep if we could make use of them in the user scoped agents and commands. Either by copying and generalizing or assimilating into existing agents or commands if similar ones already exist.
