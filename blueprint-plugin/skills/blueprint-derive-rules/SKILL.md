---
model: opus
created: 2026-01-30
modified: 2026-01-30
reviewed: 2026-01-30
description: "Derive Claude rules from git commit log decisions. Newer commits override older decisions when conflicts exist."
args: "[--since DATE] [--scope SCOPE]"
argument-hint: "--since 2024-01-01 for date range, --scope api for specific area"
allowed_tools: [Read, Write, Glob, Grep, Bash, AskUserQuestion, Task]
name: blueprint-derive-rules
---

Derive Claude rules from significant decisions found in git commit history. When newer commits contradict older decisions, the newer decision takes precedence.

**Use Case**: Extract implicit project decisions from git history and codify them as Claude rules for consistent AI-assisted development.

**Arguments**:
- `--since DATE`: Analyze commits from specific date (e.g., `--since 2024-01-01`)
- `--scope SCOPE`: Focus on specific area (e.g., `--scope api`, `--scope testing`)

**Prerequisites**:
- Project is a git repository with commit history
- Blueprint Development initialized (`docs/blueprint/` exists)

---

## Phase 1: Git History Analysis

### 1.1 Check Prerequisites

```bash
git rev-parse --git-dir 2>/dev/null
ls docs/blueprint/manifest.json 2>/dev/null
```

If not a git repository → Error: "This directory is not a git repository."
If blueprint not initialized → Suggest `/blueprint:init` first.

### 1.2 Analyze Commit Quality

```bash
# Total commits in scope
git log --oneline {scope} | wc -l

# Conventional commits percentage
git log --oneline --format="%s" {scope} | grep -cE "^(feat|fix|docs|style|refactor|perf|test|build|ci|chore)\(?.*\)?:" || echo 0
```

Higher conventional commit percentage = higher confidence in extracted rules.

### 1.3 Extract Decision-Bearing Commits

**Decision Indicators** (patterns that suggest rule-worthy decisions):

| Pattern | Rule Category |
|---------|---------------|
| `refactor:` + consistent pattern | Code style rule |
| `fix:` repeated for same issue type | Prevention rule |
| `feat!:` / `BREAKING CHANGE:` | Architecture rule |
| `chore:` + tooling changes | Tooling rule |
| `style:` + formatting decisions | Formatting rule |
| `test:` + testing approach | Testing rule |
| `docs:` + documentation pattern | Documentation rule |

```bash
# Extract decision commits
git log --format="%H|%s|%b" {scope} | grep -E "(always|never|must|should|prefer|avoid|instead of|replaced|switched|adopted|dropped)" | head -50
```

### 1.4 Group by Domain

Group extracted decisions by domain:

| Domain | Keywords |
|--------|----------|
| `code-style` | formatting, naming, structure, organize |
| `testing` | test, coverage, mock, fixture, assertion |
| `api-design` | endpoint, route, handler, response, error |
| `error-handling` | catch, throw, error, exception, fallback |
| `dependencies` | add, remove, upgrade, replace, migrate |
| `security` | auth, token, secret, validate, sanitize |
| `performance` | cache, optimize, lazy, async, batch |
| `documentation` | document, comment, readme, docstring |

name: blueprint-derive-rules
---

## Phase 2: Decision Extraction

### 2.1 Parallel Agent Analysis

Launch parallel agents to analyze git history efficiently:

**Agent 1: Refactoring Patterns**
```
<Task subagent_type="Explore" prompt="Analyze git log for refactor: commits. Identify consistent patterns that suggest code style rules. Look for: naming conventions, file organization, import patterns, code structure decisions. Return findings with commit SHAs.">
```

**Agent 2: Fix Patterns**
```
<Task subagent_type="Explore" prompt="Analyze git log for repeated fix: commits addressing same issue types. Identify preventable patterns that should become rules. Look for: common bugs, security fixes, performance issues. Return findings with commit SHAs.">
```

**Agent 3: Breaking Changes**
```
<Task subagent_type="Explore" prompt="Analyze git log for feat!: and BREAKING CHANGE commits. Identify architectural decisions that should become rules. Look for: API changes, dependency migrations, pattern switches. Return findings with commit SHAs.">
```

**Agent 4: Tooling Decisions**
```
<Task subagent_type="Explore" prompt="Analyze git log for chore: and build: commits. Identify tooling and workflow decisions that should become rules. Look for: linter configs, formatter settings, CI changes, script patterns. Return findings with commit SHAs.">
```

### 2.2 Consolidate Findings

Merge agent results, grouping by:
1. Domain (code-style, testing, api-design, etc.)
2. Chronology (newest to oldest)
3. Frequency (how often the pattern appears)

### 2.3 Conflict Resolution

When multiple commits address the same topic:

**Conflict Detection**:
```bash
# Find commits mentioning same topic
git log --format="%H|%ai|%s" | grep -i "{topic}" | sort -t'|' -k2 -r
```

**Resolution Strategy**:
- **Newer overrides older**: Latest decision wins
- **Higher frequency wins**: If 5 commits say X and 1 says Y, X wins
- **Breaking changes override**: `feat!:` trumps regular `feat:`

Mark overridden decisions as "superseded" with reference to the newer decision.

### 2.4 User Confirmation

For significant decisions, confirm with user:

```
question: "Found decision: '{decision}' from commit {sha} ({date}). Should this become a rule?"
options:
  - label: "Yes, create rule"
    description: "Add to .claude/rules/"
  - label: "Yes, but modify"
    description: "Let me adjust the wording"
  - label: "Skip this one"
    description: "Don't create a rule for this"
  - label: "Mark as superseded"
    description: "This was overridden by a later decision"
```

