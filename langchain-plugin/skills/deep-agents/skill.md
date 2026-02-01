---
model: opus
name: Deep Agents
description: Deep Agents library for building complex, multi-step AI agents with planning, context management, and subagent delegation.
allowed-tools: Bash(python *), Bash(uv *), BashOutput, Read, Write, Edit, Grep, Glob, TodoWrite
created: 2026-01-08
modified: 2026-01-08
reviewed: 2026-01-08
---

# Deep Agents

## Core Expertise

Deep Agents is a TypeScript library for building sophisticated AI agents:
- Built on LangGraph with planning and decomposition
- File system context management (prevents token overflow)
- Subagent delegation for focused exploration
- Persistent memory across conversations
- Modeled after Claude Code and Deep Research patterns

## When to Use Deep Agents

| Use Deep Agents | Use Standard LangChain |
|-----------------|----------------------|
| Multi-step planning required | Simple Q&A or single tool |
| Large context (files, docs) | Small, bounded context |
| Subtask delegation needed | Linear tool execution |
| Long-running workflows | Quick, stateless calls |

## Installation

```bash
# Install Deep Agents
npm install @langchain/deep-agents

# Required peer dependencies
npm install @langchain/langgraph @langchain/core
npm install @langchain/openai  # or your model provider
```

## Basic Agent Setup

```typescript
import { DeepAgent } from "@langchain/deep-agents";
import { ChatOpenAI } from "@langchain/openai";

const model = new ChatOpenAI({
  model: "gpt-4o",
  temperature: 0,
});

const agent = new DeepAgent({
  llm: model,
  name: "research-agent",
  systemPrompt: `You are a research assistant.
    Break complex questions into steps using write_todos.
    Use read_file and write_file to manage context.`,
});

const result = await agent.invoke({
  messages: [{ role: "user", content: "Research X and summarize" }],
});
```

## Built-in Tools

### Planning Tools

```typescript
// write_todos - Task decomposition
// Automatically available in Deep Agents

// Agent uses it to plan:
// write_todos([
//   { task: "Search for X", status: "pending" },
//   { task: "Analyze results", status: "pending" },
//   { task: "Write summary", status: "pending" },
// ])
```

### File System Tools

```typescript
// Built-in tools for context management

// ls - List directory contents
// read_file - Read file content
// write_file - Write/create files
// edit_file - Modify existing files

// Agent stores intermediate results in files
// to prevent context overflow
```

### Subagent Delegation

```typescript
// task - Spawn focused subagent

// Parent agent delegates:
// task({
//   description: "Research pricing models",
//   instructions: "Find and compare...",
// })

// Subagent runs independently and returns results
```

## Custom Tools

```typescript
import { DeepAgent } from "@langchain/deep-agents";
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

const agent = new DeepAgent({
  llm: model,
  tools: [searchTool],  // Add custom tools
});
```

## Persistent Memory

### Using LangGraph Store

```typescript
import { DeepAgent } from "@langchain/deep-agents";
import { InMemoryStore } from "@langchain/langgraph";

const store = new InMemoryStore();

const agent = new DeepAgent({
  llm: model,
  store,
  memoryNamespace: ["user", "research"],
});

// Agent can save/retrieve memories across threads
const config = { configurable: { thread_id: "session-1" } };
await agent.invoke(input, config);

// Later session retrieves memories
const config2 = { configurable: { thread_id: "session-2" } };
await agent.invoke(input2, config2);
```

### Memory Patterns

```typescript
// Agent saves learned patterns:
// save_memory({
//   key: "api-design-patterns",
//   content: "Always use REST conventions...",
// })

// Agent retrieves before responding:
// recall_memories({ query: "API design" })
```

## Checkpointing

```typescript
import { MemorySaver } from "@langchain/langgraph";

const checkpointer = new MemorySaver();

const agent = new DeepAgent({
  llm: model,
  checkpointer,
});

// Resume interrupted workflows
const config = { configurable: { thread_id: "long-task" } };

// First run (may be interrupted)
await agent.invoke(input, config);

// Resume from checkpoint
await agent.invoke(null, config);
```

## Configuration Options

```typescript
const agent = new DeepAgent({
  // Required
  llm: model,

  // Identity
  name: "my-agent",
  systemPrompt: "You are...",

  // Tools
  tools: [customTool1, customTool2],
  enableFileTools: true,      // ls, read, write, edit
  enablePlanningTools: true,  // write_todos
  enableSubagents: true,      // task delegation

  // Memory
  store: memoryStore,
  memoryNamespace: ["project", "agent-name"],

  // Persistence
  checkpointer: checkpointer,

  // Limits
  maxIterations: 50,
  maxTokens: 100000,
});
```

## Multi-Agent Patterns

### Supervisor Pattern

```typescript
const researchAgent = new DeepAgent({
  llm: model,
  name: "researcher",
  systemPrompt: "You research topics thoroughly...",
});

const writerAgent = new DeepAgent({
  llm: model,
  name: "writer",
  systemPrompt: "You write clear, concise content...",
});

const supervisorAgent = new DeepAgent({
  llm: model,
  name: "supervisor",
  systemPrompt: `You coordinate research and writing.
    Delegate research to the researcher.
    Delegate writing to the writer.
    Review and iterate until quality is high.`,
  subagents: [researchAgent, writerAgent],
});
```

### Specialized Agents

```typescript
// Code agent with file tools
const codeAgent = new DeepAgent({
  llm: model,
  name: "coder",
  tools: [runTestsTool, lintTool],
  enableFileTools: true,
  systemPrompt: "You write and test code...",
});

// Research agent with search
const searchAgent = new DeepAgent({
  llm: model,
  name: "searcher",
  tools: [webSearchTool],
  enableFileTools: true,
  systemPrompt: "You search and synthesize information...",
});
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
| Focused work | Delegate via `task` tool |
| Long sessions | Enable checkpointing |
| Learned patterns | Store in persistent memory |
| Debug | Enable `LANGCHAIN_TRACING_V2` |
| Token limits | Set `maxTokens` config |

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
| `task` | Delegate to subagent |
| `save_memory` | Persist knowledge |
| `recall_memories` | Retrieve knowledge |

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
