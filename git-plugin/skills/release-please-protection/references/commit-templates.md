# Conventional Commit Guide

Moved verbatim from `SKILL.md`. Commit templates to offer in place of a manual changelog or version edit.

## Conventional Commit Guide

The skill provides instant conventional commit templates based on the type of change:

### Feature Addition
```
feat(scope): brief description

Detailed explanation of what was added and why.
Can be multiple paragraphs.

Refs: #issue-number
```

### Bug Fix
```
fix(scope): brief description

Explanation of the bug and how it was fixed.

Fixes: #issue-number
```

### Breaking Change
```
feat(scope)!: brief description

BREAKING CHANGE: Explanation of what breaks and migration path.

Details about the new behavior.

Refs: #issue-number
```

### Chore (No Version Bump)
```
chore(scope): brief description

Maintenance work that doesn't affect functionality.
Examples: dependency updates, refactoring, docs.
```
