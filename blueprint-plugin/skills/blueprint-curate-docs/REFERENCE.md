# blueprint-curate-docs REFERENCE

## ai_docs Template

```markdown
# [Library/Pattern Name]

**Version:** X.Y.Z
**Last Updated:** YYYY-MM-DD
**Use Case:** [Why we use this in this project]

## Quick Reference

### [Common Operation 1]
\`\`\`language
# Code snippet that can be directly copied
\`\`\`

## Patterns We Use

### [Pattern Name]
[When to use this pattern]

\`\`\`language
# Full example as used in this project
# Reference: src/path/file.ts:15-25
\`\`\`

## Configuration

\`\`\`
VAR_NAME=value
\`\`\`

## Gotchas

### Gotcha 1: [Title]
**Issue:** [What can go wrong]
**Solution:**
\`\`\`language
# Correct approach
\`\`\`

## Testing

### How to Mock
\`\`\`language
# Mocking pattern for tests
\`\`\`

## References
- [Official docs](https://...)
- [Related code](src/path/file.ts)
```

## Section Guidelines

| Section | Guidelines | Lines |
|---------|---|---|
| Quick Reference | Most common operations, copy-paste ready | 20-30 |
| Patterns We Use | Project-specific implementations with line refs | 30-50 |
| Configuration | Environment variables and project config | 10-20 |
| Gotchas | Known issues with solutions | 40-60 |
| Testing | Mocking and test patterns | 20-30 |
| References | Links to docs and related code | 5-10 |

## Line Count Target
< 200 lines total. Concise and actionable, not comprehensive documentation.

## Code Example Format

Include file/line references:
```typescript
// Reference: src/auth/handlers.ts:42-55
function login(req, res) {
  // Implementation
}
```

## Gotcha Format

Always include solution:
```
### Gotcha: Connection pool exhaustion
**Issue:** Pool defaults to 10, causes timeouts under load
**Solution:** Set pool size to CPU count × 4
```
