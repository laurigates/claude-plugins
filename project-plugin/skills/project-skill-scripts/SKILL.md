---
model: sonnet
name: project-skill-scripts
description: Analyze plugin skills to identify opportunities where supporting scripts would improve performance (fewer tokens, faster execution, consistent results), then optionally create those scripts.
args: "[--analyze] [--create <plugin/skill>] [--all]"
allowed-tools: Bash(chmod *), Bash(mkdir *), Read, Write, Edit, Glob, Grep, TodoWrite
argument-hint: "--analyze | --create git-plugin/git-commit-workflow | --all"
created: 2026-01-24
modified: 2026-02-14
reviewed: 2026-02-14
---

# /project:skill-scripts

Analyze plugin skills to identify opportunities where supporting scripts would improve performance (fewer tokens, faster execution, consistent results), then optionally create those scripts.

## When to Use This Skill

| Use this skill when... | Use alternative when... |
|------------------------|--------------------------|
| Analyzing skill improvement opportunities | Need to create a single script for a skill |
| Bulk script creation across plugins | One-off script for one specific need |
| Measuring coverage of scripts across portfolio | Script generation is already done |

## Context

- Plugin root: !`git rev-parse --show-toplevel 2>/dev/null`
- Total plugins: !`find . -maxdepth 2 -name 'plugin.json' -type f 2>/dev/null`
- Skills with scripts: !`find . -name 'scripts/*.sh' -type f 2>/dev/null`

## Parameters

Parse `$ARGUMENTS` for:

- `--analyze`: Scan all skills, report candidates (default)
- `--create <plugin/skill>`: Create script for specific skill only
- `--all`: Analyze and create scripts for all high-scoring candidates

## Execution

Execute this skill script analysis and creation workflow:

### Step 1: Run analysis script

Execute analyzer to get structured data on all skills:

1. Run analyzer: `bash "${CLAUDE_PLUGIN_ROOT}/skills/project-discovery/scripts/analyze-skills.sh" $(git rev-parse --show-toplevel 2>/dev/null || echo '.')`
2. Parse output to identify:
   - Current coverage (skills with scripts)
   - High-scoring candidates (score >= 8)
   - Script type recommendations

### Step 2: Analyze candidates (--create or --all modes)

For each candidate skill:

1. Read SKILL.md to understand the workflow
2. Identify script opportunity patterns:
   - Multiple sequential git/gh commands → context-gather script
   - Multi-phase workflow → workflow script
   - Project type detection + conditional execution → multi-tool script
   - Repeated command with different args → utility script
3. Evaluate benefit: >= 4 tool calls, consistency, error handling, reuse frequency
4. Skip if: single simple commands, interactive/creative, already well-structured

### Step 3: Create scripts

For approved candidates:

1. Use standard script template with structured output (KEY=value, section markers)
2. Follow design principles: structured output, error resilience, bounded output, portable
3. Place in `<plugin>/skills/<skill-name>/scripts/<script-name>.sh`
4. Make executable: `chmod +x <path>`
5. Update SKILL.md with "Recommended" section referencing the script
6. Update `modified:` date in frontmatter

### Step 4: Report results

Present findings:
- Current coverage (X/Y skills have scripts)
- Scripts created (plugin, skill, script, type, commands replaced)
- Remaining candidates (plugin, skill, score, type, recommendation)
- Next steps (test, commit)

### Step 5: Commit changes

If scripts created:

```
feat(<affected-plugins>): add supporting scripts to skills
```

Include in body:
- Which scripts were created
- What they replace (token/call savings)
- Which SKILL.md files were updated

## Examples

### Analyze Only

```
$ /project:skill-scripts --analyze

Skill Scripts Analysis

Current Coverage: 5/191 skills have supporting scripts

Top Candidates:
  git-plugin/gh-cli-agentic         score=14  type=context-gather
  kubernetes-plugin/kubectl-debugging score=12  type=multi-tool
  testing-plugin/playwright-testing   score=10  type=workflow
```

### Create for Specific Skill

```
$ /project:skill-scripts --create testing-plugin/playwright-testing

Analyzing testing-plugin/playwright-testing...
Found: 6 bash blocks, 3 phases, 12 commands

Creating scripts/run-tests.sh...
- Consolidates: test discovery, execution, report parsing
- Replaces: 5 individual tool calls
- Output: structured test results with file:line references

Updated SKILL.md with "Recommended" section.
```

## Error Handling

| Situation | Action |
|-----------|--------|
| Skill has no bash patterns | Skip, report "no script opportunity" |
| Script already exists | Report existing, ask to overwrite |
| SKILL.md is read-only | Report error, suggest manual update |
| Plugin not found | List available plugins |
