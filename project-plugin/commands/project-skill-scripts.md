---
model: opus
description: Analyze plugin skills for supporting script opportunities and create them
args: [--analyze] [--create <plugin/skill>] [--all]
allowed-tools: Bash(chmod *), Bash(mkdir *), Read, Write, Edit, Glob, Grep, TodoWrite
argument-hint: --analyze | --create git-plugin/git-commit-workflow | --all
created: 2026-01-24
modified: 2026-01-24
reviewed: 2026-01-24
---

# /project:skill-scripts

Analyze plugin skills to identify opportunities where supporting scripts would improve performance (fewer tokens, faster execution, consistent results), then optionally create those scripts.

## Usage

- `/project:skill-scripts` or `/project:skill-scripts --analyze` - Scan all skills, report candidates
- `/project:skill-scripts --create git-plugin/git-commit-workflow` - Create script for specific skill
- `/project:skill-scripts --all` - Analyze and create scripts for all high-scoring candidates

## Phase 1: Run Analysis Script

Execute the analyzer to get structured data on all skills:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/project-discovery/scripts/analyze-skills.sh" "$(git rev-parse --show-toplevel 2>/dev/null || echo '.')"
```

Parse the output to identify:
- Skills already with scripts (current coverage)
- High-scoring candidates (score >= 8)
- Script type recommendations (context-gather, workflow, multi-tool, utility)

## Phase 2: Deep Analysis (for --create or --all)

For each candidate skill, read the SKILL.md and identify:

### 2.1 Script Opportunity Patterns

| Pattern | Script Type | Example |
|---------|-------------|---------|
| Multiple sequential git/gh commands | context-gather | Collect status + diff + log + issues |
| Multi-phase workflow (Phase 1, 2, 3...) | workflow | Run all phases in sequence |
| Project type detection + conditional execution | multi-tool | Detect linters, run appropriate one |
| Repeated command with different args | utility | Run same tool across multiple targets |
| Structured output assembly | context-gather | Build JSON/table from multiple sources |

### 2.2 Evaluate Benefit

Before creating a script, verify it provides real value:

| Criterion | Threshold | Benefit |
|-----------|-----------|---------|
| Commands replaced | >= 4 individual tool calls | Token savings |
| Output consistency | Variable AI-composed vs deterministic | Reliability |
| Error handling | Multiple failure points | Robustness |
| Reuse frequency | Used in multiple contexts | Maintainability |

Skip if the skill's bash usage is:
- Single commands with simple flags
- Interactive/creative (needs AI judgment per invocation)
- Already well-structured with few commands

## Phase 3: Create Scripts

### 3.1 Script Template

All supporting scripts follow this structure:

```bash
#!/usr/bin/env bash
# <Description>
# Usage: bash <script-name>.sh [args]
#
# <What this replaces and why it's better>

set -uo pipefail

# Parse arguments
# ...

echo "=== <SECTION NAME> ==="

# Structured output with key=value pairs
echo "KEY=value"

# Section separators for parsing
echo "--- <subsection> ---"

echo "=== COMPLETE ==="
```

### 3.2 Script Design Principles

| Principle | Implementation |
|-----------|----------------|
| Structured output | Use `KEY=value`, `--- section ---`, `=== PHASE ===` markers |
| Error resilience | Use `2>/dev/null`, `|| true`, `|| echo "fallback"` |
| Bounded output | Pipe through `head -N`, limit find results |
| No side effects | Scripts should be read-only unless explicitly named otherwise |
| Portable | Use POSIX-compatible constructs where possible |
| Self-documenting | Header comment explains usage and what it replaces |

### 3.3 File Placement

```
<plugin>-plugin/skills/<skill-name>/scripts/<script-name>.sh
```

Script naming conventions:
- `discover.sh` - Discovery/exploration scripts
- `detect-and-fix.sh` - Detection + action scripts
- `<noun>-context.sh` - Context-gathering scripts (commit-context, pr-context)
- `<noun>-scan.sh` - Scanning/analysis scripts
- `analyze-<noun>.sh` - Analysis scripts

### 3.4 Update SKILL.md

After creating the script, add a "Recommended" section to the SKILL.md:

```markdown
## <Action Name> (Recommended)

<Brief description of what the script does>:

\`\`\`bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/<skill-name>/scripts/<script-name>.sh"
\`\`\`

The script outputs: <list key outputs>. See [scripts/<script-name>.sh](scripts/<script-name>.sh) for details.
```

Place this section:
- Before the manual workflow it replaces (if replacing a workflow)
- Near the top of the execution section (if adding context-gathering)
- After the "When to Use" section (if it's the primary action)

### 3.5 Make Executable

```bash
chmod +x <path-to-script>
```

### 3.6 Update Modified Date

Update the `modified:` field in the SKILL.md frontmatter to today's date.

## Phase 4: Report

Present results in this format:

```markdown
## Skill Scripts Analysis

### Current Coverage
- X/Y skills have supporting scripts

### Scripts Created
| Plugin | Skill | Script | Type | Commands Replaced |
|--------|-------|--------|------|-------------------|
| ... | ... | ... | ... | ... |

### Remaining Candidates
| Plugin | Skill | Score | Type | Recommendation |
|--------|-------|-------|------|----------------|
| ... | ... | ... | ... | ... |

### Next Steps
- [ ] Test scripts in target project contexts
- [ ] Commit changes with conventional commit message
```

## Phase 5: Commit (if changes made)

Stage and commit with:

```
feat(<affected-plugins>): add supporting scripts to skills
```

Include in the commit body:
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
