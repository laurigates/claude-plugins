---
name: VectorCode Semantic Search
description: Semantic code search with VectorCode using embeddings for finding code by meaning, not just keywords. Use when searching for code patterns, similar implementations, concept-based search, or when keyword search fails. Automatically available via MCP.
allowed-tools: mcp__vectorcode, Read, Grep, Glob
---

# VectorCode Semantic Search

Expert knowledge for using VectorCode's semantic code search capabilities through MCP integration. VectorCode indexes code using embeddings, enabling searches based on meaning and context rather than exact keyword matches.

## Core Expertise

**Semantic Search**
- Find code by intent and meaning, not just keywords
- Discover similar implementations across codebases
- Locate related functionality without knowing exact names
- Cross-language concept search

**Index Management**
- List indexed projects and files
- Add new files to the index
- Remove outdated or irrelevant files
- Verify index coverage

**Query Optimization**
- Formulate effective semantic queries
- Combine with traditional search tools
- Balance recall vs precision
- Iterate queries based on results

## When to Use VectorCode

**✅ Use VectorCode when:**
- Searching by concept or intent ("authentication logic", "error handling patterns")
- Finding similar code without knowing exact function names
- Exploring unfamiliar codebases
- Discovering related functionality across modules
- Keyword search returns too many or irrelevant results
- Looking for implementation patterns

**❌ Use Grep/Glob instead when:**
- Searching for exact strings or identifiers
- Finding specific function/class names
- Locating file paths or extensions
- Simple pattern matching suffices
- Need complete exhaustive results

**🔀 Combine both when:**
- Initial semantic search to find areas of interest
- Follow up with grep for specific details
- Broad concept search, narrow with keywords

## Essential MCP Tools

### List Indexed Projects

```javascript
// Tool: mcp__vectorcode__ls
// Lists all projects that have been indexed by VectorCode

// Parameters: none
// Returns: List of project root paths

// Use this first to verify what's indexed
```

**When to use:**
- Starting work on a new machine
- Verifying project is indexed
- Choosing project_root for queries
- Troubleshooting missing results

### Query Code Semantically

```javascript
// Tool: mcp__vectorcode__query
// Performs semantic search across indexed code

{
  "n_query": 10,              // Number of results to return
  "query_messages": [         // Array of search keywords/phrases
    "authentication",
    "user login",
    "session management"
  ],
  "project_root": "/path/to/project"  // Must match indexed path
}
```

**Parameters:**
- `n_query` (number): Results to return (start with 10-20)
- `query_messages` (array): Distinct keywords or phrases
- `project_root` (string): Exact path from `ls` output

**Returns:**
- File paths with relevance scores
- Code snippets with context
- Line ranges for matches

### Add Files to Index

```javascript
// Tool: mcp__vectorcode__vectorise
// Adds files to VectorCode's embedding index

{
  "paths": [
    "/absolute/path/to/file1.py",
    "/absolute/path/to/file2.js"
  ],
  "project_root": "/path/to/project"
}
```

**When to use:**
- After creating new files
- When expanding index coverage
- After major code changes
- Before semantic search sessions

**Important:** Use absolute paths for files

### List Indexed Files

```javascript
// Tool: mcp__vectorcode__files_ls
// Lists all files indexed for a specific project

{
  "project_root": "/path/to/project"
}
```

**When to use:**
- Verifying what's indexed
- Checking coverage of modules
- Debugging missing results
- Planning index updates

### Remove Files from Index

```javascript
// Tool: mcp__vectorcode__files_rm
// Removes files from the index

{
  "files": [
    "/absolute/path/to/file1.py",
    "/absolute/path/to/file2.js"
  ],
  "project_root": "/path/to/project"
}
```

**When to use:**
- After deleting source files
- Removing generated/build files
- Cleaning up old code
- Reducing index size

## Query Formulation Best Practices

### Effective Query Keywords

**✅ Good queries:**
```javascript
// Concept-based
["database connection", "connection pooling"]

// Functional intent
["user authentication", "password validation"]

// Pattern-based
["error handling", "try catch", "exception"]

// Domain-specific
["HTTP request", "API endpoint", "REST"]
```

**❌ Poor queries:**
```javascript
// Too specific (use grep instead)
["function getUserById"]

// Single generic word
["data"]

// Implementation details (language-specific)
["async def", "try:"]
```

### Query Keywords Should Be:

1. **Conceptual, not literal**
   - ❌ "def authenticate"
   - ✅ "user authentication logic"

2. **Distinct and orthogonal**
   - ❌ ["login", "sign in", "authenticate"] (redundant)
   - ✅ ["authentication", "session", "authorization"] (different aspects)

