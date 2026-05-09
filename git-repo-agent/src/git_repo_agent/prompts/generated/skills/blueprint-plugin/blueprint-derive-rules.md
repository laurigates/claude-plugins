# /blueprint:derive-rules

Extract project decisions from git commit history and codify them as Claude rules. Newer commits override older decisions when conflicts exist.

**Use case**: Derive implicit project patterns from git history to establish consistent AI-assisted development guidelines.

**Usage**: `/blueprint:derive-rules [--since DATE] [--scope SCOPE]`


## Execution

Execute the complete git-to-rules derivation workflow:


### Step 0: Resolve the output path

Read `structure.generated_rules_path` from `docs/blueprint/manifest.json` (default `.claude/rules/`):

```bash
RULES_DIR=$(jq -r '.structure.generated_rules_path // ".claude/rules/"' docs/blueprint/manifest.json)
mkdir -p "$RULES_DIR"
```

Use `$RULES_DIR` for all subsequent reads/writes and conflict checks. Hand-written files in the parent `.claude/rules/` are intentionally invisible to this skill (issue #1043).


### Step 1: Verify prerequisites

1. If not a git repository → Error: "This directory is not a git repository"
2. If Blueprint not initialized → Suggest `/blueprint:init` first
3. If few commits (< 20) → Warn: "Limited commit history; derived rules may be incomplete"


### Step 2: Analyze git history quality

1. Calculate total commits in scope
2. Calculate conventional commits percentage
3. Report quality: Higher % = higher confidence in extracted rules
4. Parse `--since` and `--scope` flags to determine analysis range


### Step 3: Extract decision-bearing commits

Use parallel agents to analyze git history efficiently (see [REFERENCE.md](REFERENCE.md#git-analysis)):

- **Agent 1**: Analyze `refactor:` commits for code style patterns
- **Agent 2**: Analyze `fix:` commits for repeated issue types
- **Agent 3**: Analyze `feat!:` and `BREAKING CHANGE:` commits for architecture decisions
- **Agent 4**: Analyze `chore:` and `build:` commits for tooling decisions

Consolidate findings by domain (code-style, testing, api-design, etc.), chronologically (newest first), and by frequency (most common wins).


### Step 4: Resolve conflicts

When multiple commits address the same topic:

1. Detect conflicts using pattern matching: `git log --format="%H|%ai|%s" | grep "{topic}"`
2. Apply resolution strategy:
   - **Newer overrides older**: Latest decision wins
   - **Higher frequency wins**: If 5 commits say X and 1 says Y, X wins
   - **Breaking changes override**: `feat!:` trumps regular commits
3. Mark overridden decisions as "superseded" with reference to newer decision
4. Confirm significant decisions with user via report to orchestrator


### Step 5: Generate rules in `$RULES_DIR`

For each decision, generate rule file using template from [REFERENCE.md](REFERENCE.md#rule-template). Write each file to `$RULES_DIR/<filename>.md` (the configured `structure.generated_rules_path`):

1. Extract source commit, date, type
2. Determine confidence level (High/Medium/Low based on commit frequency and clarity)
3. Generate actionable rule statement
4. Include code examples from commit diffs
5. Reference any superseded earlier decisions
6. Add `paths` frontmatter when the rule is naturally scoped to specific file types (see [REFERENCE.md](REFERENCE.md#rule-categories) for suggested patterns per category)

Generate separate rule files by category (see [REFERENCE.md](REFERENCE.md#rule-categories)):
- `code-style.md`, `testing-standards.md`, `api-conventions.md`, `error-handling.md`, `dependencies.md`, `security-practices.md`

Path-scope rules where appropriate — e.g., `testing-standards.md` scoped to test files reduces context noise when working on non-test code.


### Step 6: Handle conflicts with existing rules

Check for conflicts with existing rules **only under `$RULES_DIR`** (never the parent `.claude/rules/`, which may contain hand-authored content unrelated to blueprint):

1. If conflicts found → Ask user: Git-derived overrides existing rule, or keep existing?
2. Apply user choice: Update, merge, or keep separate
3. Document conflict resolution in rule file


### Step 7: Update task registry

Update the task registry entry in `docs/blueprint/manifest.json`:

```bash
jq --arg now "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg sha "$(git rev-parse HEAD 2>/dev/null)" \
  --argjson processed "${COMMITS_ANALYZED:-0}" \
  --argjson created "${RULES_DERIVED:-0}" \
  '.task_registry["derive-rules"].last_completed_at = $now |
   .task_registry["derive-rules"].last_result = "success" |
   .task_registry["derive-rules"].context.commits_analyzed_up_to = $sha |
   .task_registry["derive-rules"].stats.runs_total = ((.task_registry["derive-rules"].stats.runs_total // 0) + 1) |
   .task_registry["derive-rules"].stats.items_processed = $processed |
   .task_registry["derive-rules"].stats.items_created = $created' \
  docs/blueprint/manifest.json > tmp.json && mv tmp.json docs/blueprint/manifest.json
```


### Step 8: Update manifest and report

1. Update `docs/blueprint/manifest.json` with derived rules metadata: timestamp, commits analyzed, rules generated, source commits
2. Generate completion report showing:
   - Commits analyzed (count and date range)
   - Conventional commits percentage
   - Rules generated by category
   - Confidence scores per rule
   - Any conflicts resolved
3. Prompt user for next action: Review rules, execute derived development workflow, or done


# blueprint-derive-rules REFERENCE

Reference material for git analysis patterns, rule templates, and conflict resolution procedures.


## Git Analysis Patterns


### Decision Indicators

| Pattern | Rule Category | Examples |
|---------|---|---|
| `refactor:` + consistent pattern | Code style | File organization, naming conventions, imports |
| `fix:` repeated for same issue | Prevention | Common bugs, security issues, performance problems |
| `feat!:` / `BREAKING CHANGE:` | Architecture | API changes, dependency migrations, pattern switches |
| `chore:` + tooling changes | Tooling | Linter configs, formatter settings, CI changes |
| `style:` + formatting | Formatting | Indentation, spacing, code formatting |
| `test:` + testing approach | Testing | Test patterns, coverage, fixtures |
| `docs:` + documentation | Documentation | Documentation patterns, comment style |


### Extraction Commands

**Extract decision-bearing commits:**
```bash
git log --format="%H|%s|%b" {scope} | grep -E "(always|never|must|should|prefer|avoid|instead of|replaced|switched|adopted|dropped)"
```

**Group by domain:**
```bash
git log --oneline --format="%s" {scope} | sed 's/^[a-z]*(\([^)]*\)).*/\1/' | sort | uniq -c | sort -rn
```

**Detect conflicts (same topic):**
```bash
git log --format="%H|%ai|%s" | grep -i "{topic}" | sort -t'|' -k2 -r
```


## Rule Template

Rules may include an optional `paths` frontmatter to scope them to specific file types or directories. Add `paths` when the rule only applies to certain parts of the codebase — this reduces context noise and keeps rules relevant.

**Global rule** (applies to all files — no frontmatter needed):
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
\`\`\`{language}
{Good example from commit diff or codebase}
\`\`\`


### Don't
\`\`\`{language}
{Counter-example if available}
\`\`\`


## Supersedes

{List any earlier decisions this overrides, or "None"}

---

*Derived from git history via /blueprint:derive-rules*
```

**Path-scoped rule** (add `paths` frontmatter when rule only applies to specific files):
```markdown
---
paths:
  - "{glob-pattern}"
  - "{glob-pattern}"
---


# {Rule Title}

{Rule description — applies only to matched paths}


## Source
...
```


## Rule Categories

Generate separate rule files by category. Apply `paths` frontmatter where the rule is naturally scoped to specific file types or directories:

| File | Content | Source Commits | Suggested `paths` |
|------|---------|---|---|
| `code-style.md` | Naming, formatting, structure rules | `refactor:`, `style:` | *(global — omit paths)* |
| `testing-standards.md` | Testing approach, coverage, fixtures | `test:` | `["**/*.{test,spec}.*", "tests/**/*", "test/**/*"]` |
| `api-conventions.md` | Endpoint patterns, error handling | `feat:` (api scope), `fix:` (api scope) | `["src/{api,routes}/**/*", "**/*controller*", "**/*handler*"]` |
| `error-handling.md` | Exception patterns, fallbacks | `fix:` (error-related) | *(global — omit paths)* |
| `dependencies.md` | Package management, version policies | `chore:` (deps), `build:` | `["package.json", "go.mod", "Cargo.toml", "pyproject.toml", "*.lock"]` |
| `security-practices.md` | Auth, validation, secrets handling | `fix:` (security), `feat:` (security) | *(global — omit paths)* |

**Path scoping guidance**: Use `paths` when the rule only makes sense in context of specific files. Omit `paths` for rules that apply universally (e.g., error handling philosophy, security mindset). Use brace expansion for concise patterns: `*.{ts,tsx}`, `src/{api,routes}/**/*`.


## Conflict Resolution Strategy


### Detection
Find commits addressing same topic:
```bash
git log --format="%H|%ai|%s" | grep -i "{topic}" | sort -t'|' -k2 -r
```


### Resolution Rules
1. **Newer overrides older**: Latest decision wins
2. **Higher frequency wins**: If 5 commits say X and 1 says Y, X wins
3. **Breaking changes override**: `feat!:` trumps regular commits


### Handling Existing Rules
When conflict with existing rules under the configured `structure.generated_rules_path` (default `.claude/rules/`). Hand-written files outside that directory are never inspected:

| Option | Action |
|--------|--------|
| Git-derived overrides | Update existing rule with git-derived content |
| Keep existing | Use existing rule, document git decision as alternative |
| Merge both | Combine into comprehensive rule with both perspectives |
| Create separate | Add git-derived as additional rule |


### Superseding Pattern
Document overridden decisions:
```markdown

## Supersedes

- **Previous rule**: `code-style.md` - Naming convention v1 (commit abc1234)
- **Reason**: Updated to match newer pattern in commit def5678 (more common, 7 commits)
```


## Confidence Scoring

Rate confidence based on:

| Score | Criteria |
|-------|----------|
| **High** | Pattern appears 5+ times, explicit commit message, breaking change |
| **Medium** | Pattern appears 2-4 times, clear intent but not explicit |
| **Low** | Pattern appears 1 time, inferred from code change only |


## Manifest Format

```json
{
  "derived_rules": {
    "last_derived_at": "ISO-8601-timestamp",
    "commits_analyzed": N,
    "conventional_commits_percentage": 85,
    "rules_generated": N,
    "rules_by_category": {
      "code-style": N,
      "testing-standards": N,
      "api-conventions": N,
      "error-handling": N,
      "dependencies": N,
      "security-practices": N
    },
    "source_commits": [
      {
        "sha": "{sha}",
        "date": "ISO-8601",
        "type": "refactor|fix|feat|chore",
        "message": "commit message",
        "rule_generated": "code-style.md"
      }
    ]
  }
}
```


## Tips

- **High commit quality**: More conventional commits = more reliable rules
- **Frequency matters**: Patterns that appear multiple times are more trustworthy
- **Recency wins**: Newer decisions override older ones
- **Breaking changes signal**: `feat!:` or `BREAKING CHANGE` indicates important architectural decision
- **User confirmation**: Always ask about significant decisions before making them rules