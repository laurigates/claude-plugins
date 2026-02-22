---
model: haiku
name: google-knowledge-search
description: |
  Search and retrieve official Google developer documentation using the Developer Knowledge API MCP server.
  Use when you need to find Firebase, Google Cloud, Android, or Maps documentation, implementation guides,
  or API references from Google's canonical sources.
allowed-tools: Bash, Read, Grep, Glob, TodoWrite
created: 2026-02-08
modified: 2026-02-08
reviewed: 2026-02-08
---

# Google Developer Knowledge Search

Expert knowledge for searching Google's official developer documentation via the Developer Knowledge API MCP server.

## When to Use This Skill

| Use this skill when... | Use something else when... |
|------------------------|---------------------------|
| Need official Google documentation | Searching non-Google docs (use WebSearch) |
| Firebase/Cloud/Android/Maps implementation guides | Looking for community tutorials or blog posts |
| Need canonical API references | Need GitHub issues or source code |
| Comparing Google services (Cloud Run vs Cloud Functions) | Comparing Google vs non-Google services |

## Core Expertise

The Google Developer Knowledge API provides programmatic access to Google's official developer documentation in Markdown format. Documentation is re-indexed within 24 hours of updates, ensuring results are current.

**Key advantages:**
- Canonical source of truth for Google documentation
- Markdown format optimized for AI consumption
- Chunked search results for relevant snippets
- Full document retrieval for complete context
- Covers Firebase, Google Cloud, Android, Maps, and more

## MCP Tools

### search_documents

Search across Google's developer documentation corpus. Returns relevant document chunks with snippets.

**Best practices:**
- Use specific, targeted queries
- Include the product name in queries (e.g., "Firebase Cloud Messaging push notifications")
- Results include a `parent` field used by `get_document` for full content

### get_document

Retrieve the full Markdown content of a document using the `parent` from search results.

**Best practices:**
- Use after `search_documents` to get complete context
- Preferred when you need the full page, not just snippets

### batch_get_documents

Retrieve multiple documents at once using `parent` values from search results.

**Best practices:**
- Use when comparing multiple pages or gathering broad context
- More efficient than multiple individual `get_document` calls

## Search Strategies

### Implementation Guidance

Search for specific product features:
- "Firebase Cloud Messaging setup Android"
- "Cloud Storage Python client library upload"
- "Google Maps JavaScript API markers"

### Troubleshooting

Search for error messages or common issues:
- "Cloud Functions cold start optimization"
- "Firebase Authentication error codes"
- "Android Jetpack Compose state management"

### Comparative Analysis

Search for service comparisons:
- "Cloud Run vs Cloud Functions comparison"
- "Firestore vs Realtime Database differences"
- "Firebase Hosting vs Cloud Storage static sites"

### API References

Search for specific API details:
- "Cloud Storage JSON API methods"
- "Firebase Admin SDK Node.js reference"
- "Maps Geocoding API parameters"

## Documentation Coverage

| Product | Coverage |
|---------|----------|
| Firebase | Authentication, Firestore, Cloud Functions, Hosting, Cloud Messaging, Storage, Remote Config |
| Google Cloud | Compute Engine, Cloud Run, Cloud Functions, Cloud Storage, BigQuery, Pub/Sub, IAM |
| Android | Jetpack, Compose, Architecture Components, Kotlin, NDK |
| Maps | JavaScript API, Directions, Geocoding, Places, Static Maps |
| General | OAuth, Identity Platform, gcloud CLI, API design guides |

## Workflow Pattern

1. **Search** with `search_documents` using a targeted query
2. **Review** snippets in search results for relevance
3. **Retrieve** full documents with `get_document` or `batch_get_documents` using `parent` values
4. **Apply** the documentation guidance to the current task

## Limitations

- English-language results only
- Official documentation only (no GitHub, blogs, YouTube, or OSS sites)
- Publicly visible pages only (no internal or gated content)

## Agentic Optimizations

| Context | Approach |
|---------|----------|
| Quick lookup | Use `search_documents` with specific query, read snippets |
| Deep dive | Use `search_documents` then `get_document` for full page |
| Multi-page research | Use `search_documents` then `batch_get_documents` for efficiency |
| Product comparison | Search both products, use `batch_get_documents` to retrieve all |

## Quick Reference

| Tool | Input | Returns |
|------|-------|---------|
| `search_documents` | Query string | Document chunks with snippets and `parent` |
| `get_document` | `parent` from search | Full Markdown content of one document |
| `batch_get_documents` | Multiple `parent` values | Full Markdown content of multiple documents |
