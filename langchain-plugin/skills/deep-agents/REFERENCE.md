# Deep Agents - Reference

Custom tools, persistence, full configuration options, multi-agent subagent patterns, context-management strategy, streaming, and the Claude Code comparison.

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

## Comparison to Claude Code

| Feature | Deep Agents | Claude Code |
|---------|-------------|-------------|
| Planning | `write_todos` | `TodoWrite` (off by default on Opus 4.8+/Sonnet 5/Fable; enable with `CLAUDE_CODE_ENABLE_TODO_TOOLS=1`) |
| Subagents | `task` | `Task` |
| File ops | `read/write/edit_file` | `Read/Write/Edit` |
| Memory | LangGraph Store | Conversation context |
| Model | Configurable | Claude |
