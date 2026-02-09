---
model: haiku
created: 2025-12-16
modified: 2026-02-09
reviewed: 2026-02-09
name: claude-blog-sources
description: |
  Access Claude Blog and official Claude Code documentation for latest improvements, usage patterns,
  and best practices. Use when researching Claude Code features, CLAUDE.md optimization, memory
  management, or staying current with Claude capabilities.
allowed-tools: WebFetch, WebSearch, Task
---

# Claude Blog Sources

## Overview

The Anthropic Claude Blog (https://www.claude.com/blog/) publishes official guidance on Claude Code features, usage patterns, and best practices. This skill provides structured access to blog content for staying current with Claude capabilities.

## Primary Sources

### Official Documentation (preferred for technical details)

**Claude Code Docs**: https://code.claude.com/docs/en/

| Topic | URL | Description |
|-------|-----|-------------|
| Memory management | /docs/en/memory | CLAUDE.md, auto memory, @imports, rules hierarchy |
| Configuration | /docs/en/configuration | Settings, permissions, MCP servers |
| Hooks | /docs/en/hooks | Pre/post tool use hooks |
| Claude Code overview | /docs/en/overview | Getting started, features |

Use official docs as the authoritative reference. Blog posts supplement with patterns and examples.

### Blog

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

## CLAUDE.md Best Practices (from Blog + Official Docs)

Based on official documentation and blog posts:

### Structure Guidelines

- **Keep concise**: Treat as documentation both humans and Claude need to understand quickly
- **Strategic placement**: Root for team-wide, parent dirs for monorepos, home folder for universal
- **Use `@import`**: Reference existing docs with `@path/to/file.md` instead of duplicating content
- **Use `CLAUDE.local.md`**: Personal preferences go here (auto-gitignored), not in shared CLAUDE.md
- **Use `.claude/rules/`**: Path-specific rules with `paths` frontmatter for conditional loading

### Memory Hierarchy

| Layer | Purpose | Managed by |
|-------|---------|------------|
| CLAUDE.md | Team instructions (checked into git) | Developers |
| CLAUDE.local.md | Personal preferences (gitignored) | Individual |
| .claude/rules/ | Path-specific and domain rules | Developers |
| ~/.claude/rules/ | User-level rules (all projects) | Individual |
| Auto memory | Claude's own learnings | Claude (automatic) |

### Essential Sections (team-shared)

1. **Project Overview**: Brief summary, key technologies, architectural patterns
2. **Directory Map**: Visual hierarchy showing key directories
3. **Standards & Conventions**: Type hints, code style, naming conventions
4. **Common Commands**: Frequently-used commands with descriptions
5. **Workflows**: Standard approaches for different task types
6. **Tool Integration**: MCP servers, custom tools with usage examples

### What Auto Memory Handles (omit from CLAUDE.md)

- Current focus and work-in-progress context
- Key file relationships and navigation patterns
- Debugging insights and workarounds
- Personal preferences and habits

### What to Avoid

- Sensitive information (API keys, credentials, connection strings)
- Excessive length (keep concise from context engineering perspective)
- Theoretical content not matching actual development reality
- Content that duplicates auto memory concerns

### Evolution Strategy

- Start simple, expand deliberately
- Add sections based on real friction points
- Maintain as living document that evolves with codebase
- Use `@import` to keep CLAUDE.md lean as the project grows

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

*Last reviewed: February 2026. Update this list monthly when reviewing new articles.*

Official documentation worth checking (authoritative reference):

- [ ] /docs/en/memory - Memory management, CLAUDE.md, @imports, auto memory, rules hierarchy
- [ ] /docs/en/configuration - Settings, permissions, MCP servers
- [ ] /docs/en/hooks - Hook system for tool use events

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
