---
name: github-issue-search
description: |
  Search GitHub issues to find solutions, workarounds, and discussions for open
  source problems. Covers search query syntax, error message patterns, and
  MCP tool usage. Use when encountering errors with OSS libraries, searching
  for known issues, or finding upstream bug workarounds.
---

# GitHub Issue Search for Solutions

Search GitHub repository issues to find solutions, workarounds, and discussions for open source software problems.

## When to Use

Use this skill automatically when:
- User encounters errors or problems with open source software
- User mentions a library/package name with an error message
- User asks "has anyone reported this issue before?"
- User needs workarounds for known bugs
- User wants to understand if a problem is already tracked
- Debugging reveals potential upstream issues

## Core Capabilities

### Search Issues by Error Message

When encountering an error, search the repository for related issues:

```
Error Message → Extract Keywords → Search Issues → Find Solutions
```

**MCP Tool Used:** `mcp__github__search_issues`

**Search Query Construction:**
1. Extract error type (e.g., "TypeError", "ECONNREFUSED", "panic")
2. Extract key terms from error message
3. Identify repository from context (package.json, go.mod, error stack trace)
4. Construct targeted search query

### Search Patterns

**By Error Message:**
```
Query: "TypeError: Cannot read property 'map' of undefined repo:facebook/react"
```

**By Symptom:**
```
Query: "memory leak kubernetes deployment repo:kubernetes/kubernetes"
```

**By Feature/Behavior:**
```
Query: "authentication timeout websocket repo:socketio/socket.io"
```

**By Version:**
```
Query: "breaking change v2.0.0 migration repo:vuejs/vue"
```

## Search Strategies

### Strategy 1: Error-Focused Search

**When:** You have a specific error message

**Approach:**
1. Extract the most unique part of error message
2. Search in relevant repository
3. Filter by issue state (both open and closed)
4. Look for labels like "bug", "help wanted"

**Example:**
```
Error: ENOENT: no such file or directory, open '/app/config.json'

Search Query: "ENOENT config.json repo:nodejs/node"
Alternative: "no such file or directory config repo:nodejs/node"
```

**MCP Search Parameters:**
- `query`: Error keywords + repo
- `sort`: "created" or "updated" (most recent first)
- `order`: "desc"
- `state`: Both open and closed issues

### Strategy 2: Symptom-Based Search

**When:** You know the symptom but not the exact error

**Approach:**
1. Describe the observable behavior
2. Include version or component
3. Search for related discussions

**Example:**
```
Symptom: Pods stuck in "Pending" state after upgrade

Search Query: "pods pending stuck upgrade repo:kubernetes/kubernetes"
Additional: "pending state scheduling repo:kubernetes/kubernetes"
```

### Strategy 3: Version-Specific Search

**When:** Issue appeared after upgrading

**Approach:**
1. Search for version number + issue type
2. Look for migration guides or breaking changes
3. Check closed issues for similar problems

**Example:**
```
Problem: App broken after upgrading from v3.0 to v4.0

Search Query: "v4.0 breaking change repo:expressjs/express"
Alternative: "upgrade v3 v4 migration repo:expressjs/express"
```

### Strategy 4: Workaround Discovery

**When:** Known issue, need a temporary fix

**Approach:**
1. Search closed issues (often have workarounds)
2. Look for comments with code snippets
3. Check for "workaround" or "temporary fix" labels

**Example:**
```
Problem: Known bug with npm install on Windows

Search Query: "npm install windows workaround repo:npm/cli is:closed"
```

## Using GitHub MCP Tools

### Search Issues

```
Tool: mcp__github__search_issues

Parameters:
- query: Search query with GitHub search syntax
- owner: Repository owner (optional, can be in query)
- repo: Repository name (optional, can be in query)
- sort: "comments", "created", "updated", "reactions"
- order: "asc" or "desc"
- perPage: Number of results (max 100)
- page: Page number for pagination
```

**Examples:**

```javascript
// Search by error message
{
  "query": "TypeError map undefined repo:facebook/react",
  "sort": "updated",
  "order": "desc",
  "perPage": 20
}

// Search by label and state
{
  "query": "label:bug is:closed memory leak repo:nodejs/node",
  "sort": "reactions",
  "order": "desc"
}

// Search recent issues
{
  "query": "authentication failed created:>2024-01-01 repo:auth0/auth0-spa-js",
  "sort": "created",
  "order": "desc"
}
```

### Get Issue Details

```
Tool: mcp__github__issue_read

Parameters:
- method: "get" (issue details), "get_comments" (comments)
- owner: Repository owner
- repo: Repository name
- issue_number: Issue number
- perPage: Results per page
- page: Page number
```

**Example:**

