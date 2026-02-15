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

## Rule Categories

Generate separate rule files by category:

| File | Content | Source Commits |
|------|---------|---|
| `code-style.md` | Naming, formatting, structure rules | `refactor:`, `style:` |
| `testing-standards.md` | Testing approach, coverage, fixtures | `test:` |
| `api-conventions.md` | Endpoint patterns, error handling | `feat:` (api scope), `fix:` (api scope) |
| `error-handling.md` | Exception patterns, fallbacks | `fix:` (error-related) |
| `dependencies.md` | Package management, version policies | `chore:` (deps), `build:` |
| `security-practices.md` | Auth, validation, secrets handling | `fix:` (security), `feat:` (security) |

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
When conflict with existing rules in `.claude/rules/`:

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
