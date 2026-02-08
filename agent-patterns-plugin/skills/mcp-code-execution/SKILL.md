---
model: opus
name: MCP Code Execution Pattern
description: |
  Design and scaffold the code execution pattern for MCP-based agent systems. Use when
  building agents that interact with many MCP tools, when intermediate data is too large
  for model context, when you need loops/conditionals across tool calls, or when PII must
  stay out of the model context. Based on Anthropic's engineering guidance.
allowed-tools: Bash, Read, Write, Edit, Grep, Glob, TodoWrite
created: 2026-02-08
modified: 2026-02-08
reviewed: 2026-02-08
---

# MCP Code Execution Pattern

Expert knowledge for designing agent systems that generate and execute code to interact with MCP servers, instead of calling tools directly.

## When to Use This Pattern

| Use code execution when... | Use direct tool calls when... |
|----------------------------|-------------------------------|
| Connecting to 10+ MCP servers or 50+ tools | Few servers with handful of tools |
| Intermediate results are large (>10K tokens) | Results are small and all needed by the model |
| Workflows need loops, retries, or conditionals | Linear sequences of 2-3 tool calls |
| PII must not reach the model context | No sensitive data in tool responses |
| Tasks benefit from state persistence across runs | Stateless, one-shot operations |
| You want agents to accumulate reusable skills | Fixed, predefined workflows |

## Core Architecture

### How It Works

Instead of loading all MCP tool definitions into the model context upfront, the agent:

1. **Discovers** available tools by navigating a typed file tree
2. **Generates** TypeScript/Python code that imports and calls typed wrapper functions
3. **Executes** the code in a sandboxed environment
4. **Returns** only filtered/summarized results to the model

This reduces token usage from O(all_tool_definitions) to O(only_relevant_imports).

### File Tree Structure

```
project/
├── servers/
│   ├── google-drive/
│   │   ├── getDocument.ts
│   │   ├── getSheet.ts
│   │   ├── listFiles.ts
│   │   └── index.ts          # Re-exports all tools
│   ├── salesforce/
│   │   ├── query.ts
│   │   ├── updateRecord.ts
│   │   └── index.ts
│   └── slack/
│       ├── sendMessage.ts
│       ├── getChannelHistory.ts
│       └── index.ts
├── skills/                    # Agent-accumulated reusable functions
│   └── save-sheet-as-csv.ts
├── workspace/                 # Persistent state between executions
├── client.ts                  # MCP client that routes calls to servers
└── sandbox.config.ts          # Execution environment configuration
```

### Typed Wrapper Pattern

Each MCP tool gets a typed wrapper function that the agent imports:

```typescript
// servers/google-drive/getDocument.ts
import { callMCPTool } from "../../client.js";

interface GetDocumentInput {
  documentId: string;
}

interface GetDocumentResponse {
  content: string;
}

/** Read a document from Google Drive */
export async function getDocument(
  input: GetDocumentInput
): Promise<GetDocumentResponse> {
  return callMCPTool<GetDocumentResponse>("google_drive__get_document", input);
}
```

The agent then writes code that uses these wrappers naturally:

```typescript
import * as gdrive from "./servers/google-drive";
import * as salesforce from "./servers/salesforce";

const transcript = (
  await gdrive.getDocument({ documentId: "abc123" })
).content;

await salesforce.updateRecord({
  objectType: "SalesMeeting",
  recordId: "00Q5f000001abcXYZ",
  data: { Notes: transcript },
});
```

## Key Patterns

### 1. Progressive Tool Discovery

The agent navigates the filesystem to find relevant tools on demand, instead of loading all definitions upfront.

```
Agent: "I need to read from Google Drive"
  → ls servers/
  → ls servers/google-drive/
  → cat servers/google-drive/getDocument.ts  (reads signature + JSDoc)
  → generates code importing only getDocument
```

**Token impact**: 150,000 tokens (all definitions) reduced to ~2,000 tokens (one definition). 98.7% reduction.

### 2. Context-Efficient Data Filtering

Filter large datasets in the execution environment before results reach the model:

```typescript
// Filter in the sandbox — only summary reaches the model
const allRows = await gdrive.getSheet({ sheetId: "abc123" });
const pending = allRows.filter((row) => row["Status"] === "pending");
console.log(`Found ${pending.length} pending orders`);
console.log(pending.slice(0, 5)); // Only first 5 for model review
```

### 3. Native Control Flow

Replace chained tool calls with code-native loops and conditionals:

```typescript
// Polling loop — runs entirely in sandbox
let found = false;
while (!found) {
  const messages = await slack.getChannelHistory({ channel: "C123456" });
  found = messages.some((m) => m.text.includes("deployment complete"));
  if (!found) await new Promise((r) => setTimeout(r, 5000));
}
console.log("Deployment notification received");
```

### 4. PII Tokenization

The MCP client intercepts responses and tokenizes sensitive data before it reaches the model:

```typescript
// Agent writes this code
for (const row of sheet.rows) {
  await salesforce.updateRecord({
    objectType: "Lead",
    recordId: row.salesforceId,
    data: { Email: row.email, Phone: row.phone, Name: row.name },
  });
}
console.log(`Updated ${sheet.rows.length} leads`);
```

