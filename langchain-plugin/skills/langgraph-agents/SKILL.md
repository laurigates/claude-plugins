---
name: langgraph-agents
description: LangGraph stateful AI agents with graph-based workflows. Use when creating state-machine agents with checkpoints, human-in-the-loop, streaming execution, or subgraph composition.
user-invocable: false
allowed-tools: Bash(python *), Bash(uv *), Read, Write, Edit, Grep, Glob, TodoWrite
created: 2026-01-08
modified: 2026-05-09
reviewed: 2026-04-25
---

# LangGraph Agents

## When to Use This Skill

| Use this skill when... | Use a sibling skill instead when... |
|---|---|
| Building stateful agents as graphs of nodes/edges with checkpointing | Writing simple LCEL chains without state — use `langchain-development` |
| Adding human-in-the-loop approval, streaming, or time-travel debugging | Doing basic tool binding without a graph — use `langchain-development` |
| Composing multi-agent systems as subgraphs | Needing hierarchical planning + file-system context — use `deep-agents` |
| Wiring graphs into an initialised project | Scaffolding a brand-new project — use `langchain-init` (`/langchain:init`) |

## Core Expertise

LangGraph is a low-level orchestration framework for stateful agents:
- Graph-based workflow definition (nodes and edges)
- Durable execution with checkpointing
- Human-in-the-loop interactions
- Short-term and long-term memory
- Streaming and time-travel debugging
- LangSmith observability integration

## Installation

```bash
# Core LangGraph package
npm install @langchain/langgraph

# Required dependencies
npm install @langchain/core
npm install @langchain/openai  # or your preferred model provider

# Optional: Checkpointing backends
npm install @langchain/langgraph-checkpoint-sqlite
```

## Graph Fundamentals

### State Definition

```typescript
import { Annotation, StateGraph } from "@langchain/langgraph";

// Define state schema using Annotation
const StateAnnotation = Annotation.Root({
  messages: Annotation<BaseMessage[]>({
    reducer: (prev, next) => [...prev, ...next],
    default: () => [],
  }),
  currentStep: Annotation<string>({
    reducer: (_, next) => next,
    default: () => "start",
  }),
});

type State = typeof StateAnnotation.State;
```

### Basic Graph

```typescript
import { StateGraph, START, END } from "@langchain/langgraph";

const graph = new StateGraph(StateAnnotation)
  .addNode("agent", agentNode)
  .addNode("tools", toolsNode)
  .addEdge(START, "agent")
  .addConditionalEdges("agent", routeAgent)
  .addEdge("tools", "agent")
  .compile();
```

### Nodes

```typescript
// Nodes are async functions that receive and return state
async function agentNode(state: State): Promise<Partial<State>> {
  const response = await model.invoke(state.messages);
  return {
    messages: [response],
  };
}

async function toolsNode(state: State): Promise<Partial<State>> {
  const lastMessage = state.messages[state.messages.length - 1];
  const toolCalls = lastMessage.tool_calls || [];

  const results = await Promise.all(
    toolCalls.map(tc => tools[tc.name].invoke(tc.args))
  );

  return {
    messages: results.map((r, i) =>
      new ToolMessage({ content: r, tool_call_id: toolCalls[i].id })
    ),
  };
}
```

### Conditional Edges

```typescript
function routeAgent(state: State): string {
  const lastMessage = state.messages[state.messages.length - 1];

  if (lastMessage.tool_calls?.length) {
    return "tools";
  }
  return END;
}

// Add conditional routing
graph.addConditionalEdges("agent", routeAgent, {
  tools: "tools",
  [END]: END,
});
```

## Prebuilt Agents

### ReAct Agent

```typescript
import { createReactAgent } from "@langchain/langgraph/prebuilt";
import { ChatOpenAI } from "@langchain/openai";

const model = new ChatOpenAI({ model: "gpt-4o" });

const agent = createReactAgent({
  llm: model,
  tools: [searchTool, calculatorTool],
});

// Run the agent
const result = await agent.invoke({
  messages: [{ role: "user", content: "What's the weather in NYC?" }],
});
```

### With System Prompt

```typescript
const agent = createReactAgent({
  llm: model,
  tools: [searchTool],
  stateModifier: "You are a helpful research assistant.",
});
```

## Agentic Optimizations

| Context | Pattern |
|---------|---------|
| Quick iteration | Use `MemorySaver` for development |
| Production | Use `SqliteSaver` or external DB |
| Debug state | `graph.getState(config)` |
| Time travel | `graph.getStateHistory(config)` |
| Trace execution | Enable `LANGCHAIN_TRACING_V2` |
| Reduce tokens | Stream updates, not full state |
| Human approval | `interruptBefore: ["dangerous_node"]` |

## Quick Reference

### Core Imports

| Import | Package |
|--------|---------|
| `StateGraph` | `@langchain/langgraph` |
| `Annotation` | `@langchain/langgraph` |
| `START, END` | `@langchain/langgraph` |
| `MemorySaver` | `@langchain/langgraph` |
| `createReactAgent` | `@langchain/langgraph/prebuilt` |

### Graph Methods

| Method | Description |
|--------|-------------|
| `.addNode(id, fn)` | Add a node |
| `.addEdge(from, to)` | Add unconditional edge |
| `.addConditionalEdges(from, fn)` | Add conditional routing |
| `.compile()` | Build executable graph |
| `.invoke(input, config)` | Run to completion |
| `.stream(input, config)` | Stream execution |
| `.getState(config)` | Get current state |
| `.updateState(config, update)` | Modify state |

### Stream Modes

| Mode | Output |
|------|--------|
| `"values"` | Full state after each step |
| `"updates"` | Only changed values |
| `"messages"` | Message chunks for streaming UI |
| `"debug"` | Detailed execution info |

### Config Options

| Option | Description |
|--------|-------------|
| `thread_id` | Conversation/session ID |
| `checkpoint_id` | Specific checkpoint to resume |
| `recursion_limit` | Max graph iterations (default: 25) |

For checkpointing backends, human-in-the-loop interrupts, streaming modes, subgraph composition, long-term memory, and composite graph patterns, see [REFERENCE.md](REFERENCE.md).
