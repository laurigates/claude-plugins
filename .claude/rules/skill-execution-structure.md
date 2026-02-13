# Skill Execution Structure

User-invocable skills must be structured so the model **executes immediately** upon invocation, rather than summarizing or narrating the skill content.

## The Problem: Narration Instead of Execution

When a skill reads like a specification document, the model summarizes what it could do instead of doing it. This is the most common skill authoring mistake.

**Symptoms:**
- Model loads the skill and says "I see this skill handles X, Y, Z. What would you like me to do?"
- Model describes the phases/steps instead of executing them
- Model asks the user to choose an action that the skill already defines

## Anti-Patterns

### Phase-based narration

```markdown
## Workflow

### Phase 1: Current State Detection

Check for existing configuration:

| File | Purpose | Status |
|------|---------|--------|
| `.config.json` | Project config | EXISTS / MISSING |

### Phase 2: Analysis

For existing config, analyze:
- [ ] File exists and is valid JSON
- [ ] Required fields present
```

This reads as a description of what phases exist, not as instructions to execute.

### Descriptive checklists

```markdown
**Currently Installed Servers:**
List each server with:
- Name
- Command type
- Required environment variables
- Status (configured / missing)
```

This describes what to list without commanding the model to actually do it.

## Correct Pattern

### Imperative execution directive

Start the execution section with a clear command:

```markdown
## Execution

Execute this configuration workflow:

### Step 1: Detect current state

Read `.config.json` and check if it exists:

1. If exists, parse and validate JSON structure
2. If missing, note for creation in Step 3
```

### Key structural elements

| Element | Purpose | Example |
|---------|---------|---------|
| Imperative opener | Tells model to act NOW | "Execute this workflow:", "Run this check:" |
| `## Context` with backticks | Auto-populates runtime state | `!`\``git status --porcelain`\`` |
| `## Parameters` | Defines argument parsing | "Parse `$ARGUMENTS` for flags:" |
| `## Execution` or `## Your task` | The action section | "Execute this X workflow:" |
| Numbered steps with verbs | Actionable instructions | "1. Read the config file", "2. Validate the JSON" |

### Context section with runtime detection

```markdown
## Context

- Config file: !`test -f .mcp.json && echo "EXISTS" || echo "MISSING"`
- Current servers: !`cat .mcp.json 2>/dev/null | jq -r '.mcpServers | keys[]' 2>/dev/null`
- Git tracking: !`grep -q '.mcp.json' .gitignore 2>/dev/null && echo "IGNORED" || echo "NOT IGNORED"`
```

This gives the model actual data to work with rather than telling it to go discover state.

### Parameter parsing section

```markdown
## Parameters

Parse these from `$ARGUMENTS`:

- `--check-only`: Report status without making changes
- `--fix`: Apply changes without prompting
- `--server <name>`: Target specific server (repeatable)
```

## Restructuring Workflow

When fixing an affected skill:

1. **Add `## Context` with backtick commands** — auto-detect state before execution
2. **Add `## Parameters`** — explicit argument parsing instructions
3. **Replace `## Workflow` with `## Execution`** — use imperative opener
4. **Change "Phase N:" to "Step N:" with verb** — "Step 1: Detect state" not "Phase 1: State Detection"
5. **Move reference data to REFERENCE.md** — JSON configs, full option tables, example reports
6. **Keep execution steps concise** — each step says what to DO, references REFERENCE.md for details

## Reference Data Extraction

Large data blocks interrupt the execution flow. Move them to `REFERENCE.md`:

| Keep in SKILL.md | Move to REFERENCE.md |
|-------------------|---------------------|
| Step-by-step execution flow | Full server configuration JSON blobs |
| Inline decision logic | Complete environment variable tables |
| Quick reference flags table | Example report templates |
| Core server list (2-3 items) | Full server registry |

Reference with: `Use server configurations from [REFERENCE.md](REFERENCE.md).`

## Before/After Example

**Before (narrates):**
```markdown
## Workflow

### Phase 1: Detection
Check if config exists.

### Phase 2: Analysis
Analyze current configuration.

### Phase 3: Report
Generate compliance report.
```

**After (executes):**
```markdown
## Execution

Execute this configuration check:

### Step 1: Detect current state

Read `.config.json`. If it exists, proceed to Step 2. If missing, report "No configuration found" and offer to create one.

### Step 2: Analyze configuration

Parse the JSON and validate:
1. Check for required `servers` key
2. List each server with its status
3. Flag missing environment variables

### Step 3: Report results

Print a summary table of findings and recommend fixes.
```

## Checklist

- [ ] Has imperative opener ("Execute this...", "Run this...", "Perform this...")
- [ ] Uses `## Context` with backtick commands for runtime detection
- [ ] Uses `## Parameters` for argument parsing
- [ ] Uses `## Execution` or `## Your task` (not `## Workflow`)
- [ ] Steps use imperative verbs ("Read", "Check", "Create", "Parse")
- [ ] Reference data extracted to REFERENCE.md
- [ ] Execution section is the first major section after Context/Parameters
