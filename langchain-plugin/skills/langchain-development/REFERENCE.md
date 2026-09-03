# LangChain Development - Reference

TypeScript configuration, tool definition and binding, RAG pipelines (loaders, vector stores, retrieval chains), and ReAct agents.

## TypeScript Configuration

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
