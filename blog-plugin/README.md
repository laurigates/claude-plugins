# blog-plugin

Blog post creation for documenting projects, capturing progress, and sharing technical work.

## Why This Plugin?

- **Low friction entry**: Start writing with minimal prompts
- **Consistent structure**: Templates for different post types
- **Context awareness**: Automatically gathers project info from git
- **ADHD-friendly**: Designed to reduce blank-page paralysis
- **Personal log**: Track what you've accomplished across projects

## Installation

Add to your Claude Code plugins:

```bash
claude plugins add /path/to/blog-plugin
```

## Quick Start

```bash
# Start writing - you'll be guided through the rest
/blog:post

# Or specify the type directly
/blog:post quick-update
/blog:post project-update --project my-app
/blog:post retrospective
```

## Commands

| Command | Description |
|---------|-------------|
| `/blog:post` | Create a new blog post with guided prompts |

## Skills

| Skill | Description |
|-------|-------------|
| `blog-post-writing` | Style guide and templates for consistent blog posts |

## Post Types

| Type | When to Use | Time |
|------|-------------|------|
| Quick Update | Daily log, small wins | 5-15 min |
| Project Update | Milestones, notable progress | 20-45 min |
| Retrospective | Looking back at work done | 45-90 min |
| Tutorial | Teaching something you learned | 1-3 hours |
| Deep Dive | Explaining complex topics | 2-5 hours |

## Example Workflow

1. Finish working on something
2. Run `/blog:post`
3. Answer 1-2 quick questions
4. Get a pre-filled template with your git context
5. Fill in the details (or leave as quick note)
6. Save as draft or publish

## File Organization

Posts are saved with consistent naming:

```
blog/
├── posts/
│   └── 2026-01-10-fixed-auth-bug.md
└── drafts/
    └── wip-new-feature.md
```

## Post Metadata

Every post includes frontmatter for organization:

```yaml
---
title: "Fixed the Auth Bug"
date: 2026-01-10
type: quick-update
project: my-app
tags: [bugfix, auth]
status: draft
---
```

## Future Plans

- [ ] Automation hooks for end-of-day summaries
- [ ] Integration with static site generators
- [ ] Cross-project timeline views
- [ ] Tag-based categorization commands
