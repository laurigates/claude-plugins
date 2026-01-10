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

Capture small wins fast. No fluff.

```markdown
---
title: <What you did>
date: YYYY-MM-DD
type: quick-update
project: <project-name>
tags: []
status: draft
---

# <Title>

<What you did. One sentence.>

## Changes

- <Concrete change>
- <Another change>

---
*~Xh*
```

## Project Update Format

Document meaningful progress.

```markdown
---
title: <Project>: <What was done>
date: YYYY-MM-DD
type: project-update
project: <project-name>
tags: []
status: draft
---

# <Title>

<One sentence: what changed and why it matters>

## What I Did

<Details. Code if relevant.>

```language
// code
```

## Problems Solved

<What broke, how you fixed it>

## Results

<What works now. Metrics if you have them.>

## Next

- [ ] <Next action>

---
*~Xh*
```

## Retrospective Format

Look back at a project or time period.

```markdown
---
title: "Retro: <Project or Period>"
date: YYYY-MM-DD
type: retrospective
project: <project-name>
tags: [retrospective]
status: draft
---

# <Title>

## Timeline

- **Start**: <Initial state>
- **Milestone**: <What happened>
- **End**: <Current state>

## Worked

- <Success>

## Didn't Work

- <Failure or challenge>

## Lessons

<What you know now>

## Next

<Plans or closure>

---
*Duration: <timeframe> | Status: ongoing/paused/complete*
```

## Tutorial Format

Teach how to do something.

```markdown
---
title: "How to <Do the Thing>"
date: YYYY-MM-DD
type: tutorial
project: <project-name>
tags: [tutorial]
status: draft
---

# <Title>

## Prerequisites

- <What you need>

## Steps

### 1. <Step>

```language
// code
```

### 2. <Step>

```language
// code
```

## Troubleshooting

**<Issue>**: <Solution>

## Resources

- [<Link>](<url>)

---
*Tested: <versions>*
```

## Deep Dive Format

Explain a complex topic or decision.

```markdown
---
title: "<Topic>"
date: YYYY-MM-DD
type: deep-dive
project: <project-name>
tags: [deep-dive]
status: draft
---

# <Title>

<The question you're answering>

## Background

<Minimum context needed>

## Problem

<What prompted this>

## Analysis

### <Aspect>

<Details, code, examples>

## Insights

1. <Key takeaway>
2. <Another>

## Implications

<What this means going forward>

---
*~Xh | Confidence: low/medium/high*
```

## Writing Style Guidelines

### Voice & Tone

| Guideline | Example |
|-----------|---------|
| Direct statements | "Fixed the auth bug" not "I was able to successfully fix..." |
| Facts first | Lead with what happened, not buildup |
| No filler phrases | Cut "basically", "actually", "in order to", "the fact that" |
| Specific over vague | "Reduced load time from 3s to 400ms" not "Made it faster" |
| One idea per sentence | Split compound sentences |

### What to Cut

| Remove | Replace With |
|--------|--------------|
| "I decided to..." | Just state what you did |
| "It's worth noting that..." | State the fact directly |
| "As you can see..." | Nothing - let the content speak |
| "In this post I will..." | Nothing - just do it |
| Introductory paragraphs | Jump to the point |
| Redundant conclusions | End when you're done |

### Formatting

- **Headers for navigation** - scan-friendly structure
- **Bullet points** - faster to read than prose
- **Code blocks** - show, don't describe
- **Bold sparingly** - only for key terms
- **One paragraph = one point** - 1-3 sentences max

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
