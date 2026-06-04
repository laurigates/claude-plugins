---
name: deep-agents
description: Build hierarchical AI agents with the deepagents npm package. Use when creating orchestrators that plan multi-step tasks, delegate to child agents, or maintain persistent memory.
user-invocable: false
allowed-tools: Bash(python *), Bash(uv *), BashOutput, Read, Write, Edit, Grep, Glob, TodoWrite
created: 2026-01-08
modified: 2026-06-04
reviewed: 2026-06-04
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

## Custom Tools

Custom tools use the standard LangChain `tool()` helper and are passed via the
`tools` option.

```typescript
import { createDeepAgent } from "deepagents";
import { tool } from "@langchain/core/tools";
import { z } from "zod";

const searchTool = tool(
  async ({ query }) => {
    // Implement search
    return JSON.stringify(results);
  },
  {
    name: "web_search",
    description: "Search the web for information",
    schema: z.object({
      query: z.string().describe("Search query"),
    }),
  }
);

const agent = createDeepAgent({
  model,
  tools: [searchTool],  // Add custom tools alongside the built-ins
});
```

## Persistent Memory

Deep Agents inherits LangGraph's `store` for cross-thread memory. Pass a store
instance to `createDeepAgent` and address conversations by `thread_id`.

```typescript
import { createDeepAgent } from "deepagents";
import { InMemoryStore } from "@langchain/langgraph";

const store = new InMemoryStore();

const agent = createDeepAgent({
  model,
  store,
});

// One thread writes memories...
const config = { configurable: { thread_id: "session-1" } };
await agent.invoke(input, config);

// ...a later thread can retrieve them.
const config2 = { configurable: { thread_id: "session-2" } };
await agent.invoke(input2, config2);
```

## Checkpointing

```typescript
import { createDeepAgent } from "deepagents";
import { MemorySaver } from "@langchain/langgraph";

const checkpointer = new MemorySaver();

const agent = createDeepAgent({
  model,
  checkpointer,
});

// Resume interrupted workflows by reusing the thread_id
const config = { configurable: { thread_id: "long-task" } };

// First run (may be interrupted)
await agent.invoke(input, config);

// Resume from checkpoint
await agent.invoke(null, config);
```

## Configuration Options

```typescript
const agent = createDeepAgent({
  // Model — provider-prefixed string ("openai:gpt-5") or a model instance
  model,

  // Behaviour
  systemPrompt: "You are...",

  // Tools — added alongside the built-in file/planning/task tools
  tools: [customTool1, customTool2],

  // Delegation — typed SubAgent definitions (see Multi-Agent Patterns)
  subagents: [researchSubagent, writerSubagent],

  // Persistence (LangGraph)
  checkpointer,
  store,
});
```

## Multi-Agent Patterns

Subagents are plain objects matching the `SubAgent` shape: `name`, `description`,
and `systemPrompt` are required; `tools` and `model` are optional overrides.

### Supervisor Pattern

```typescript
import type { SubAgent } from "deepagents";

const researchSubagent: SubAgent = {
  name: "researcher",
  description: "Researches topics thoroughly",
  systemPrompt: "You research topics thoroughly...",
};

const writerSubagent: SubAgent = {
  name: "writer",
  description: "Writes clear, concise content",
  systemPrompt: "You write clear, concise content...",
};

const supervisorAgent = createDeepAgent({
  model,
  systemPrompt: `You coordinate research and writing.
    Delegate research to the researcher.
    Delegate writing to the writer.
    Review and iterate until quality is high.`,
  subagents: [researchSubagent, writerSubagent],
});
```

### Specialized Subagents

```typescript
// Subagents can override the model and carry their own tools.
const codeSubagent: SubAgent = {
  name: "coder",
  description: "Writes and tests code",
  systemPrompt: "You write and test code...",
  tools: [runTestsTool, lintTool],
};

const searchSubagent: SubAgent = {
  name: "searcher",
  description: "Searches and synthesizes information",
  systemPrompt: "You search and synthesize information...",
  tools: [webSearchTool],
  model: "openai:gpt-5-mini",
};
```

## Context Management Strategy

```typescript
// Deep Agents pattern: Use files to manage context

// 1. Read source material
// read_file({ path: "docs/requirements.md" })

// 2. Write intermediate results
// write_file({
//   path: "scratch/analysis.md",
//   content: "## Analysis\n..."
// })

// 3. Read back when needed
// read_file({ path: "scratch/analysis.md" })

// 4. Write final output
// write_file({
//   path: "output/report.md",
//   content: "# Final Report\n..."
// })
```

## Streaming

The compiled graph supports LangGraph streaming.

```typescript
const stream = await agent.stream(
  { messages: [userMessage] },
  { streamMode: "messages" }
);

for await (const [message, metadata] of stream) {
  if (message.content) {
    process.stdout.write(message.content);
  }
  if (metadata.langgraph_node === "tools") {
    console.log("\n[Tool executed]");
  }
}
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

## Comparison to Claude Code

| Feature | Deep Agents | Claude Code |
|---------|-------------|-------------|
| Planning | `write_todos` | `TodoWrite` |
| Subagents | `task` | `Task` |
| File ops | `read/write/edit_file` | `Read/Write/Edit` |
| Memory | LangGraph Store | Conversation context |
| Model | Configurable | Claude |
