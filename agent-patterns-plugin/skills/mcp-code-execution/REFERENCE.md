# MCP Code Execution — Reference

Supporting material for [`mcp-code-execution`](SKILL.md). Loaded on demand. The
decision tables, architecture overview, and checklists live in `SKILL.md`; this
file carries the typed-wrapper code, the six key-pattern examples, and the
project scaffolding steps.

## Typed wrapper pattern

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

## Key patterns

### 1. Progressive tool discovery

The agent navigates the filesystem to find relevant tools on demand instead of
loading all definitions upfront.

```
Agent: "I need to read from Google Drive"
  → ls servers/
  → ls servers/google-drive/
  → cat servers/google-drive/getDocument.ts  (reads signature + JSDoc)
  → generates code importing only getDocument
```

**Token impact**: 150,000 tokens (all definitions) reduced to ~2,000 tokens (one
definition). 98.7% reduction.

### 2. Context-efficient data filtering

Filter large datasets in the execution environment before results reach the model:

```typescript
const allRows = await gdrive.getSheet({ sheetId: "abc123" });
const pending = allRows.filter((row) => row["Status"] === "pending");
console.log(`Found ${pending.length} pending orders`);
console.log(pending.slice(0, 5)); // Only first 5 for model review
```

### 3. Native control flow

Replace chained tool calls with code-native loops and conditionals:

```typescript
let found = false;
while (!found) {
  const messages = await slack.getChannelHistory({ channel: "C123456" });
  found = messages.some((m) => m.text.includes("deployment complete"));
  if (!found) await new Promise((r) => setTimeout(r, 5000));
}
console.log("Deployment notification received");
```

### 4. PII tokenization

The MCP client intercepts responses and tokenizes sensitive data before it
reaches the model:

```typescript
for (const row of sheet.rows) {
  await salesforce.updateRecord({
    objectType: "Lead",
    recordId: row.salesforceId,
    data: { Email: row.email, Phone: row.phone, Name: row.name },
  });
}
console.log(`Updated ${sheet.rows.length} leads`);
```

What the model sees:

```
[
  { salesforceId: "00Q...", email: "[EMAIL_1]", phone: "[PHONE_1]", name: "[NAME_1]" },
  { salesforceId: "00Q...", email: "[EMAIL_2]", phone: "[PHONE_2]", name: "[NAME_2]" }
]
Updated 247 leads
```

The actual PII flows between external systems without entering model context.

### 5. State persistence

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

### 6. Skill accumulation

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

## Scaffolding a new project

### Step 1: Identify MCP servers

List the MCP servers the agent needs. Check `.mcp.json`:

```bash
cat .mcp.json 2>/dev/null || echo "No MCP config found"
```

### Step 2: Generate server directory

For each MCP server, create a directory with typed wrappers. Each tool gets its
own file with an input interface, output interface, JSDoc comment, and an async
function wrapping `callMCPTool`.

### Step 3: Create the MCP client

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

### Step 4: Configure the sandbox

| Concern | Requirement |
|---------|-------------|
| Isolation | Process-level or container-level sandboxing |
| Resource limits | CPU time, memory caps, disk quotas |
| Network | Restrict to MCP server connections only |
| Timeout | Hard execution time limit per run |
| Filesystem | Scoped to `workspace/` and `servers/` directories |
| Monitoring | Log all executions and MCP calls |

### Step 5: Wire up the agent loop

```
1. Receive user request
2. Agent explores servers/ tree to find relevant tools
3. Agent generates TypeScript code using typed wrappers
4. Code executes in sandbox
5. Filtered output returns to agent
6. Agent decides: done, or generate more code?
```
