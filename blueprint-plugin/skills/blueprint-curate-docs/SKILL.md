---
model: opus
description: "Curate library or project documentation for ai_docs to optimize AI context"
args: "[library-name|project:pattern-name]"
argument-hint: "Library name (e.g., redis, pydantic) or project:pattern-name"
allowed-tools: Read, Write, Glob, Bash, WebFetch, WebSearch, AskUserQuestion
created: 2025-12-16
modified: 2026-02-17
reviewed: 2026-02-14
name: blueprint-curate-docs
---

# /blueprint:curate-docs

Curate library or project documentation into ai_docs entries optimized for AI agents - concise, actionable, gotcha-aware context that fits in PRPs.

**Usage**: `/blueprint:curate-docs [library-name]` or `/blueprint:curate-docs project:[pattern-name]`

## When to Use This Skill

| Use this skill when... | Use alternative when... |
|------------------------|-------------------------|
| Creating ai_docs for PRP context | Reading raw documentation for ad-hoc tasks |
| Documenting library patterns for reuse | One-time library usage |
| Building knowledge base for project | General library research |

## Context

- ai_docs directory: !`test -d docs/blueprint/ai_docs 2>/dev/null`
- Existing library docs: !`find docs/blueprint/ai_docs/libraries -name "*.md" -type f 2>/dev/null`
- Existing project patterns: !`find docs/blueprint/ai_docs/project -name "*.md" -type f 2>/dev/null`
- Library in dependencies: !`grep -m1 "^$1[\":@=]" package.json pyproject.toml requirements.txt 2>/dev/null`

## Parameters

Parse `$ARGUMENTS`:

- `library-name`: Name of library to document (e.g., `redis`, `pydantic`)
  - Location: `docs/blueprint/ai_docs/libraries/[library-name].md`
  - OR `project:[pattern-name]` for project patterns
  - Location: `docs/blueprint/ai_docs/project/[pattern-name].md`

## Execution

Execute complete documentation curation workflow:

### Step 1: Determine target and check existing docs

1. Parse argument to determine if library or project pattern
2. Check if ai_docs entry already exists
3. If exists → Ask: Update or create new version?
4. Check project dependencies for library version

### Step 2: Research and gather documentation

For **libraries**:
- Find official documentation URL
- Search for specific sections relevant to project use cases
- Find known issues and gotchas (WebSearch: "{library} common issues", "{library} gotchas")
- Extract key sections with WebFetch

For **project patterns**:
- Search codebase for pattern implementations: `grep -r "{pattern}" src/`
- Identify where and how it's used
- Document conventions and variations
- Extract real code examples from project

### Step 3: Extract key information

1. **Use cases**: How/why this library/pattern is used in project
2. **Common operations**: Most frequent uses
3. **Patterns we use**: Project-specific implementations (with file references)
4. **Configuration**: How it's configured in this project
5. **Gotchas**: Version-specific behaviors, common mistakes, performance pitfalls, security considerations

Sources for gotchas: GitHub issues, Stack Overflow, team experience, official docs warnings.

### Step 4: Create ai_docs entry

Generate file at appropriate location (see [REFERENCE.md](REFERENCE.md#template)):
- `docs/blueprint/ai_docs/libraries/[library-name].md` OR
- `docs/blueprint/ai_docs/project/[pattern-name].md`

Include all sections from template: Quick Reference, Patterns We Use, Configuration, Gotchas, Testing, Examples.

Keep under 200 lines total.

### Step 5: Add code examples

Include copy-paste-ready code snippets from:
- Project codebase (reference actual files and line numbers)
- Official documentation examples
- Stack Overflow solutions
- Personal implementation experience

### Step 6: Update task registry

Update the task registry entry in `docs/blueprint/manifest.json`:

```bash
jq --arg now "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --argjson processed "${ITEMS_PROCESSED:-0}" \
  --argjson created "${ITEMS_CREATED:-0}" \
  '.task_registry["curate-docs"].last_completed_at = $now |
   .task_registry["curate-docs"].last_result = "success" |
   .task_registry["curate-docs"].stats.runs_total = ((.task_registry["curate-docs"].stats.runs_total // 0) + 1) |
   .task_registry["curate-docs"].stats.items_processed = $processed |
   .task_registry["curate-docs"].stats.items_created = $created' \
  docs/blueprint/manifest.json > tmp.json && mv tmp.json docs/blueprint/manifest.json
```

### Step 7: Validate and save

1. Verify entry is < 200 lines
2. Verify all code examples are accurate
3. Verify gotchas include solutions
4. Save file
5. Report completion

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Check ai_docs exists | `test -d docs/blueprint/ai_docs && echo "YES" \|\| echo "NO"` |
| List library docs | `ls docs/blueprint/ai_docs/libraries/ 2>/dev/null` |
| Check library version | `grep "{library}" package.json pyproject.toml 2>/dev/null \| head -1` |
| Search for patterns | Use grep on src/ for project patterns |
| Fast research | Use WebSearch for common issues instead of fetching docs |

---

For ai_docs template, section guidelines, and example entries, see [REFERENCE.md](REFERENCE.md).
