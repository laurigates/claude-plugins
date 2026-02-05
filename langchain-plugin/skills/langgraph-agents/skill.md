---
model: opus
name: LangGraph Agents
description: |
  Build stateful AI agents using LangGraph's graph-based workflow framework. Use when
  you want to create an agent with checkpointed state, define agent behavior as a graph
  of nodes and edges, add human-in-the-loop approval steps, or compose multiple agents
  as subgraphs in a LangGraph application.
allowed-tools: Bash(python *), Bash(uv *), BashOutput, Read, Write, Edit, Grep, Glob, TodoWrite
created: 2026-01-08
modified: 2026-02-05
reviewed: 2026-01-08
---

# LangGraph Agents

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

## Checkpointing (Persistence)

### Memory Checkpointer

```typescript
import { MemorySaver } from "@langchain/langgraph";

const checkpointer = new MemorySaver();

const graph = new StateGraph(StateAnnotation)
  .addNode("agent", agentNode)
  .compile({ checkpointer });

// Invoke with thread_id for persistence
const config = { configurable: { thread_id: "user-123" } };

await graph.invoke({ messages: [userMessage] }, config);

// Continue conversation in same thread
await graph.invoke({ messages: [anotherMessage] }, config);
```

### SQLite Checkpointer

```typescript
import { SqliteSaver } from "@langchain/langgraph-checkpoint-sqlite";

const checkpointer = SqliteSaver.fromConnString("./checkpoints.db");

const graph = workflow.compile({ checkpointer });
```

### Get State History

```typescript
// Get current state
const state = await graph.getState(config);

// Get state history (time travel)
const history = await graph.getStateHistory(config);
for await (const snapshot of history) {
  console.log(snapshot.values, snapshot.next);
}
```

## Human-in-the-Loop

### Interrupt Before Node

```typescript
const graph = new StateGraph(StateAnnotation)
  .addNode("agent", agentNode)
  .addNode("tools", toolsNode)
  .compile({
    checkpointer,
    interruptBefore: ["tools"],  // Pause before running tools
  });

// First invocation stops before tools
const result1 = await graph.invoke(input, config);
// result1.next === ["tools"]

// User reviews, then continue
const result2 = await graph.invoke(null, config);
```

### Interrupt After Node

```typescript
const graph = workflow.compile({
  checkpointer,
  interruptAfter: ["agent"],  // Pause after agent responds
});
```

### Update State

```typescript
// Modify state during interrupt
await graph.updateState(config, {
  messages: [new HumanMessage("Actually, do X instead")],
});

// Continue with modified state
await graph.invoke(null, config);
```

## Streaming

### Stream Events

```typescript
const stream = await graph.stream(
  { messages: [userMessage] },
  { streamMode: "values" }
);

for await (const state of stream) {
  console.log(state.messages[state.messages.length - 1]);
}
```

### Stream Updates

```typescript
const stream = await graph.stream(
  { messages: [userMessage] },
  { streamMode: "updates" }
);

for await (const update of stream) {
  // { nodeId: { ...stateUpdate } }
  console.log(update);
}
```

### Stream Messages

```typescript
const stream = await graph.stream(
  { messages: [userMessage] },
  { streamMode: "messages" }
);

for await (const [message, metadata] of stream) {
  if (message.content) {
    process.stdout.write(message.content);
  }
}
```

## Subgraphs

### Define Subgraph

```typescript
const researchGraph = new StateGraph(ResearchState)
  .addNode("search", searchNode)
  .addNode("summarize", summarizeNode)
  .addEdge(START, "search")
  .addEdge("search", "summarize")
  .addEdge("summarize", END)
  .compile();

// Use as node in parent graph
const parentGraph = new StateGraph(ParentState)
  .addNode("research", researchGraph)
  .addNode("write", writeNode)
  .addEdge(START, "research")
  .addEdge("research", "write")
  .addEdge("write", END)
  .compile();
```

## Long-Term Memory (Store)

```typescript
import { InMemoryStore } from "@langchain/langgraph";

const store = new InMemoryStore();

const graph = workflow.compile({
  checkpointer,
  store,
});

// In nodes, access store via config
async function agentNode(
  state: State,
  config: RunnableConfig
): Promise<Partial<State>> {
  const store = config.store;

  // Get memories for user
  const memories = await store.search(["user", userId]);

  // Save new memory
  await store.put(["user", userId], memoryId, { content: "..." });

  return { ... };
}
```

## Common Patterns

### Tool Execution Loop

```typescript
const graph = new StateGraph(StateAnnotation)
  .addNode("agent", agentNode)
  .addNode("tools", toolsNode)
  .addEdge(START, "agent")
  .addConditionalEdges("agent", (state) => {
    const last = state.messages[state.messages.length - 1];
    return last.tool_calls?.length ? "tools" : END;
  })
  .addEdge("tools", "agent")
  .compile();
```

### Multi-Agent Workflow

```typescript
const graph = new StateGraph(StateAnnotation)
  .addNode("researcher", researcherAgent)
  .addNode("writer", writerAgent)
  .addNode("reviewer", reviewerAgent)
  .addEdge(START, "researcher")
  .addEdge("researcher", "writer")
  .addEdge("writer", "reviewer")
  .addConditionalEdges("reviewer", (state) => {
    return state.approved ? END : "writer";
  })
  .compile();
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
