# google-knowledge-plugin

Search and retrieve official Google developer documentation using the [Developer Knowledge API](https://developers.google.com/knowledge/mcp) MCP server.

## Overview

This plugin provides skills for setting up and using Google's Developer Knowledge API, which gives programmatic access to official documentation for Firebase, Google Cloud, Android, Maps, and more.

## Skills

| Skill | Type | Description |
|-------|------|-------------|
| `google-knowledge-setup` | User-invocable | Configure the Google Developer Knowledge API MCP server for Claude Code |
| `google-knowledge-search` | Auto-discovered | Search and retrieve official Google developer documentation |

## Quick Start

### Setup

```
/google-knowledge:setup PROJECT_ID
```

This walks through:
1. Enabling the Developer Knowledge API
2. Creating an API key
3. Enabling the MCP server
4. Configuring Claude Code

### Usage

Once configured, the MCP server provides three tools:
- `search_documents` - Search Google docs for relevant pages
- `get_document` - Get full content of a document
- `batch_get_documents` - Get multiple documents at once

## Requirements

- Google Cloud project with billing enabled
- `gcloud` CLI installed and authenticated
- Claude Code with MCP support

## Documentation Coverage

- Firebase (firebase.google.com)
- Google Cloud (docs.cloud.google.com)
- Android (developer.android.com)
- Google Maps (developers.google.com/maps)
