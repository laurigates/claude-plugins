# langchain-plugin

LangChain JS/TS development skills for building AI agents, chains, and workflows with LangGraph.

## Skills

| Skill | Description |
|-------|-------------|
| `langchain-development` | Core LangChain patterns - models, chains, tools, RAG |
| `langgraph-agents` | Graph-based stateful agents with persistence |
| `deep-agents` | Complex agents with planning and subagent delegation |
| `langchain-init` | Scaffold a new LangChain TypeScript project |

## When to Use

### langchain-development
- Building LLM applications with TypeScript/JavaScript
- Creating chains and pipelines
- Implementing RAG (Retrieval-Augmented Generation)
- Integrating tools with language models

### langgraph-agents
- Multi-step agent workflows
- Human-in-the-loop interactions
- Persistent conversations with checkpointing
- Complex routing and conditional logic

### deep-agents
- Long-running research or coding tasks
- Tasks requiring planning and decomposition
- Large context management (files, documents)
- Multi-agent orchestration

## Quick Start

```bash
# Initialize a new project
/langchain:init my-agent

# Or manually install
npm install langchain @langchain/core @langchain/langgraph @langchain/openai
```

## Example: Simple Agent

```typescript
import { ChatOpenAI } from "@langchain/openai";
import { createReactAgent } from "@langchain/langgraph/prebuilt";

const agent = createReactAgent({
  llm: new ChatOpenAI({ model: "gpt-4o" }),
  tools: [myTool],
});

const result = await agent.invoke({
  messages: [{ role: "user", content: "Hello!" }],
});
```

## Example: Persistent Agent

```typescript
import { MemorySaver } from "@langchain/langgraph";

const checkpointer = new MemorySaver();
const agent = createReactAgent({
  llm: model,
  tools: [myTool],
  checkpointer,
});

// Conversations persist across calls
const config = { configurable: { thread_id: "user-123" } };
await agent.invoke(input, config);
```

## Resources

- [LangChain JS Docs](https://js.langchain.com)
- [LangGraph Docs](https://langchain-ai.github.io/langgraphjs/)
- [LangSmith](https://smith.langchain.com) - Observability and debugging
