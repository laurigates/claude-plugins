---
model: opus
created: 2025-12-16
modified: 2025-12-16
reviewed: 2025-12-16
allowed-tools: Read, Write, Edit, MultiEdit, Glob, Grep, TodoWrite
argument-hint: <project-path>
description: Analyze and assimilate project-specific Claude configurations
name: meta-assimilate
---

# Assimilate Command

Examine the .claude/{agents,commands} of the project at path [path] and think deep if we could make use of them in the user scoped agents and commands. Either by copying and generalizing or assimilating into existing agents or commands if similar ones already exist.
