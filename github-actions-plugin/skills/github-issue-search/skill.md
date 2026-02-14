---
model: haiku
created: 2025-12-16
modified: 2026-02-14
reviewed: 2025-12-16
name: github-issue-search
description: Search GitHub issues for solutions, workarounds, and discussions for open source problems. Use when encountering errors with OSS libraries or finding upstream bug workarounds.
allowed-tools: Bash, Read, Grep, Glob
---

# GitHub Issue Search for Solutions

Search GitHub repository issues to find solutions, workarounds, and discussions for open source software problems.

For detailed examples, advanced patterns, and best practices, see [REFERENCE.md](REFERENCE.md).

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
Error Message -> Extract Keywords -> Search Issues -> Find Solutions
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

### Search Strategy Summary

| Strategy | When to Use | Key Approach |
|----------|-------------|--------------|
| Error-focused | Specific error message | Extract unique error terms, search repo |
| Symptom-based | Observable behavior, no exact error | Describe behavior + version/component |
| Version-specific | Issue after upgrading | Version number + issue type, check migration |
| Workaround discovery | Known issue, need temp fix | Search closed issues for code snippets |

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

## Quick Reference: Search Query Syntax

| Filter | Syntax | Example |
|--------|--------|---------|
| Repository | `repo:owner/repo` | `repo:facebook/react` |
| Open only | `is:open` | `bug is:open` |
| Closed only | `is:closed` | `fix is:closed` |
| Issues only | `is:issue` | `error is:issue` |
| Label | `label:name` | `label:bug` |
| Exclude label | `-label:name` | `-label:wontfix` |
| Created after | `created:>DATE` | `created:>2024-01-01` |
| Updated after | `updated:>DATE` | `updated:>2024-11-01` |
| Author | `author:user` | `author:octocat` |
| Reactions | `reactions:>N` | `reactions:>10` |
| Comments | `comments:>N` | `comments:>5` |
| Exclude term | `-term` | `-test -mock` |
| Organization | `org:name` | `org:kubernetes` |

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Quick error search | `mcp__github__search_issues` with error keywords + `repo:` filter |
| Find workarounds | Search closed issues: `query + is:closed repo:owner/repo` |
| Popular issues | Sort by reactions: `sort: "reactions"` |
| Recent issues | Filter by date: `created:>YYYY-MM-DD` |
| Get solution details | `mcp__github__issue_read` with `method: "get_comments"` |

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