What the model sees in the execution output:

```
[
  { salesforceId: "00Q...", email: "[EMAIL_1]", phone: "[PHONE_1]", name: "[NAME_1]" },
  { salesforceId: "00Q...", email: "[EMAIL_2]", phone: "[PHONE_2]", name: "[NAME_2]" }
]
Updated 247 leads
```

The actual PII flows between external systems without entering model context.

### 5. State Persistence

Save intermediate results to the workspace for cross-execution continuity:

```typescript
// Execution 1: fetch and save
const leads = await salesforce.query({
  query: "SELECT Id, Email FROM Lead LIMIT 1000",
});
await fs.writeFile("./workspace/leads.csv", leads.map((l) => `${l.Id},${l.Email}`).join("\n"));

// Execution 2: resume from saved state
const saved = await fs.readFile("./workspace/leads.csv", "utf-8");
```

### 6. Skill Accumulation

Agents persist reusable functions as skills for future executions:

```typescript
// skills/save-sheet-as-csv.ts
import * as gdrive from "../servers/google-drive";
import * as fs from "fs/promises";

export async function saveSheetAsCsv(sheetId: string): Promise<string> {
  const data = await gdrive.getSheet({ sheetId });
  const csv = data.map((row) => row.join(",")).join("\n");
  const path = `./workspace/sheet-${sheetId}.csv`;
  await fs.writeFile(path, csv);
  return path;
}
```

Later executions import the skill directly:

```typescript
import { saveSheetAsCsv } from "./skills/save-sheet-as-csv";
const csvPath = await saveSheetAsCsv("abc123");
```

## Scaffolding a New Project

### Step 1: Identify MCP Servers

List the MCP servers the agent needs to interact with. Check `.mcp.json` or the project's MCP configuration:

```bash
cat .mcp.json 2>/dev/null || echo "No MCP config found"
```

### Step 2: Generate Server Directory

For each MCP server, create a directory with typed wrappers. Each tool gets its own file with:
- Input interface
- Output interface
- JSDoc comment describing the tool
- Async function wrapping `callMCPTool`

### Step 3: Create the MCP Client

The client routes `callMCPTool` calls to the appropriate MCP server:

```typescript
// client.ts
import { Client } from "@modelcontextprotocol/sdk/client/index.js";

const clients = new Map<string, Client>();

export async function callMCPTool<T>(
  toolName: string,
  input: Record<string, unknown>
): Promise<T> {
  const serverName = toolName.split("__")[0];
  const client = clients.get(serverName);
  if (!client) throw new Error(`No MCP client for server: ${serverName}`);

  const result = await client.callTool({ name: toolName, arguments: input });
  return result.content as T;
}
```

### Step 4: Configure the Sandbox

The execution environment needs:

| Concern | Requirement |
|---------|-------------|
| Isolation | Process-level or container-level sandboxing |
| Resource limits | CPU time, memory caps, disk quotas |
| Network | Restrict to MCP server connections only |
| Timeout | Hard execution time limit per run |
| Filesystem | Scoped to `workspace/` and `servers/` directories |
| Monitoring | Log all executions and MCP calls |

### Step 5: Wire Up the Agent Loop

The agent loop becomes:

```
1. Receive user request
2. Agent explores servers/ tree to find relevant tools
3. Agent generates TypeScript code using typed wrappers
4. Code executes in sandbox
5. Filtered output returns to agent
6. Agent decides: done, or generate more code?
```

## Security Checklist

| Item | Status |
|------|--------|
| Sandboxed execution environment | Required |
| Resource limits (CPU, memory, disk) | Required |
| Network isolation (MCP servers only) | Required |
| Execution timeout | Required |
| PII tokenization in MCP client | Recommended for sensitive data |
| Audit logging of all executions | Recommended |
| Read-only access to `servers/` | Recommended |
| Scoped write access to `workspace/` only | Recommended |

## Agentic Optimizations

| Context | Approach |
|---------|----------|
| Many tools (50+) | Use progressive discovery via file tree |
| Large intermediate data | Filter in sandbox, return summaries |
| Multi-step workflows | Generate single code block with control flow |
| Sensitive data pipelines | Enable PII tokenization in MCP client |
| Long-running tasks | Use workspace/ for state persistence |
| Repeated operations | Extract to skills/ for reuse |

## Quick Reference

### Token Impact

| Approach | Tool definitions | Intermediate data | Total |
|----------|-----------------|-------------------|-------|
| Direct tool calls | All loaded upfront | Passes through context | High |
| Code execution | On-demand discovery | Stays in sandbox | Low |

### When NOT to Use This Pattern

- Simple integrations with 1-3 MCP servers
- All tool responses are small and needed by the model
- No sensitive data in tool responses
- Infrastructure complexity isn't justified (sandbox setup, monitoring)
- Prototype or proof-of-concept stage

### Reference

- [Anthropic Engineering: Code Execution with MCP](https://www.anthropic.com/engineering/code-execution-with-mcp)
- [Cloudflare "Code Mode"](https://blog.cloudflare.com/) — independent validation of the same pattern
