---
model: haiku
description: Initialize a new LangChain TypeScript project with recommended configuration
args: [project-name]
allowed-tools: Bash(uv *), Bash(pip *), Bash(python *), Read, Write, Edit
argument-hint: my-agent-project
created: 2026-01-08
modified: 2026-01-08
reviewed: 2026-01-08
---

# /langchain:init

Initialize a new LangChain TypeScript project with optimal configuration for building AI agents.

## Context

Detect the environment:
- `node --version` - Node.js version
- `which bun` - Check if Bun is available

## Parameters

| Parameter | Description | Default |
|-----------|-------------|---------|
| `project-name` | Name of the project directory | Required |

## Execution

### 1. Create Project Directory

```bash
mkdir -p $1 && cd $1
```

### 2. Initialize Package

If Bun is available:
```bash
bun init -y
```

Otherwise:
```bash
npm init -y
```

### 3. Install Dependencies

Core packages:
```bash
# Package manager: bun or npm
bun add langchain @langchain/core @langchain/langgraph
bun add @langchain/openai  # Default model provider

# Dev dependencies
bun add -d typescript @types/node tsx
```

### 4. Create TypeScript Config

Create `tsconfig.json`:
```json
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "NodeNext",
    "moduleResolution": "NodeNext",
    "esModuleInterop": true,
    "strict": true,
    "skipLibCheck": true,
    "outDir": "dist",
    "declaration": true
  },
  "include": ["src/**/*"],
  "exclude": ["node_modules", "dist"]
}
```

### 5. Create Project Structure

```bash
mkdir -p src
```

### 6. Create Example Agent

Create `src/agent.ts`:
```typescript
import { ChatOpenAI } from "@langchain/openai";
import { createReactAgent } from "@langchain/langgraph/prebuilt";
import { tool } from "@langchain/core/tools";
import { z } from "zod";

// Example tool
const greetTool = tool(
  async ({ name }) => `Hello, ${name}!`,
  {
    name: "greet",
    description: "Greet someone by name",
    schema: z.object({
      name: z.string().describe("The name to greet"),
    }),
  }
);

// Create the agent
const model = new ChatOpenAI({
  model: "gpt-4o",
  temperature: 0,
});

export const agent = createReactAgent({
  llm: model,
  tools: [greetTool],
});

// Run if executed directly
if (import.meta.url === `file://${process.argv[1]}`) {
  const result = await agent.invoke({
    messages: [{ role: "user", content: "Say hello to Claude" }],
  });
  console.log(result.messages[result.messages.length - 1].content);
}
```

### 7. Create Environment Template

Create `.env.example`:
```bash
# OpenAI (default)
OPENAI_API_KEY=sk-...

# Optional: Anthropic
# ANTHROPIC_API_KEY=sk-ant-...

# Optional: LangSmith tracing
# LANGCHAIN_TRACING_V2=true
# LANGCHAIN_API_KEY=ls__...
# LANGCHAIN_PROJECT=my-project
```

### 8. Update package.json Scripts

Add to `package.json`:
```json
{
  "scripts": {
    "dev": "tsx watch src/agent.ts",
    "start": "tsx src/agent.ts",
    "build": "tsc",
    "typecheck": "tsc --noEmit"
  }
}
```

### 9. Create .gitignore

```
node_modules/
dist/
.env
*.log
```

## Post-Actions

1. Display success message with next steps:
   - Copy `.env.example` to `.env` and add API key
   - Run `bun dev` or `npm run dev` to start
   - Check LangChain docs for more examples

2. Suggest installing additional model providers if needed:
   - `@langchain/anthropic` for Claude
   - `@langchain/google-genai` for Gemini
