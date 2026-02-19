# fix(ci): increase max-turns for Claude Skill Quality Review workflow

The 'Plugin PR Checks' workflow uses `--max-turns 10` for Claude Code, which is insufficient for reviewing PRs with multiple changed skill files. The job failed with `error_max_turns` (used all 10 turns without completing).

## Location

`.github/workflows/plugin-pr-checks.yml`, line 70:

```yaml
claude_args: "--model haiku --max-turns 10"
```

## Fix

Increase `max-turns` to 20-30 for the compliance job:

```yaml
claude_args: "--model haiku --max-turns 25"
```

## Context

When a PR changes multiple skill files, the Claude Skill Quality Review step needs to:
1. Read the quality rules at `.claude/rules/skill-quality.md`
2. Read each changed SKILL.md file
3. Check each file against the quality checklist
4. Leave review comments for each issue found

With 3+ changed skill files, 10 turns is not enough to complete all these steps.