3. **Multiple perspectives**
   - ✅ ["database", "persistence", "storage"] (covers concept broadly)

4. **Domain language**
   - ✅ ["HTTP request", "API client", "REST endpoint"]

### Iterative Query Refinement

```bash
# Round 1: Broad concept
query: ["authentication", "login"]
result: Too many results

# Round 2: Narrow with context
query: ["OAuth authentication", "token validation"]
result: Better, but missing some

# Round 3: Add related concepts
query: ["OAuth", "JWT token", "bearer authentication"]
result: Good coverage

# If still too broad, reduce n_query or use grep to filter
```

## Common Patterns

### Explore Unfamiliar Codebase

```javascript
// Step 1: List indexed projects
mcp__vectorcode__ls()

// Step 2: Broad exploration
mcp__vectorcode__query({
  n_query: 20,
  query_messages: ["main entry point", "application startup", "initialization"],
  project_root: "/path/to/project"
})

// Step 3: Follow specific area
mcp__vectorcode__query({
  n_query: 15,
  query_messages: ["database schema", "models", "ORM"],
  project_root: "/path/to/project"
})
```

### Find Similar Implementations

```javascript
// Looking for similar error handling
mcp__vectorcode__query({
  n_query: 10,
  query_messages: ["error handling", "exception management", "retry logic"],
  project_root: "/path/to/project"
})

// Looking for API patterns
mcp__vectorcode__query({
  n_query: 15,
  query_messages: ["REST API", "HTTP handler", "endpoint routing"],
  project_root: "/path/to/project"
})
```

### Cross-Module Search

```javascript
// Find authentication across different modules
mcp__vectorcode__query({
  n_query: 20,
  query_messages: ["authentication", "authorization", "access control"],
  project_root: "/path/to/project"
})

// Results will include frontend, backend, middleware, etc.
```

### Discover Dependencies

```javascript
// Find where external services are used
mcp__vectorcode__query({
  n_query: 15,
  query_messages: ["external API", "third party", "service integration"],
  project_root: "/path/to/project"
})

// Find database access patterns
mcp__vectorcode__query({
  n_query: 15,
  query_messages: ["database query", "SQL", "data access"],
  project_root: "/path/to/project"
})
```

### Locate Configuration

```javascript
// Find configuration handling
mcp__vectorcode__query({
  n_query: 10,
  query_messages: ["configuration", "settings", "environment variables"],
  project_root: "/path/to/project"
})
```

### Debug Feature Implementation

```javascript
// Find where feature is implemented
mcp__vectorcode__query({
  n_query: 15,
  query_messages: ["user registration", "signup", "account creation"],
  project_root: "/path/to/project"
})

// Then use grep for specific details
// grep -r "createUser" <files-from-vectorcode>
```

## Combining with Traditional Search

### Two-Stage Search Strategy

```bash
# Stage 1: VectorCode for discovery
# Broad semantic search to find relevant areas

mcp__vectorcode__query({
  n_query: 20,
  query_messages: ["payment processing", "transaction"],
  project_root: "/path/to/project"
})

# Results: src/payments/processor.py, src/api/checkout.py, ...

# Stage 2: Grep for specifics
# Now search specific files for exact patterns

grep -r "process_payment" src/payments/ src/api/
```

### Validation Pattern

```bash
# Use VectorCode to find candidates
# Use Grep to verify exact matches

# 1. Semantic search
vectorcode: "configuration loading"
# Returns: config.py, settings.py, env.py

# 2. Verify with grep
grep -l "load_config\|read_settings" config.py settings.py env.py
```

## Index Management Workflow

### Initial Setup

```bash
# 1. Check if project is indexed
mcp__vectorcode__ls()

# 2. If not indexed, run vectorcode init (see vectorcode-init command)
# This typically happens automatically via git hooks

# 3. Verify files are indexed
mcp__vectorcode__files_ls({project_root: "/path/to/project"})

# 4. Add missing files if needed
mcp__vectorcode__vectorise({
  paths: ["/path/to/new_file.py"],
  project_root: "/path/to/project"
})
```

### Maintain Index

```bash
# After major changes
# 1. Add new files
mcp__vectorcode__vectorise({
  paths: ["/path/to/new_module.py", "/path/to/new_util.js"],
  project_root: "/path/to/project"
})

# 2. Remove deleted files
mcp__vectorcode__files_rm({
  files: ["/path/to/old_file.py"],
  project_root: "/path/to/project"
})

# 3. For updated files, re-vectorize
# (removing and re-adding automatically re-indexes)
```

### Troubleshooting Missing Results

