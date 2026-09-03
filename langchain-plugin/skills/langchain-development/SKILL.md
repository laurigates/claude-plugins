---
name: langchain-development
description: LangChain JS/TS framework for building LLM-powered apps. Use when working with chat models, prompt templates, LCEL chains, tool binding, or RAG pipelines.
user-invocable: false
allowed-tools: Bash(python *), Bash(uv *), Read, Write, Edit, Grep, Glob, TodoWrite
created: 2026-01-08
modified: 2026-09-02
reviewed: 2026-09-02
---

# LangChain Development

## When to Use This Skill

| Use this skill when... | Use a sibling skill instead when... |
|---|---|
| Building LCEL chains (prompt → model → parser) or RAG pipelines | You need stateful graph workflows — use `langgraph-agents` |
| Working with chat models, prompt templates, or tool binding | You need hierarchical multi-agent orchestration — use `deep-agents` |
| Adding LangChain to an existing TypeScript project | You are scaffolding a brand-new project — use `langchain-init` (`/langchain:init`) |
| Implementing document loaders and vector stores | You only need a one-off SDK call without LangChain — use the provider SDK directly |

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
// Use a real, current model id (never an unversioned alias like "claude-haiku"),
// and omit sampling params — Fable-generation models reject temperature/top_p/top_k.
const anthropic = new ChatAnthropic({
  model: "claude-haiku-4-5",
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

For TypeScript configuration, tool definition and binding, RAG pipelines, and ReAct agents, see [REFERENCE.md](REFERENCE.md).
