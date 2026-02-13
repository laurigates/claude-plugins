---
model: haiku
name: langchain-development
description: LangChain JS/TS framework for building LLM-powered applications - models, chains, tools, and RAG patterns.
allowed-tools: Bash(python *), Bash(uv *), BashOutput, Read, Write, Edit, Grep, Glob, TodoWrite
created: 2026-01-08
modified: 2026-01-08
reviewed: 2026-01-08
---

# LangChain Development

## Core Expertise

LangChain JS/TS is a framework for building LLM applications:

- Unified interface across model providers (OpenAI, Anthropic, Google, etc.)
- Composable chains and agents
- Built-in tool integration
- RAG (Retrieval-Augmented Generation) support
- LangSmith observability integration

## Installation

### Package Manager Setup

```bash
# Core package
npm install langchain
# or
pnpm add langchain
# or
bun add langchain

# Model provider packages (install what you need)
npm install @langchain/openai
npm install @langchain/anthropic
npm install @langchain/google-genai

# Common integrations
npm install @langchain/community  # Community integrations
npm install @langchain/textsplitters  # Document splitting
```

### TypeScript Configuration

```json
{
  "compilerOptions": {
    "target": "ES2020",
    "module": "NodeNext",
    "moduleResolution": "NodeNext",
    "esModuleInterop": true,
    "strict": true
  }
}
```

## Chat Models

### Basic Usage

```typescript
import { ChatOpenAI } from "@langchain/openai";
import { ChatAnthropic } from "@langchain/anthropic";
import { HumanMessage, SystemMessage } from "@langchain/core/messages";

// OpenAI
const openai = new ChatOpenAI({
  model: "gpt-4o",
  temperature: 0,
});

// Anthropic
const anthropic = new ChatAnthropic({
  model: "claude-haiku",
  temperature: 0,
});

// Invoke with messages
const response = await openai.invoke([
  new SystemMessage("You are a helpful assistant."),
  new HumanMessage("Hello!"),
]);
```

### Streaming

```typescript
const stream = await openai.stream([new HumanMessage("Tell me a story")]);

for await (const chunk of stream) {
  process.stdout.write(chunk.content as string);
}
```

### Structured Output

```typescript
import { z } from "zod";

const schema = z.object({
  name: z.string().describe("The name"),
  age: z.number().describe("The age"),
});

const structuredLlm = openai.withStructuredOutput(schema);
const result = await structuredLlm.invoke("John is 30 years old");
// { name: "John", age: 30 }
```

## Prompt Templates

### Basic Templates

```typescript
import { ChatPromptTemplate } from "@langchain/core/prompts";

const prompt = ChatPromptTemplate.fromMessages([
  ["system", "You are a {role}."],
  ["human", "{input}"],
]);

const formatted = await prompt.invoke({
  role: "helpful assistant",
  input: "Hello!",
});
```

### Few-Shot Prompts

```typescript
import { FewShotChatMessagePromptTemplate } from "@langchain/core/prompts";

const examples = [
  { input: "2+2", output: "4" },
  { input: "3+3", output: "6" },
];

const fewShotPrompt = new FewShotChatMessagePromptTemplate({
  examplePrompt: ChatPromptTemplate.fromMessages([
    ["human", "{input}"],
    ["ai", "{output}"],
  ]),
  examples,
  inputVariables: ["input"],
});
```

## Chains (LCEL)

### Basic Chain

```typescript
import { ChatOpenAI } from "@langchain/openai";
import { ChatPromptTemplate } from "@langchain/core/prompts";
import { StringOutputParser } from "@langchain/core/output_parsers";

const prompt = ChatPromptTemplate.fromTemplate("Tell me a joke about {topic}");
const model = new ChatOpenAI();
const parser = new StringOutputParser();

// Chain with pipe operator
const chain = prompt.pipe(model).pipe(parser);

const result = await chain.invoke({ topic: "programming" });
```

### Parallel Chains

```typescript
import { RunnableParallel } from "@langchain/core/runnables";

const parallel = RunnableParallel.from({
  joke: jokeChain,
  poem: poemChain,
});

const results = await parallel.invoke({ topic: "cats" });
// { joke: "...", poem: "..." }
```

### Branching

```typescript
import { RunnableBranch } from "@langchain/core/runnables";

const branch = RunnableBranch.from([
  [(x) => x.type === "math", mathChain],
  [(x) => x.type === "code", codeChain],
  defaultChain, // Fallback
]);
```

## Tools

### Defining Tools

