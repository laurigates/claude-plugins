# ADR-0012: Blog Plugin for Project Documentation

**Date**: 2026-01-10
**Status**: Accepted
**Deciders**: Plugin Maintainers

## Context

Developers working across multiple projects often struggle to document their work consistently. This is particularly challenging for those with ADHD, where:

- Context-switching between projects leads to forgotten progress
- Blank-page anxiety prevents starting documentation
- Inconsistent formats make it hard to scan past work
- High-friction capture means good work goes undocumented
- No central log of accomplishments across project boundaries

The existing `documentation-plugin` focuses on technical documentation (API docs, READMEs, knowledge graphs) rather than personal/project logs and blog-style content.

### Problem Statement

How do we enable developers to:
1. Capture work progress with minimal friction
2. Maintain consistent documentation style across projects
3. Create a searchable log of accomplishments
4. Reduce the barrier between "did something" and "wrote about it"

## Decision Drivers

- **Low friction**: Must be faster to use than not using it
- **ADHD-friendly**: Templates reduce blank-page paralysis; permission to be incomplete (draft status)
- **Cross-project**: Works regardless of which project is active
- **Consistent**: Same structure makes scanning old posts easy
- **Automation-ready**: Structured metadata enables future tooling
- **Honest time estimates**: Help users choose appropriate post types

## Considered Options

### Option 1: Extend documentation-plugin

Add blog functionality to the existing documentation-plugin.

**Pros**:
- No new plugin to maintain
- Shared infrastructure with doc generation

**Cons**:
- Different use case (technical docs vs personal logs)
- Different audience (API consumers vs self/readers)
- Conflates two distinct workflows
- documentation-plugin already has its own scope

### Option 2: Create blog-plugin (Selected)

Create a dedicated plugin for blog-style documentation.

**Pros**:
- Clear separation of concerns
- Focused skill and command design
- Can evolve independently
- Explicit ADHD-friendly design patterns

**Cons**:
- Another plugin to maintain
- Some potential overlap with documentation concepts

### Option 3: Add to communication-plugin

Extend communication-plugin (which handles ticket drafting, Google Chat formatting).

**Pros**:
- Both involve "writing for an audience"

**Cons**:
- Weak conceptual fit (chat/tickets vs blog posts)
- Different structure and workflow
- communication-plugin is for external communication, not personal logs

## Decision Outcome

**Chosen option**: Option 2 - Create dedicated blog-plugin

A separate plugin provides the clearest mental model and allows for ADHD-specific design decisions without compromising other plugins.

### Plugin Structure

```
blog-plugin/
├── .claude-plugin/plugin.json
├── README.md
├── skills/
│   └── blog-post-writing/
│       └── skill.md          # Style guide, templates, patterns
└── commands/
    └── blog-post.md          # /blog:post entry point
```

### Key Design Decisions

#### 1. Five Post Types with Time Estimates

| Type | Use Case | Time |
|------|----------|------|
| Quick Update | Small wins, daily log | 5-15 min |
| Project Update | Milestones, notable progress | 20-45 min |
| Retrospective | Looking back at work | 45-90 min |
| Tutorial | Teaching something learned | 1-3 hours |
| Deep Dive | Complex explanations | 2-5 hours |

**Rationale**: Explicit time estimates help users choose appropriate scope. "Quick Update" permission reduces pressure to write comprehensively.

#### 2. Automatic Context Gathering

The `/blog:post` command automatically collects:
- Current project name (from git remote, package.json, or directory)
- Recent commits (last 7 days)
- Current branch
- Changed files

**Rationale**: Pre-filled context reduces cognitive load and helps recall what was done.

#### 3. Structured Frontmatter

```yaml
---
title: <title>
date: YYYY-MM-DD
type: quick-update | project-update | retrospective | tutorial | deep-dive
project: <project-name>
tags: [tag1, tag2]
status: draft | published
---
```

**Rationale**: Consistent metadata enables:
- Cross-project timeline views
- Tag-based filtering
- Draft/published workflow
- Future automation (RSS, static site generation)

#### 4. ADHD-Friendly Patterns

| Pattern | Purpose |
|---------|---------|
| Templates | Reduce blank-page paralysis |
| Draft status | Permission to be incomplete |
| What/Why structure | Focused prompts guide writing |
| Time tracking | Build awareness of effort |
| Next steps section | Create continuity between sessions |
| Git context comments | Remind what was done |

#### 5. Minimal Required Interaction

The command asks only essential questions:
- Post type (if not specified)
- One focused prompt per type (e.g., "What did you just do?")
- File location (if no blog directory exists)

**Rationale**: Every question is a point of friction. Minimize questions, maximize automatic inference.

## Consequences

### Positive

- **Reduced friction**: Pre-filled templates and auto-context make starting easy
- **Consistent output**: Same structure across all posts enables scanning
- **Cross-project visibility**: Project metadata tracks work regardless of where it happened
- **Automation-ready**: Structured data supports future tooling
- **ADHD accommodation**: Explicit design for executive function challenges

### Negative

- **Another plugin**: Increases total plugin count
- **Overlap with writing concepts**: Some patterns similar to ticket-drafting skill
- **File organization**: Users must decide where to store posts

### Risks

| Risk | Mitigation |
|------|------------|
| Users forget to use it | Low friction reduces barrier; could add hooks for end-of-session prompts |
| Posts become stale | Draft status is explicit; no pressure to publish |
| Too many post types | Types are suggestions, not requirements; quick-update is default |

## Future Considerations

1. **End-of-day hooks**: Prompt for quick-update at session end
2. **Cross-project timeline**: Aggregate posts across repositories
3. **Static site integration**: Export to Hugo, Jekyll, Astro
4. **Tag-based queries**: "What did I do with authentication last month?"
5. **Commit-linked posts**: Auto-suggest posts based on significant commits

## Links

- Related: [ADR-0002: Domain-Driven Plugin Organization](0002-domain-driven-plugin-organization.md)
- Related: [communication-plugin/skills/ticket-drafting-guidelines](../../communication-plugin/skills/ticket-drafting-guidelines/)
- Plugin: [blog-plugin/README.md](../../blog-plugin/README.md)