```javascript
// Get issue details
{
  "method": "get",
  "owner": "facebook",
  "repo": "react",
  "issue_number": 12345
}

// Get issue comments (where solutions often are)
{
  "method": "get_comments",
  "owner": "facebook",
  "repo": "react",
  "issue_number": 12345,
  "perPage": 50
}
```

## GitHub Search Query Syntax

### Basic Search
```
error message repo:owner/repo
```

### Filter by State
```
is:open        # Open issues only
is:closed      # Closed issues only
is:issue       # Issues (not PRs)
```

### Filter by Labels
```
label:bug
label:"help wanted"
label:documentation
-label:wontfix  # Exclude label
```

### Filter by Date
```
created:>2024-01-01
updated:<2024-06-01
created:2024-01-01..2024-12-31
```

### Filter by Author/Assignee
```
author:username
assignee:username
mentions:username
```

### Filter by Reactions/Comments
```
reactions:>10
comments:>5
```

### Combine Filters
```
memory leak repo:nodejs/node is:closed label:bug created:>2024-01-01 comments:>5
```

## Workflow Examples

### Example 1: React Error Debugging

**Problem:**
```
Error: Cannot read property 'setState' of undefined
Component: UserProfile
Version: React 18.2.0
```

**Search Workflow:**

```bash
# 1. Search for exact error
Search: "Cannot read property setState of undefined repo:facebook/react"

# 2. Refine with version
Search: "setState undefined react 18 repo:facebook/react"

# 3. Look for component lifecycle issues
Search: "setState undefined lifecycle repo:facebook/react is:closed"

# 4. Check recent similar issues
Search: "setState this undefined created:>2024-01-01 repo:facebook/react"
```

**Extract Solutions:**
- Read issue descriptions
- Check accepted answers in comments
- Look for code snippets with fixes
- Note if issue is fixed in later version

### Example 2: Kubernetes Deployment Issue

**Problem:**
```
Pods stuck in "ImagePullBackOff"
Private registry authentication
Kubernetes v1.28
```

**Search Workflow:**

```bash
# 1. Search for specific symptom
Search: "ImagePullBackOff private registry repo:kubernetes/kubernetes"

# 2. Look for authentication issues
Search: "image pull secret authentication repo:kubernetes/kubernetes is:closed"

# 3. Check version-specific issues
Search: "ImagePullBackOff 1.28 repo:kubernetes/kubernetes"

# 4. Find workarounds
Search: "ImagePullBackOff workaround label:bug repo:kubernetes/kubernetes"
```

### Example 3: npm Package Installation Failure

**Problem:**
```
npm ERR! code ENOENT
npm ERR! syscall rename
Package: webpack@5.88.0
```

**Search Workflow:**

```bash
# 1. Search error code
Search: "ENOENT syscall rename repo:npm/cli"

# 2. Search package-specific
Search: "webpack install error ENOENT repo:webpack/webpack"

# 3. Platform-specific (if Windows/Mac/Linux)
Search: "ENOENT windows npm install repo:npm/cli"

# 4. Check for known issues in npm
Search: "syscall rename permission repo:npm/cli is:closed"
```

### Example 4: Database Connection Issues

**Problem:**
```
Error: Connection timeout
Library: pg (PostgreSQL client)
Node.js application
```

**Search Workflow:**

```bash
# 1. Search generic connection issue
Search: "connection timeout repo:brianc/node-postgres"

# 2. Search configuration issues
Search: "timeout configuration connection pool repo:brianc/node-postgres"

# 3. Look for similar stack traces
Search: "ETIMEDOUT connection repo:brianc/node-postgres is:closed"

# 4. Check recent reports
Search: "timeout created:>2024-01-01 repo:brianc/node-postgres"
```

## Analyzing Search Results

### Prioritize Results

**High Priority:**
1. **Recently updated** - Active discussion, recent workarounds
2. **Many comments** - Detailed discussion with multiple perspectives
3. **Many reactions** - Community considers it important
4. **Closed with solution** - Problem was solved
5. **Labeled "bug"** - Confirmed issue, likely has workarounds

**Lower Priority:**
1. Feature requests (not bugs)
2. Old issues with no activity
3. "wontfix" or "duplicate" labels
4. Issues with different symptoms

### Extract Solutions from Issues

**Look for:**
1. **Original poster's resolution** - "Solved by doing X"
2. **Maintainer responses** - Official guidance
3. **Code snippets** - Actual fixes/workarounds
4. **Links to PRs** - Fixed in specific version
5. **Configuration changes** - Settings that resolve issue

**Comments to focus on:**
- Comments with many 👍 reactions
- Comments marked as answer (GitHub Discussions)
- Comments from maintainers/contributors
- Comments with code blocks
- Comments mentioning "workaround" or "fix"

### Red Flags

**Ignore if:**
- Marked as "duplicate" (find original issue)
- Labeled "wontfix" or "intended behavior"
- Different error message despite similar keywords
- Different version (unless upgrade is solution)
- Different platform/environment if relevant

