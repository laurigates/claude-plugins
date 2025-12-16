---
name: claude-blog-sources
description: |
  Access Claude Blog for latest Claude Code improvements, usage patterns, and best practices.
  Use when researching Claude Code features, CLAUDE.md optimization, or staying current with
  Claude capabilities. Checks recent articles for relevant updates and patterns.
allowed-tools: WebFetch, WebSearch, Task
---

# Claude Blog Sources

## Overview

The Anthropic Claude Blog (https://www.claude.com/blog/) publishes official guidance on Claude Code features, usage patterns, and best practices. This skill provides structured access to blog content for staying current with Claude capabilities.

## Primary Blog URL

**Main Blog**: https://www.claude.com/blog/

Note: May redirect to https://website.claude.com/blog - follow redirects automatically.

## Key Articles for Claude Code

### Essential Reading

| Article | URL | Topic |
|---------|-----|-------|
| Using CLAUDE.md Files | /blog/using-claude-md-files | CLAUDE.md structure and best practices |
| How Anthropic Teams Use Claude Code | /blog/how-anthropic-teams-use-claude-code | Internal usage patterns and workflows |
| Claude Code on the Web | /blog/claude-code-on-the-web | Web-based features and capabilities |

### Article Relevance Categories

**High Relevance** (always check):
- Articles mentioning "CLAUDE.md", "Claude Code", "Skills", "Agents"
- Articles about coding workflows, development practices
- Product announcements for Claude Code features

**Medium Relevance** (check if applicable):
- Articles about prompt engineering, context management
- Enterprise AI deployment patterns
- Integration guides (Slack, GitHub, etc.)

## Research Workflow

### When User Asks About Claude Code Features

1. **Check Recent Articles First**
   ```
   WebSearch: site:claude.com/blog {feature_name} OR "Claude Code"
   ```

2. **Fetch Relevant Articles**
   ```
   WebFetch: https://www.claude.com/blog/{article-slug}
   Prompt: Extract practical guidance, examples, and best practices for {topic}
   ```

3. **Cross-Reference with Documentation**
   - Official docs: https://docs.claude.com/en/docs/claude-code/
   - Compare blog insights with documentation

### Monthly Article Review Process

For staying current with Claude improvements:

1. **Fetch Blog Index**
   ```
   WebFetch: https://www.claude.com/blog/
   Prompt: List all articles from the past month with titles, dates, and relevance to Claude Code
   ```

2. **Triage by Relevance**
   - High: Directly mentions Claude Code, CLAUDE.md, Skills, or Agents
   - Medium: General AI coding patterns, prompt engineering
   - Low: Unrelated topics (enterprise, safety research, etc.)

3. **Extract Key Insights**
   For high-relevance articles, extract:
   - New features or capabilities
   - Updated best practices
   - Example patterns and workflows
   - Configuration recommendations

4. **Update Local Knowledge**
   - Consider updating relevant Skills with new patterns
   - Update CLAUDE.md files with new best practices
   - Create new Skills for newly documented features

## CLAUDE.md Best Practices (from Blog)

Based on the official blog post on CLAUDE.md files:

### Structure Guidelines

- **Keep concise**: Treat as documentation both humans and Claude need to understand quickly
- **Strategic placement**: Root for team-wide, parent dirs for monorepos, home folder for universal
- **Break into files**: Large information should be in separate markdown files, referenced from CLAUDE.md

### Essential Sections

1. **Project Overview**: Brief summary, key technologies, architectural patterns
2. **Directory Map**: Visual hierarchy showing key directories
3. **Standards & Conventions**: Type hints, code style, naming conventions
4. **Common Commands**: Frequently-used commands with descriptions
5. **Workflows**: Standard approaches for different task types
6. **Tool Integration**: MCP servers, custom tools with usage examples

### What to Avoid

- Sensitive information (API keys, credentials, connection strings)
- Excessive length (keep concise from context engineering perspective)
- Theoretical content not matching actual development reality

### Evolution Strategy

- Start simple, expand deliberately
- Add sections based on real friction points
- Maintain as living document that evolves with codebase

## Delegation Pattern

When research requires deep investigation:

```markdown
Use research-documentation agent for:
- Comprehensive blog article analysis
- Cross-referencing multiple sources
- Building knowledge summaries

Example delegation prompt:
"Research the Claude blog for articles about {topic} from the past 3 months.
Extract practical patterns and update recommendations. Focus on:
- New features or capabilities
- Changed best practices
- Concrete examples we can apply"
```

## Recent Articles Checklist

*Last reviewed: November 2025. Update this list monthly when reviewing new articles.*

Articles worth checking (sorted by relevance to Claude Code):

- [ ] /blog/using-claude-md-files - CLAUDE.md best practices
- [ ] /blog/how-anthropic-teams-use-claude-code - Internal usage patterns
- [ ] /blog/improving-frontend-design-through-skills - Skills feature
- [ ] /blog/claude-code-on-the-web - Web-based features

## Integration with Other Skills

This skill complements:
- **project-discovery**: Use blog patterns for new codebase orientation
- **blueprint-development**: Apply latest CLAUDE.md best practices to PRDs
- **multi-agent-workflows**: Incorporate blog-recommended delegation patterns
