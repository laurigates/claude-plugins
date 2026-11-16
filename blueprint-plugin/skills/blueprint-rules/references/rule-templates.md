# blueprint-rules — Rule File Templates (Steps 4–5)

Templates for the "Add a new rule" action. Use the global template when the rule applies to all files, and the scoped template when it applies to the glob patterns the user gave.

**Global rule template**:
```markdown
# {Rule Name}

## Overview
{Brief description of when this rule applies}

## Requirements
- {Requirement 1}
- {Requirement 2}

## Examples
{Code examples if applicable}
```

**Scoped rule template** (with `paths` frontmatter):
```markdown
---
paths:
  - "src/components/**/*.{ts,tsx}"
---

# {Rule Name}

## Overview
{Brief description - applies only to matched paths}

## Requirements
- {Requirement 1}
- {Requirement 2}
```

Brace expansion is supported: `*.{ts,tsx}` matches both `.ts` and `.tsx` files.
Glob patterns follow standard syntax: `**` for recursive, `*` for single level.

## Common Rule Patterns

Suggested file locations and `paths:` patterns for frequent rule types:

| Rule Type | Suggested Path | Scope Pattern |
|-----------|---------------|---------------|
| React components | `rules/frontend/react.md` | `["**/*.{tsx,jsx}"]` |
| API handlers | `rules/backend/api.md` | `["src/{api,routes}/**/*"]` |
| Database models | `rules/backend/models.md` | `["src/{models,db}/**/*"]` |
| Test files | `rules/testing.md` | `["**/*.{test,spec}.*"]` |
| Documentation | `rules/docs.md` | `["**/*.md", "docs/**/*"]` |
| Config files | `rules/config.md` | `["*.config.{js,ts,mjs}", ".env*"]` |