---

## Phase 3: Rule Generation

### 3.1 Rule Template

Generate rules in `.claude/rules/` with this structure:

```markdown
# {Rule Title}

{Rule description derived from commit message/body}

## Source

- **Commit**: {sha} ({date})
- **Type**: {feat|fix|refactor|chore}
- **Confidence**: {High|Medium|Low}

## Rule

{Clear, actionable rule statement}

## Examples

### Do
```{language}
{Good example from commit diff or codebase}
```

### Don't
```{language}
{Counter-example if available}
```

## Supersedes

{List any earlier decisions this overrides, or "None"}

name: blueprint-derive-rules
---
*Derived from git history via /blueprint:derive-rules*
```

### 3.2 Rule Categories

Generate separate rule files by category:

| File | Content |
|------|---------|
| `code-style.md` | Naming, formatting, structure rules |
| `testing-standards.md` | Testing approach, coverage, fixtures |
| `api-conventions.md` | Endpoint patterns, error handling |
| `error-handling.md` | Exception patterns, fallbacks |
| `dependencies.md` | Package management, version policies |
| `security-practices.md` | Auth, validation, secrets handling |

### 3.3 Handle Existing Rules

Check for existing rules that might conflict:

```bash
ls .claude/rules/*.md 2>/dev/null
```

If conflicts found:
```
question: "Found existing rule '{rule_name}' that may conflict with git-derived rule. How to proceed?"
options:
  - label: "Git decision overrides"
    description: "Update existing rule with git-derived content"
  - label: "Keep existing rule"
    description: "Existing rule takes precedence"
  - label: "Merge both"
    description: "Combine into comprehensive rule"
  - label: "Create separate rule"
    description: "Add git-derived as additional rule"
```

---

## Phase 4: Manifest Update & Reporting

### 4.1 Update Manifest

Add derived rules to `docs/blueprint/manifest.json`:

```json
{
  "derived_rules": {
    "last_derived_at": "{ISO timestamp}",
    "commits_analyzed": {count},
    "rules_generated": {count},
    "source_commits": [
      {
        "sha": "{sha}",
        "date": "{date}",
        "rule_file": ".claude/rules/{file}.md",
        "confidence": "{High|Medium|Low}"
      }
    ],
    "superseded_decisions": [
      {
        "old_sha": "{sha}",
        "new_sha": "{sha}",
        "topic": "{topic}"
      }
    ]
  }
}
```

### 4.2 Summary Report

```
Rules Derived from Git History

**Analysis Summary**
- Commits analyzed: {N}
- Decision commits found: {N}
- Conflicts resolved: {N} (newer overrides older)

**Rules Generated**

| Rule File | Decisions | Source Commits |
|-----------|-----------|----------------|
| code-style.md | {N} | {sha1}, {sha2} |
| testing-standards.md | {N} | {sha3} |
| api-conventions.md | {N} | {sha4}, {sha5} |

**Superseded Decisions**
- {topic}: {old_sha} ({old_date}) → {new_sha} ({new_date})

**Confidence Levels**
- High: {N} rules (explicit commit messages)
- Medium: {N} rules (inferred from patterns)
- Low: {N} rules (single occurrence)

**Next Steps**
1. Review generated rules in .claude/rules/
2. Run `/blueprint:generate-rules` to add PRD-based rules
3. Run `/blueprint:sync` to check for stale content
```

### 4.3 Prompt Next Action

```
question: "Rules derived from git history. What would you like to do?"
options:
  - label: "Review generated rules"
    description: "Open rule files for verification"
  - label: "Derive more from PRDs"
    description: "Run /blueprint:generate-rules for PRD-based rules"
  - label: "Re-run with different scope"
    description: "Analyze a specific time range or area"
  - label: "I'm done for now"
    description: "Exit - rules are saved"
```

name: blueprint-derive-rules
---

## Phase 5: Incremental Updates

### 5.1 Detect New Commits

On subsequent runs, only analyze new commits:

```bash
# Get last analyzed commit from manifest
last_sha=$(jq -r '.derived_rules.source_commits[-1].sha // ""' docs/blueprint/manifest.json)

# Analyze commits since then
git log --format="%H|%s|%b" ${last_sha}..HEAD
```

### 5.2 Override Detection

Check if new commits override existing rules:

```bash
# Find commits that might override existing rules
for rule in .claude/rules/*.md; do
  topic=$(head -1 "$rule" | sed 's/# //')
  git log --format="%H|%s" ${last_sha}..HEAD | grep -i "$topic"
done
```

If overrides found, prompt user to update rule or create superseding rule.

---

## Error Handling

| Condition | Action |
|-----------|--------|
| No git repository | Error with clear message |
| No conventional commits | Lower confidence, use raw message analysis |
| Very few commits | Warn about limited data, generate tentative rules |
| No decision patterns found | Report "no rule-worthy decisions found" |
| Conflicting decisions in same commit | Ask user to clarify intent |

name: blueprint-derive-rules
---

## Tips

- **Conventional commits**: Projects with conventional commits produce better rules
- **Commit messages matter**: Detailed commit bodies provide richer context
- **Review generated rules**: AI-derived rules should be verified
- **Incremental is better**: Run periodically to capture new decisions
- **Scope for focus**: Use `--scope` to focus on specific areas
