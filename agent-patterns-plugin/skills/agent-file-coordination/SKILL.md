---
model: haiku
created: 2025-12-16
modified: 2025-12-16
reviewed: 2025-12-16
name: agent-file-coordination
description: |
  File-based context sharing for multi-agent workflows. Provides directory
  organization, agent output templates, progress tracking, and inter-agent context.
  Use when setting up multi-agent workflows, reading/writing agent context files,
  or maintaining workflow transparency with file-based coordination.
---

# Agent File Coordination

## Description

File-based context sharing and coordination structures for multi-agent workflows. Provides standardized directory organization, file formats, and templates for transparent agent coordination and human inspection.

## When to Use

Automatically apply this skill when:
- Setting up multi-agent workflows
- Reading/writing agent context files
- Monitoring agent progress
- Debugging agent coordination
- Sharing data between agents
- Maintaining workflow transparency

## Directory Organization

### Standard Structure
```
~/.claude/
├── tasks/              # Workflow coordination
│   ├── current-workflow.md      # Active workflow status
│   ├── agent-queue.md           # Agent scheduling & dependencies
│   └── inter-agent-context.json # Structured cross-agent data
│
├── docs/               # Agent outputs & results
│   ├── {agent}-output.md        # Standardized agent results
│   └── agent-output-template.md # Template for consistency
│
└── status/             # Real-time progress
    └── {agent}-progress.md      # Live status updates
```

[... rest of the file content - see source file for complete content]

## References

- Related Skills: `agent-coordination-patterns`
- Related Commands: Multi-agent workflow commands
- Replaces: `agent-context-management` (file structure sections)