```typescript
import { tool } from "@langchain/core/tools";
import { z } from "zod";

const calculatorTool = tool(
  async ({ a, b, operation }) => {
    switch (operation) {
      case "add":
        return String(a + b);
      case "subtract":
        return String(a - b);
      case "multiply":
        return String(a * b);
      case "divide":
        return String(a / b);
    }
  },
  {
    name: "calculator",
    description: "Performs basic arithmetic",
    schema: z.object({
      a: z.number(),
      b: z.number(),
      operation: z.enum(["add", "subtract", "multiply", "divide"]),
    }),
  },
);
```

### Tool Binding

```typescript
const modelWithTools = model.bindTools([calculatorTool]);

const response = await modelWithTools.invoke("What is 25 * 4?");

// Check for tool calls
if (response.tool_calls?.length) {
  const toolCall = response.tool_calls[0];
  const result = await calculatorTool.invoke(toolCall.args);
}
```

## RAG (Retrieval-Augmented Generation)

### Document Loading

```typescript
import { TextLoader } from "langchain/document_loaders/fs/text";
import { PDFLoader } from "@langchain/community/document_loaders/fs/pdf";
import { RecursiveCharacterTextSplitter } from "@langchain/textsplitters";

// Load documents
const loader = new TextLoader("./data/document.txt");
const docs = await loader.load();

// Split into chunks
const splitter = new RecursiveCharacterTextSplitter({
  chunkSize: 1000,
  chunkOverlap: 200,
});
const splitDocs = await splitter.splitDocuments(docs);
```

### Vector Store

```typescript
import { MemoryVectorStore } from "langchain/vectorstores/memory";
import { OpenAIEmbeddings } from "@langchain/openai";

const embeddings = new OpenAIEmbeddings();
const vectorStore = await MemoryVectorStore.fromDocuments(
  splitDocs,
  embeddings,
);

// Search
const results = await vectorStore.similaritySearch("query", 4);
```

### RAG Chain

```typescript
import { createRetrievalChain } from "langchain/chains/retrieval";
import { createStuffDocumentsChain } from "langchain/chains/combine_documents";

const retriever = vectorStore.asRetriever({ k: 4 });

const combineDocsChain = await createStuffDocumentsChain({
  llm: model,
  prompt: ChatPromptTemplate.fromTemplate(`
    Answer based on this context:
    {context}

    Question: {input}
  `),
});

const ragChain = await createRetrievalChain({
  retriever,
  combineDocsChain,
});

const response = await ragChain.invoke({
  input: "What is the document about?",
});
```

## Agents (ReAct)

### Basic Agent

```typescript
import { createReactAgent } from "@langchain/langgraph/prebuilt";

const agent = createReactAgent({
  llm: model,
  tools: [calculatorTool, searchTool],
});

const result = await agent.invoke({
  messages: [{ role: "user", content: "Calculate 25 * 4" }],
});
```

## Agentic Optimizations

| Context         | Command/Pattern                        |
| --------------- | -------------------------------------- |
| Quick test      | `npx tsx --test src/**/*.test.ts`      |
| Type check      | `npx tsc --noEmit`                     |
| Debug traces    | Set `LANGCHAIN_TRACING_V2=true`        |
| Reduce tokens   | Use `StringOutputParser` for text-only |
| Stream output   | Use `.stream()` instead of `.invoke()` |
| Batch requests  | Use `.batch([inputs])` for parallel    |
| Cache responses | Use `InMemoryCache` for repeated calls |

## Quick Reference

### Environment Variables

| Variable               | Description              |
| ---------------------- | ------------------------ |
| `OPENAI_API_KEY`       | OpenAI API key           |
| `ANTHROPIC_API_KEY`    | Anthropic API key        |
| `LANGCHAIN_TRACING_V2` | Enable LangSmith tracing |
| `LANGCHAIN_API_KEY`    | LangSmith API key        |
| `LANGCHAIN_PROJECT`    | LangSmith project name   |

### Common Imports

| Import               | Package                          |
| -------------------- | -------------------------------- |
| `ChatOpenAI`         | `@langchain/openai`              |
| `ChatAnthropic`      | `@langchain/anthropic`           |
| `ChatPromptTemplate` | `@langchain/core/prompts`        |
| `StringOutputParser` | `@langchain/core/output_parsers` |
| `tool`               | `@langchain/core/tools`          |
| `RunnableSequence`   | `@langchain/core/runnables`      |

### Key Packages

| Package                | Purpose                |
| ---------------------- | ---------------------- |
| `langchain`            | Core framework         |
| `@langchain/core`      | Base abstractions      |
| `@langchain/openai`    | OpenAI integration     |
| `@langchain/anthropic` | Anthropic integration  |
| `@langchain/community` | Community integrations |
| `@langchain/langgraph` | Graph-based agents     |
