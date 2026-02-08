---
model: haiku
name: google-knowledge-setup
description: |
  Set up the Google Developer Knowledge API MCP server for accessing official Google documentation.
  Use when you need to configure the MCP connection to search Firebase, Google Cloud, Android, or Maps docs.
args: "[PROJECT_ID]"
argument-hint: "Google Cloud project ID for API key creation"
allowed-tools: Bash(claude mcp *), Bash(gcloud *), Bash(cat *), Read, Grep, Glob, TodoWrite
created: 2026-02-08
modified: 2026-02-08
reviewed: 2026-02-08
---

# /google-knowledge:setup

Configure the Google Developer Knowledge API MCP server for Claude Code.

## When to Use This Skill

| Use this skill when... | Use something else when... |
|------------------------|---------------------------|
| Setting up Google docs MCP server | You already have the MCP server configured |
| Need official Firebase/Cloud/Android/Maps docs | Searching general web content (use WebSearch) |
| First-time API key and MCP configuration | Troubleshooting existing MCP connections (use agent-patterns) |

## Context

- Existing MCP config: !`cat ~/.claude.json 2>/dev/null | grep -A5 google-dev-knowledge || echo "not configured"`
- gcloud available: !`command -v gcloud 2>/dev/null && echo "yes" || echo "no"`
- gcloud project: !`gcloud config get-value project 2>/dev/null || echo "none"`

## Prerequisites

1. A Google Cloud project
2. The `gcloud` CLI installed and authenticated
3. Billing enabled on the project (API key creation requires it)

## Execution

### Step 1: Enable the Developer Knowledge API

```bash
gcloud services enable developerknowledge.googleapis.com --project=$PROJECT_ID
```

### Step 2: Create an API Key

```bash
gcloud services api-keys create --project=$PROJECT_ID --display-name="Developer Knowledge API Key"
```

Retrieve the key string from the output. If you already have a key, skip this step.

### Step 3: Enable the MCP Server

```bash
gcloud beta services mcp enable developerknowledge.googleapis.com --project=$PROJECT_ID
```

If the command fails, update the beta component first:

```bash
gcloud components update beta
```

### Step 4: Configure Claude Code

```bash
claude mcp add google-dev-knowledge --transport http https://developerknowledge.googleapis.com/mcp --header "X-Goog-Api-Key: $API_KEY"
```

Replace `$API_KEY` with the key from Step 2.

### Step 5: Verify Configuration

Check that the MCP server appears in Claude Code's configuration:

```bash
claude mcp list
```

## Supported Documentation Sources

| Source | Domain |
|--------|--------|
| Firebase | firebase.google.com |
| Android | developer.android.com |
| Google Cloud | docs.cloud.google.com |
| Maps | developers.google.com/maps |
| General | developers.google.com |

## MCP Tools Available After Setup

| Tool | Purpose |
|------|---------|
| `search_documents` | Search Google docs for relevant pages and snippets |
| `get_document` | Get full content of a document by `parent` from search results |
| `batch_get_documents` | Get full content of multiple documents at once |

## Troubleshooting

| Issue | Solution |
|-------|----------|
| `gcloud beta services mcp` not found | Run `gcloud components update beta` |
| API key unauthorized | Verify key is restricted to Developer Knowledge API only |
| No results returned | API indexes official docs only (not GitHub, blogs, or YouTube) |
| False positive blocks | If using Model Armor, set Prompt Injection filter to `HIGH_AND_ABOVE` |

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Quick setup check | `claude mcp list 2>/dev/null \| grep google-dev-knowledge` |
| Enable API | `gcloud services enable developerknowledge.googleapis.com --project=$PROJECT_ID` |
| Enable MCP | `gcloud beta services mcp enable developerknowledge.googleapis.com --project=$PROJECT_ID` |
| Add to Claude | `claude mcp add google-dev-knowledge --transport http https://developerknowledge.googleapis.com/mcp --header "X-Goog-Api-Key: $API_KEY"` |
