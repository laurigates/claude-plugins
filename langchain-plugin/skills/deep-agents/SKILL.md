---
name: deep-agents
description: Build hierarchical AI agents with the deepagents npm package. Use when creating orchestrators that plan multi-step tasks, delegate to child agents, or maintain persistent memory.
user-invocable: false
allowed-tools: Bash(python *), Bash(uv *), Read, Write, Edit, Grep, Glob, TodoWrite
created: 2026-01-08
modified: 2026-09-02
reviewed: 2026-09-02
---

# Deep Agents

## When to Use This Skill

| Use this skill when... | Use `langgraph-agents` instead when... |
|---|---|
| Building hierarchical agents with planning and subagent delegation | You need a single stateful graph without sub-agents |
| Managing large context via file-system memory across runs | Short-lived state fits in checkpointed graph memory |
| Long-running, multi-step workflows modelled on Deep Research | Simple LCEL chains suffice (use `langchain-development`) |
| Scaffolding from scratch (use `/langchain:init` first) | The project is already initialised and only needs graph wiring |

## Core Expertise

Deep Agents (`deepagents`) is a TypeScript library for building sophisticated AI agents:
- Built on LangGraph with planning and decomposition
- File system context management (prevents token overflow)
- Subagent delegation for focused exploration
- Persistent memory across conversations
- Modeled after Claude Code and Deep Research patterns

The package name on npm is **`deepagents`** (one word, unscoped). The source lives at [langchain-ai/deepagentsjs](https://github.com/langchain-ai/deepagentsjs).

## Installation

```bash
# Install Deep Agents
npm install deepagents

# Add a model provider (pick the one matching your model)
npm install @langchain/openai  # or @langchain/anthropic, @langchain/google-genai
```

`deepagents` declares `langsmith` as a peer dependency (for tracing) and builds on
`@langchain/langgraph` + `@langchain/core`, which are pulled in transitively.

## Basic Agent Setup

`createDeepAgent()` returns a compiled LangGraph graph. The model can be a
provider-prefixed string (e.g. `"openai:gpt-5"`) or a model instance.

```typescript
import { createDeepAgent } from "deepagents";
import { ChatOpenAI } from "@langchain/openai";

const model = new ChatOpenAI({
  model: "gpt-5",
  temperature: 0,
});

const agent = createDeepAgent({
  model,
  systemPrompt: `You are a research assistant.
    Break complex questions into steps using write_todos.
    Use read_file and write_file to manage context.`,
});

const result = await agent.invoke({
  messages: [{ role: "user", content: "Research X and summarize" }],
});
```

For browser or Node-explicit builds, import the backend-scoped entrypoints:

```typescript
import { createDeepAgent, StateBackend } from "deepagents/browser";
import { createDeepAgent, FilesystemBackend } from "deepagents/node";
```

## Built-in Tools

Deep Agents ships these tools automatically: `write_todos`, `ls`, `read_file`,
`write_file`, `edit_file`, `glob`, `grep`, and `task`.

### Planning Tools

```typescript
// write_todos - Task decomposition (available automatically)

// The agent uses it to plan:
// write_todos([
//   { task: "Search for X", status: "pending" },
//   { task: "Analyze results", status: "pending" },
//   { task: "Write summary", status: "pending" },
// ])
```

### File System Tools

```typescript
// Built-in tools for context management

// ls        - List directory contents
// read_file - Read file content
// write_file - Write/create files
// edit_file - Modify existing files
// glob      - Match files by pattern
// grep      - Search file contents

// The agent stores intermediate results in files
// to prevent context overflow.
```

### Subagent Delegation

```typescript
// task - Spawn a focused subagent with an isolated context window

// The parent agent delegates:
// task({
//   description: "Research pricing models",
//   subagent_type: "research-agent",
// })

// The subagent runs independently and returns results.
```

## Agentic Optimizations

| Context | Pattern |
|---------|---------|
| Large docs | Write to file, read sections as needed |
| Multi-step | Use `write_todos` to track progress |
| Focused work | Delegate via the `task` tool |
| Long sessions | Enable checkpointing |
| Learned patterns | Store via LangGraph `store` |
| Debug | Enable `LANGCHAIN_TRACING_V2` |

## Quick Reference

### Agent Methods

| Method | Description |
|--------|-------------|
| `.invoke(input, config)` | Run to completion |
| `.stream(input, config)` | Stream execution |
| `.batch(inputs, config)` | Parallel execution |

### Built-in Tools

| Tool | Purpose |
|------|---------|
| `write_todos` | Plan and track tasks |
| `ls` | List directory |
| `read_file` | Read file contents |
| `write_file` | Create/overwrite file |
| `edit_file` | Modify file section |
| `glob` | Match files by pattern |
| `grep` | Search file contents |
| `task` | Delegate to a subagent |

### Config Keys

| Key | Description |
|-----|-------------|
| `thread_id` | Conversation ID |
| `checkpoint_id` | Resume point |
| `recursion_limit` | Max iterations |

### Environment Variables

| Variable | Description |
|----------|-------------|
| `LANGCHAIN_TRACING_V2` | Enable LangSmith |
| `LANGCHAIN_API_KEY` | LangSmith key |
| `LANGCHAIN_PROJECT` | Project name |

For custom tools, persistence, full configuration options, multi-agent subagent patterns, context-management strategy, streaming, and the Claude Code comparison, see [REFERENCE.md](REFERENCE.md).