```bash
# Check if file is indexed
mcp__vectorcode__files_ls({project_root: "/path/to/project"})
# Look for specific file in results

# If missing, add it
mcp__vectorcode__vectorise({
  paths: ["/path/to/missing_file.py"],
  project_root: "/path/to/project"
})

# Verify project root matches exactly
# Common mistake: "/path/to/project" vs "/path/to/project/"
```

## Advanced Techniques

### Multi-Concept Queries

```javascript
// Combine multiple related concepts
mcp__vectorcode__query({
  n_query: 25,
  query_messages: [
    "authentication",
    "authorization",
    "permission check",
    "access control",
    "role based"
  ],
  project_root: "/path/to/project"
})
```

### Progressive Refinement

```javascript
// Start broad
n_query: 30
query: ["feature X"]

// Analyze results, then narrow
n_query: 15
query: ["feature X", "specific aspect", "related concept"]

// Further refinement
n_query: 10
query: ["very specific aspect", "implementation detail"]
```

### Cross-Language Patterns

```javascript
// VectorCode works across languages
mcp__vectorcode__query({
  n_query: 20,
  query_messages: ["async operations", "concurrency", "parallel execution"],
  project_root: "/path/to/project"
})

// Will find async/await (JS), asyncio (Python), goroutines (Go), etc.
```

## Performance Tips

**Query Size:**
- Start with `n_query: 10-15` for focused results
- Increase to `20-30` for broad exploration
- Higher numbers = more results but lower relevance

**Query Formulation:**
- Spend time on good keywords
- Use 2-5 distinct concepts
- Use distinct, specific search terms
- Think about synonyms and related concepts

**Project Root:**
- Always use exact path from `mcp__vectorcode__ls`
- Case-sensitive on Unix systems
- Include/exclude trailing slashes consistently

**Indexing:**
- Index incrementally (new files only)
- Don't re-index entire project frequently
- Use git hooks for automatic indexing

## Common Pitfalls

### ❌ Using Exact Code as Query

```javascript
// Don't do this
query: ["def process_payment(amount, user_id):"]

// Do this instead
query: ["payment processing", "transaction handling"]
```

### ❌ Single Generic Word

```javascript
// Too broad
query: ["function"]

// Better
query: ["utility functions", "helper methods", "common operations"]
```

### ❌ Wrong Project Root

```javascript
// If ls shows: "/Users/name/project"
// Don't use: "/Users/name/project/"  ❌
// Use:       "/Users/name/project"   ✅
```

### ❌ Expecting Exact Matches

```javascript
// VectorCode finds semantic similarity, not exact matches
// For exact matches, use grep
```

## Integration with Other Skills

**Combine with:**
- **rg-code-search** - Follow up with exact keyword search
- **fd-file-finding** - Locate files by name after VectorCode narrows scope
- **grep** - Extract specific patterns from VectorCode results

**Workflow:**
1. VectorCode: Find relevant areas semantically
2. fd/glob: Locate specific files in those areas
3. grep/rg: Extract exact code patterns
4. Read: Examine specific files

## Comparison Matrix

| Need | Tool | Why |
|------|------|-----|
| Find by concept | VectorCode | Semantic understanding |
| Find exact string | grep/rg | Fast, exhaustive |
| Find files by name | fd/glob | File system patterns |
| Explore unknown code | VectorCode | No prior knowledge needed |
| Verify completeness | grep | Exhaustive search |
| Find similar code | VectorCode | Pattern recognition |

## Quick Reference

### MCP Tools
- `mcp__vectorcode__ls` - List indexed projects
- `mcp__vectorcode__query` - Semantic code search
- `mcp__vectorcode__vectorise` - Add files to index
- `mcp__vectorcode__files_ls` - List indexed files
- `mcp__vectorcode__files_rm` - Remove files from index

### Query Parameters
- `n_query` - Number of results (10-30 typical)
- `query_messages` - Array of distinct keywords
- `project_root` - Exact project path from `ls`

### Best Practices
- Use concept-based keywords
- Provide 2-5 distinct terms
- Start broad, refine iteratively
- Combine with traditional search
- Verify project_root exactly

### Common Query Patterns
```javascript
// Exploration
["main functionality", "core logic", "entry point"]

// Feature location
["user authentication", "login flow", "session management"]

// Pattern discovery
["error handling", "retry logic", "fallback"]

// Architecture
["database access", "API integration", "service layer"]
```

## Resources

- **VectorCode MCP Integration**: Automatically available when MCP server is configured
- **Git Hooks**: Use `vectorcode init --hooks` to auto-index on commits
- **Index Files**: `.vectorcode.include` and `.vectorcode.exclude` control indexing
