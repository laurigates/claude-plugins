# fix(github-actions-plugin): fix lint errors in github-workflow-auto-fix SKILL.md context commands

CI 'Lint Context Commands' fails due to forbidden shell operators in context section of `github-actions-plugin/skills/github-workflow-auto-fix/SKILL.md`.

## Errors

- **Line 30**: `test -f ... && echo ... || echo ...` (banned `&&` and `||` operators)
- **Line 32**: `grep ... | sed ...` (banned pipe operator)
- **Line 33**: `gh secret list | grep -c ... || echo ...` (banned pipe and `||` operators)

## Fix

Replace with `find`-based discovery and let execution logic handle missing output.

See `.claude/rules/agentic-permissions.md` for patterns.

## Suggested replacements

```markdown
## Context

- Workflow exists: !`find .github/workflows -maxdepth 1 -name 'github-workflow-auto-fix.yml' 2>/dev/null`
- Current workflows: !`find .github/workflows -maxdepth 1 -name '*.yml' 2>/dev/null`
- Workflow names: !`find .github/workflows -maxdepth 1 -name '*.yml' -exec head -5 {} \; 2>/dev/null`
- Claude secrets configured: !`gh secret list 2>/dev/null`
```
