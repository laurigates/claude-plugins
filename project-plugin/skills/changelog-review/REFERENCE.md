# Changelog Review — Reference

Supporting material for the `changelog-review` skill, loaded on demand.

## Report Format

When producing a human-readable review (rather than the CI triage issue), use
this structure:

```markdown
# Claude Code Changelog Review

**Review Date**: YYYY-MM-DD
**Versions Reviewed**: X.X.X to Y.Y.Y
**Previous Check**: YYYY-MM-DD (vX.X.X)

## Summary

- **New versions**: N
- **High-impact changes**: N
- **Medium-impact changes**: N
- **Action items**: N

## High-Impact Changes

### [Version] - Change Title

**Impact**: Breaking/Security/Deprecation
**Affected plugins**: plugin1, plugin2
**Required action**: Description of what needs to be done

## Medium-Impact Changes

### [Version] - Change Title

**Impact**: New feature/Enhancement
**Opportunity**: How plugins could benefit
**Suggested plugins**: plugin1, plugin2

## Action Items

- [ ] Item 1 (high priority)
- [ ] Item 2 (medium priority)

## Next Steps

1. Create issues for high-priority items
2. Schedule review of medium-impact changes
3. Update version tracking file
```
