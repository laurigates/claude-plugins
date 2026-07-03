---
description: Curate library gotchas and project patterns into .claude/rules/ entries for AI context. Use when documenting library knowledge for PRP reuse.
args: "[library-name|project:pattern-name]"
argument-hint: "Library name (e.g., redis, pydantic) or project:pattern-name"
allowed-tools: Read, Write, Glob, Bash, WebFetch, WebSearch, AskUserQuestion
model: opus
created: 2025-12-16
modified: 2026-07-03
reviewed: 2026-02-14
name: blueprint-curate-docs
---

# /blueprint:curate-docs

Curate library or project documentation into `.claude/rules/` entries optimized for AI agents — concise, actionable, gotcha-aware context that is auto-loaded into sessions and referenceable from PRPs.

> **Note:** earlier blueprint versions wrote these entries to `docs/blueprint/ai_docs/`. That location is deprecated — `.claude/rules/` is the canonical home for curated AI context, since rules are loaded by Claude Code natively and shared with every contributor.

**Usage**: `/blueprint:curate-docs [library-name]` or `/blueprint:curate-docs project:[pattern-name]`

## When to Use This Skill

| Use this skill when... | Use alternative when... |
|------------------------|-------------------------|
| Documenting library gotchas for PRP/context reuse | Reading raw documentation for ad-hoc tasks |
| Codifying project patterns as rules | One-time library usage |
| Building a knowledge base under `.claude/rules/` | General library research |

## Context

- Rules directory: !`find . -maxdepth 2 -type d -name rules -path '*/.claude/*'`
- Existing rules: !`find . -maxdepth 3 -path '*/.claude/rules/*' -name "*.md" -type f`
- Rules path override: !`find . -maxdepth 3 -path '*/docs/blueprint/manifest.json' -exec jq -r '.structure.generated_rules_path // ".claude/rules/"' {} +`
- Library in dependencies: !`find . -maxdepth 1 \( -name package.json -o -name pyproject.toml -o -name requirements.txt \) -exec grep -m1 "^$1[\":@=]" {} +`

## Parameters

Parse `$ARGUMENTS`:

- `library-name`: Name of library to document (e.g., `redis`, `pydantic`)
  - Location: `$RULES_DIR/lib-[library-name].md`
  - OR `project:[pattern-name]` for project patterns
  - Location: `$RULES_DIR/[pattern-name].md`

`$RULES_DIR` is `structure.generated_rules_path` from `docs/blueprint/manifest.json` when set, otherwise `.claude/rules/`.

## Execution

Execute complete documentation curation workflow:

### Step 1: Determine target and check existing rules

1. Parse argument to determine if library or project pattern
2. Resolve `$RULES_DIR` (manifest `structure.generated_rules_path`, default `.claude/rules/`)
3. Check if a rule for this library/pattern already exists in `$RULES_DIR`
4. If exists → Ask: Update in place or skip?
5. Check project dependencies for library version

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

### Step 4: Create the rule entry

Generate the file at `$RULES_DIR/lib-[library-name].md` or `$RULES_DIR/[pattern-name].md` (see [REFERENCE.md](REFERENCE.md#template)).

**Never overwrite a hand-authored rule.** If a file with the target name exists and was not produced by this skill, pick a distinct name (e.g. `lib-[library-name]-gotchas.md`) or ask.

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
5. Report completion, including the rule path so PRPs can reference it

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Resolve rules dir | `jq -r '.structure.generated_rules_path // ".claude/rules/"' docs/blueprint/manifest.json` |
| List existing rules | `ls .claude/rules/ 2>/dev/null` |
| Check library version | `grep "{library}" package.json pyproject.toml 2>/dev/null \| head -1` |
| Search for patterns | Use grep on src/ for project patterns |
| Fast research | Use WebSearch for common issues instead of fetching docs |

---

For the rule template, section guidelines, and example entries, see [REFERENCE.md](REFERENCE.md).
