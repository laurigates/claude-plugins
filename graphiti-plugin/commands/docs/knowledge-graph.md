---
allowed-tools: Read, Glob, Task, TodoWrite, mcp__graphiti-memory__add_memory, mcp__graphiti-memory__search_memory_nodes, mcp__graphiti-memory__search_memory_facts
argument-hint: [vault-directory]
description: Build comprehensive knowledge graph from Obsidian vault documentation
---

# Build Knowledge Graph

Build a comprehensive knowledge graph from technical documentation files in an Obsidian vault's z/ directory.

## Usage

```bash
claude build-knowledge-graph
```

## What it does

This command systematically processes all files in the z/ directory of your current Obsidian vault and commits their summaries and relationships to the memory system using the memory-keeper agent. It:

1. **Scans** all documentation files in the z/ directory
2. **Processes** them in logical groups (AI/Automation, Infrastructure, DevOps, Security, etc.)
3. **Extracts** key entities, relationships, and technical specifications
4. **Builds** a comprehensive knowledge graph for semantic search and pattern recognition
5. **Preserves** architectural decisions, integration points, and operational context

## Output

- Complete knowledge graph stored in memory with group_id "fvh-technical-docs"
- Rich entity relationships for cross-referencing technologies and projects
- Enables intelligent queries about system dependencies and technical patterns

## Requirements

- Must be run from an Obsidian vault directory containing a z/ subdirectory
- Memory-keeper agent must be available
- Files should be technical documentation in Markdown format

## Example Use Cases

- Building institutional knowledge from years of technical documentation
- Creating searchable relationships between projects and technologies
- Preserving architectural decisions and their rationale
- Enabling intelligent queries about system dependencies