## Integration with Debugging Workflow

### Step 1: Encounter Error
```
Application error → Extract error details
```

### Step 2: Local Investigation
```
Check logs → Stack trace → Configuration
```

### Step 3: Search GitHub Issues (THIS SKILL)
```
Construct query → Search repository → Review results
```

### Step 4: Apply Solution
```
Test workaround → Verify fix → Document for team
```

### Step 5: Contribute Back (Optional)
```
If solution found but not documented:
- Add comment to existing issue
- Create new issue with solution
- Submit PR if code fix
```

## Repository Identification

### From Error Stack Trace

```javascript
// Stack trace shows package
Error: Something went wrong
  at Object.<anonymous> (/node_modules/express/lib/router/index.js:123:45)

// Repository: expressjs/express
```

### From Package Manager Files

```json
// package.json
{
  "dependencies": {
    "express": "^4.18.0"  // → expressjs/express
  }
}
```

```toml
# Cargo.toml
[dependencies]
tokio = "1.35.0"  # → tokio-rs/tokio
```

```go
// go.mod
require (
    github.com/gin-gonic/gin v1.9.1  // → gin-gonic/gin
)
```

### From Documentation/Import Statements

```python
# Python import
import requests  # → psf/requests

# PyPI to GitHub mapping may need lookup
```

## Best Practices

### Effective Searching

✅ **DO**: Extract key unique terms from error
```
"TypeError: Cannot read property 'map' of undefined"
→ Search: "Cannot read property map undefined"
```

✅ **DO**: Include version information
```
Search: "error message react 18"
```

✅ **DO**: Check both open and closed issues
```
Search: "error message repo:org/repo" (defaults to both states)
```

✅ **DO**: Sort by relevance, then recency
```
First search: default sort (relevance)
If too many results: sort by "updated" desc
```

❌ **DON'T**: Search full error messages verbatim
```
Bad: "Error: ENOENT: no such file or directory, open '/Users/john/app/config.json'"
Good: "ENOENT no such file directory config"
```

❌ **DON'T**: Search with repository-specific paths
```
Bad: "/node_modules/express/lib/router/index.js"
Good: "express router error"
```

### Evaluating Solutions

✅ **DO**: Test workarounds in non-production first
✅ **DO**: Check if solution applies to your version
✅ **DO**: Verify the issue context matches yours
✅ **DO**: Look for official maintainer responses

❌ **DON'T**: Apply fixes without understanding them
❌ **DON'T**: Ignore version compatibility
❌ **DON'T**: Skip reading full issue context

### Contributing Back

✅ **DO**: Comment if you find a solution not documented
✅ **DO**: Create new issue if none exists
✅ **DO**: Link related issues you found
✅ **DO**: Submit PR if you can fix the code

## Advanced Search Techniques

### Multi-Repository Search

```bash
# Search across organization
Search: "authentication error org:kubernetes"

# Search multiple related repos
Search: "error message repo:org/repo1 repo:org/repo2"
```

### Exclude False Positives

```bash
# Exclude common noise
Search: "timeout -test -mock repo:org/repo"

# Exclude specific terms
Search: "error -documentation -example repo:org/repo"
```

### Find Popular Issues

```bash
# By reactions
Search: "feature repo:org/repo sort:reactions-+1"

# By comments
Search: "bug repo:org/repo sort:comments"
```

### Time-Bound Searches

```bash
# Recent issues (last 3 months)
Search: "error created:>2024-10-01 repo:org/repo"

# Issues updated recently (active discussions)
Search: "bug updated:>2024-11-01 repo:org/repo"
```

## Troubleshooting Search

### Too Many Results

```bash
# Add more specific terms
# Add filters (labels, dates, state)
# Increase perPage to see more context
```

### No Results Found

```bash
# Remove repository restriction (search all of GitHub)
# Use fewer search terms (too specific)
# Try synonyms (e.g., "crash" → "panic", "fail")
# Check repository name (typo?)
```

### Wrong Repository

```bash
# Double-check package to repository mapping
# Some packages are forks (check original repo)
# Search package registry for canonical source
```

## Related Skills

- **System Debugging** - Use issue search during debugging
- **Helm Debugging** - Search helm/helm for Helm issues
- **Package Management** - Search dependency issues
- **Git Operations** - Link issues in commits/PRs

## References

- [GitHub Search Syntax](https://docs.github.com/en/search-github/searching-on-github/searching-issues-and-pull-requests)
- [GitHub Search Qualifiers](https://docs.github.com/en/search-github/getting-started-with-searching-on-github/understanding-the-search-syntax)
- [GitHub Issues Documentation](https://docs.github.com/en/issues)
- [GitHub MCP Server Tools](https://github.com/modelcontextprotocol/servers-archived/tree/main/src/github)
