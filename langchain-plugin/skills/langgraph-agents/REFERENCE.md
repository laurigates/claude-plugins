# LangGraph Agents - Reference

Checkpointing backends, human-in-the-loop interrupts, streaming modes, subgraph composition, long-term memory, and composite graph patterns.

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
