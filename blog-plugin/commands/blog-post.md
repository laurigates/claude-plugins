---
description: Create a blog post about your work with guided prompts and templates
args: [type] [--project <name>] [--title <title>]
allowed-tools: Read, Write, Edit, Grep, Glob, Bash, TodoWrite
argument-hint: quick-update | project-update | retrospective | tutorial | deep-dive
created: 2026-01-10
modified: 2026-01-10
reviewed: 2026-01-10
---

# /blog:post

Create a blog post about your work with minimal friction. Gathers context automatically and provides structured templates to reduce blank-page anxiety.

## Quick Start

Just run `/blog:post` - you'll be guided through the rest.

Or specify directly:
- `/blog:post quick-update` - Fast capture of small wins
- `/blog:post project-update --project my-project` - Document progress
- `/blog:post retrospective` - Look back at work done
- `/blog:post tutorial` - Teach something you learned
- `/blog:post deep-dive` - Explain a complex topic

## Phase 1: Context Gathering

### 1.1 Detect Current Project

```bash
# Get git remote name (often matches project name)
git remote get-url origin 2>/dev/null | sed 's/.*\///' | sed 's/\.git$//'
```

```bash
# Get current directory name as fallback
basename "$(pwd)"
```

```bash
# Check for package.json project name
jq -r '.name // empty' package.json 2>/dev/null
```

### 1.2 Gather Recent Work Context

```bash
# Recent commits (last 7 days)
git log --oneline --since="7 days ago" --author="$(git config user.name)" 2>/dev/null | head -10
```

```bash
# Files changed recently
git diff --stat HEAD~5 2>/dev/null | tail -5
```

```bash
# Current branch
git branch --show-current 2>/dev/null
```

### 1.3 Check for Existing Blog Directory

```bash
# Look for common blog locations
ls -d blog/ posts/ content/blog/ content/posts/ _posts/ 2>/dev/null | head -1
```

If none found, suggest creating `blog/` in project root or a central location.

## Phase 2: Post Type Selection

If type not provided as argument, ask:

```
question: "What kind of post do you want to write?"
options:
  - label: "Quick Update (5-15 min)"
    description: "Captured something small, daily log entry"
  - label: "Project Update (20-45 min)"
    description: "Milestone reached, feature complete, notable progress"
  - label: "Retrospective (45-90 min)"
    description: "Looking back at a project or time period"
  - label: "Tutorial (1-3 hours)"
    description: "Teaching how to do something"
  - label: "Deep Dive (2-5 hours)"
    description: "Explaining complex concepts or decisions"
```

## Phase 3: Quick Prompts

Based on post type, ask minimal questions to get started.

### For Quick Update

```
question: "What did you just do? (one sentence)"
```

### For Project Update

```
question: "What's the main thing you accomplished?"
```

```
question: "What was tricky or interesting about it?"
```

### For Retrospective

```
question: "What project or time period are you reflecting on?"
```

```
question: "What's the one thing you want to remember from this?"
```

### For Tutorial

```
question: "What are you teaching someone to do?"
```

```
question: "What made you want to document this?"
```

### For Deep Dive

```
question: "What topic or question are you exploring?"
```

```
question: "What's the key insight you want to share?"
```

## Phase 4: Generate Post

### 4.1 Determine File Location

If blog directory exists, use it. Otherwise:

```
question: "Where should I save blog posts?"
options:
  - label: "Create blog/ in this project"
    description: "Keep posts with the project"
  - label: "Use ~/blog/"
    description: "Central blog location"
  - label: "Specify custom path"
    description: "You tell me where"
```

### 4.2 Generate Filename

Format: `YYYY-MM-DD-<slugified-title>.md`

```bash
date +%Y-%m-%d
```

### 4.3 Create Post File

Use the appropriate template from the blog-post-writing skill.

**Pre-fill metadata:**
- `date`: Today's date
- `project`: Detected or specified project name
- `status`: draft
- `type`: Selected post type
- `title`: From user input

**Pre-fill content sections:**
- Include recent git context as comments/prompts
- Add placeholder text with guiding questions
- Mark optional sections clearly

### 4.4 Example Generated Quick Update

```markdown
---
title: "<user's one-sentence answer>"
date: 2026-01-10
type: quick-update
project: <detected-project>
tags: []
status: draft
---

# <title>

<Expand on what you did here - or leave the one-liner if that's enough>

## What Changed

<!-- Based on recent commits, you might want to mention: -->
<!-- - commit message 1 -->
<!-- - commit message 2 -->

-

## Why It Matters

<!-- Optional - skip if this is purely a log entry -->

---
*Time spent: ~Xh | Difficulty: low/medium/high*
```

## Phase 5: Writing Assistance

After creating the file, offer:

```
question: "Post created! What would you like to do?"
options:
  - label: "Help me write it"
    description: "Walk through each section together"
  - label: "I'll write it myself"
    description: "Just show me the file path"
  - label: "Add more context"
    description: "Pull in more git history, related files, etc."
```

### If "Help me write it":

Walk through each section of the template:
1. Read the current section
2. Ask a focused question about what to write
3. Draft content based on their answer
4. Move to next section
5. Repeat until complete

### If "Add more context":

```bash
# More detailed git history
git log --since="30 days ago" --oneline --author="$(git config user.name)" 2>/dev/null
```

```bash
# Related files by pattern
fd -e md -e txt . | head -20
```

Offer to include relevant snippets as reference.

## Phase 6: Finalize

### 6.1 Review Checklist

Present to user:
```
Post Review:
- [ ] Title is clear and descriptive
- [ ] Content captures what you want to remember
- [ ] Tags added (if using tags)
- [ ] Next steps or follow-up noted (if applicable)
```

### 6.2 Status Update

```
question: "Is this post ready to publish?"
options:
  - label: "Keep as draft"
    description: "I'll come back to polish it"
  - label: "Mark as published"
    description: "It's ready to share"
```

### 6.3 Summary

```
Blog post created!

File: <full-path-to-file>
Type: <post-type>
Project: <project-name>
Status: <draft|published>

Quick actions:
- Edit: open <filepath>
- View recent posts: ls blog/posts/
- Create another: /blog:post
```

## Shortcuts

For power users who want to skip prompts:

```bash
# Quick update with everything specified
/blog:post quick-update --project my-app --title "Fixed auth bug"

# Create and open in editor
/blog:post project-update --edit
```

## Tips

- **Don't overthink it**: Quick updates can be 2-3 sentences
- **Imperfect is fine**: Draft status exists for a reason
- **Context helps future you**: Include project name and date always
- **Screenshots welcome**: Add to blog/assets/ and reference
- **Link to commits**: `git log --oneline -1` gives you a reference

## Error Handling

- **No git repo**: Use directory name as project, skip commit context
- **No blog directory**: Offer to create one
- **Existing file**: Append timestamp or ask to overwrite
