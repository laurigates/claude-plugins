---
name: Blog Post Writing
description: |
  Consistent style guide for writing blog posts about projects and technical work.
  Supports quick updates, detailed write-ups, retrospectives, and tutorials.
  Designed for low-friction entry and easy scanning.
allowed-tools: Read, Write, Edit, Grep, Glob, Bash, TodoWrite
created: 2026-01-10
modified: 2026-01-10
reviewed: 2026-01-10
---

# Blog Post Writing

Expert guidance for creating consistent, scannable blog posts about projects and technical work. Optimized for capturing work in progress and sharing accomplishments.

## Core Expertise

- **Low-friction capture**: Quick entry formats that reduce blank-page anxiety
- **Consistent structure**: Predictable patterns for easy scanning later
- **Multiple post types**: From quick updates to detailed tutorials
- **Project context**: Automatic metadata for tracking work across projects
- **Future-proof**: Structure that supports later automation and publishing

## When This Skill Activates

This skill activates when:

1. User wants to write about work they've done
2. User needs to document a project update
3. User wants to create a devlog entry
4. User requests a blog post or article about technical work
5. User mentions "write up", "blog", "post", or "devlog"

## Post Types

| Type | When to Use | Typical Length |
|------|-------------|----------------|
| Quick Update | Captured something small, daily log | 100-300 words |
| Project Update | Milestone, feature complete, notable progress | 300-800 words |
| Retrospective | Looking back at a project or time period | 500-1500 words |
| Tutorial | Teaching how to do something | 800-2000 words |
| Deep Dive | Explaining complex concepts or decisions | 1000-3000 words |

## Universal Post Structure

Every post uses this metadata frontmatter:

```yaml
---
title: <descriptive title>
date: YYYY-MM-DD
type: quick-update | project-update | retrospective | tutorial | deep-dive
project: <project-name>
tags: [tag1, tag2]
status: draft | published
---
```

## Quick Update Format

For capturing small wins and progress. Minimal structure, maximum speed.

```markdown
---
title: <What you did in 5-10 words>
date: YYYY-MM-DD
type: quick-update
project: <project-name>
tags: [<relevant-tags>]
status: draft
---

# <Title>

<1-3 sentences about what you did>

## What Changed

- <Bullet points of specific changes>
- <Keep it concrete and scannable>

## Why It Matters

<1-2 sentences on significance - optional for truly quick updates>

---
*Time spent: ~Xh | Difficulty: low/medium/high*
```

## Project Update Format

For documenting meaningful progress on a project.

```markdown
---
title: <Project Name>: <What was accomplished>
date: YYYY-MM-DD
type: project-update
project: <project-name>
tags: [<relevant-tags>]
status: draft
---

# <Title>

<2-3 sentence summary of what this update covers>

## Context

<Brief background - what is this project, where were you before this work>

## What I Did

### <Subsection if needed>

<Details of the work, with code snippets if relevant>

```language
// Example code if applicable
```

## Challenges & Solutions

<What didn't work at first, how you solved it - this is the valuable learning>

## Results

<What's working now, what changed, metrics if applicable>

## Next Steps

- [ ] <Concrete next action>
- [ ] <Another thing to do>

---
*Time spent: ~Xh | Difficulty: low/medium/high*
```

## Retrospective Format

For looking back at a project, time period, or significant body of work.

```markdown
---
title: "Retrospective: <Project or Time Period>"
date: YYYY-MM-DD
type: retrospective
project: <project-name>
tags: [retrospective, <other-tags>]
status: draft
---

# <Title>

<What this retrospective covers and why you're writing it>

## The Journey

### Where I Started

<Initial state, goals, expectations>

### Key Milestones

1. **<Milestone 1>**: <What happened, when>
2. **<Milestone 2>**: <What happened, when>

### Where I Ended Up

<Current state, what exists now>

## What Worked

- <Thing that went well>
- <Another success>

## What Didn't Work

- <Challenge or failure>
- <What you'd do differently>

## Lessons Learned

<The valuable takeaways - what you know now that you didn't before>

## What's Next

<Future plans, continuation, or closure>

---
*Project duration: <timeframe> | Status: <ongoing/paused/complete>*
```

## Tutorial Format

For teaching others (or future you) how to do something.

