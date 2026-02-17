---
model: haiku
name: blog-post
description: Create a blog post about your work with guided prompts and templates
description: Create a blog post about your work with guided prompts and templates
args: "[type] [--project <name>] [--title <title>]"
allowed-tools: Read, Write, Edit, Grep, Glob, Bash(hugo *), Bash(date *), TodoWrite, AskUserQuestion
argument-hint: "quick-update | project-update | retrospective | tutorial | deep-dive"
created: 2026-01-10
modified: 2026-02-14
reviewed: 2026-02-14
---

# /blog:post

Create a blog post about your work with minimal friction. Gathers context automatically and provides structured templates to reduce blank-page anxiety.

## When to Use This Skill

| Use this skill when... | Use alternative when... |
|------------------------|--------------------------|
| Capturing work quickly into a blog post | Need detailed documentation -> Project wiki/docs |
| Want templates to reduce blank-page anxiety | Writing a technical tutorial -> `/blog:post tutorial` |
| Need git context auto-populated | Creating portfolio summary -> Different workflow |

## Context

- Blog directory: !`find . -maxdepth 1 -type d \( -name blog -o -name posts -o -name _posts \) -print -quit 2>/dev/null`
- Project name: !`git remote get-url origin 2>/dev/null`
- Recent commits: !`git rev-list --count --since="7 days ago" HEAD 2>/dev/null`
- Current branch: !`git branch --show-current 2>/dev/null`

## Parameters

Parse `$ARGUMENTS` for:

- `type`: Post type (quick-update, project-update, retrospective, tutorial, deep-dive)
  - If not provided, ask user to select
- `--project <name>`: Specify project name (default: detected from git)
- `--title <title>`: Specify post title (default: ask user)
- `--edit`: Open in editor after creation (default: show filepath)

## Execution

Execute this blog post creation workflow:

### Step 1: Gather context

Detect project name and recent git history:

1. Use `git log` to get recent commits
2. Extract project name from git remote or directory
3. If blog directory doesn't exist, ask where to save posts

### Step 2: Determine post type

If type argument not provided, ask user to select from five options:

- Quick Update (5-15 min)
- Project Update (20-45 min)
- Retrospective (45-90 min)
- Tutorial (1-3 hours)
- Deep Dive (2-5 hours)

### Step 3: Ask targeted questions based on post type

For each type, ask 1-2 focused questions:
- Quick Update: "What did you just do?"
- Project Update: "Main accomplishment?" and "What was interesting?"
- Retrospective: "What period/project?" and "One thing to remember?"
- Tutorial: "What are you teaching?" and "Why document this?"
- Deep Dive: "What topic?" and "Key insight to share?"

### Step 4: Generate post file

1. Determine where to save (blog directory, ~/blog/, or custom path)
2. Generate filename: `YYYY-MM-DD-<slugified-title>.md`
3. Create file with frontmatter:
   - `date`: Today
   - `project`: Detected or specified
   - `type`: Selected type
   - `status`: draft
4. Pre-fill content sections with placeholders and git context as comments

### Step 5: Offer writing assistance

Ask what user would like to do:
- "Help me write it" → Walk through each section interactively
- "I'll write it myself" → Show filepath
- "Add more context" → Pull more git history and files for reference

### Step 6: Finalize post

1. Present review checklist (title, content, tags, next steps)
2. Ask: "Is this post ready to publish?" (draft or published)
3. Output summary with file path and quick actions

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Get project name | `git remote get-url origin 2>/dev/null \| sed 's/.*\///' \| sed 's/\.git$//'` |
| Recent commits | `git log --since="7 days ago" --format="%h %s" 2>/dev/null \| head -10` |
| Find blog directory | `ls -d blog/ posts/ content/blog/ content/posts/ _posts/ 2>/dev/null \| head -1` |
| Current date | `date +%Y-%m-%d` |
| Get today's commits | `git log --since="1 day ago" --format="- %s" 2>/dev/null` |

## Quick Reference

| Post Type | Time | Use Case |
|-----------|------|----------|
| Quick Update | 5-15 min | Small wins, log entries |
| Project Update | 20-45 min | Milestone, feature complete |
| Retrospective | 45-90 min | Reflection on period/project |
| Tutorial | 1-3 hours | Teach how to do something |
| Deep Dive | 2-5 hours | Explain complex concepts |