```markdown
---
title: "How to <Do the Thing>"
date: YYYY-MM-DD
type: tutorial
project: <project-name>
tags: [tutorial, <technology-tags>]
status: draft
---

# <Title>

<What you'll learn and why it's useful>

## Prerequisites

- <Required knowledge or setup>
- <Tools needed>

## Overview

<Brief explanation of the approach>

## Step 1: <First Step>

<Explanation>

```language
// Code or commands
```

## Step 2: <Second Step>

<Continue pattern...>

## Troubleshooting

### <Common Issue>

<Solution>

## Summary

<Quick recap of what was covered>

## Resources

- [<Related Resource>](<url>)

---
*Tested with: <versions/environment> | Last verified: YYYY-MM-DD*
```

## Deep Dive Format

For explaining complex topics, architectural decisions, or detailed analysis.

```markdown
---
title: "<Topic>: A Deep Dive"
date: YYYY-MM-DD
type: deep-dive
project: <project-name>
tags: [deep-dive, <topic-tags>]
status: draft
---

# <Title>

<Hook - why this matters, what question you're answering>

## Background

<Context needed to understand the topic>

## The Problem

<What challenge or question prompted this exploration>

## Exploration

### <Aspect 1>

<Analysis, examples, code>

### <Aspect 2>

<Continue as needed>

## Key Insights

<The main takeaways, numbered or bulleted>

## Implications

<What this means for your work or the broader context>

## Conclusion

<Summary and final thoughts>

---
*Research time: ~Xh | Confidence: low/medium/high*
```

## Writing Style Guidelines

### Voice & Tone

| Guideline | Example |
|-----------|---------|
| First person | "I discovered that..." not "It was discovered..." |
| Conversational | Write like you're explaining to a colleague |
| Honest about uncertainty | "I think this works because..." |
| Specific over vague | "Reduced load time from 3s to 400ms" not "Made it faster" |

### Formatting

- **Use headers liberally** - makes scanning easy later
- **Bullet points for lists** - easier to read than paragraphs
- **Code blocks with language tags** - syntax highlighting helps
- **Bold for key terms** - draws the eye to important concepts
- **Short paragraphs** - 2-4 sentences max

### ADHD-Friendly Patterns

| Pattern | Why It Helps |
|---------|--------------|
| Start with templates | Reduces blank-page paralysis |
| Metadata first | Context capture before you forget |
| What/Why structure | Focused prompts guide writing |
| Time tracking | Builds awareness of effort |
| Next steps section | Creates continuity between sessions |
| Draft status | Permission to be incomplete |

## File Organization

Recommended directory structure for blog posts:

```
blog/
├── posts/
│   ├── YYYY/
│   │   ├── MM/
│   │   │   ├── YYYY-MM-DD-slug.md
├── drafts/
│   ├── <working-title>.md
└── assets/
    ├── images/
    └── diagrams/
```

Alternative flat structure:

```
blog/
├── YYYY-MM-DD-slug.md
└── drafts/
```

## Quick Reference

### Post Type Decision Tree

```
Did you learn something you want to teach?
  → Yes → Tutorial
  → No ↓

Are you looking back at past work?
  → Yes → Retrospective
  → No ↓

Is this about a complex topic or decision?
  → Yes → Deep Dive
  → No ↓

Did you make significant progress?
  → Yes → Project Update
  → No → Quick Update
```

### Essential Metadata

| Field | Required | Purpose |
|-------|----------|---------|
| title | Yes | Findability |
| date | Yes | Timeline |
| type | Yes | Structure selection |
| project | Yes | Cross-project tracking |
| tags | No | Categorization |
| status | Yes | Draft vs published |

### Time Estimates

| Activity | Time |
|----------|------|
| Quick Update | 5-15 min |
| Project Update | 20-45 min |
| Retrospective | 45-90 min |
| Tutorial | 1-3 hours |
| Deep Dive | 2-5 hours |

## Integration with Other Skills

This skill works alongside:

- **Git Commit Workflow** - Reference commits in posts
- **Ticket Drafting** - Similar structured writing patterns
- **Project Blueprint** - Link to PRDs and PRPs

## Success Indicators

This skill is working when:

- Posts follow consistent structure
- Writing starts quickly (low friction)
- Posts are easy to scan later
- Project context is captured
- Progress is documented even when small
