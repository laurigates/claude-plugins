---
description: |
  Check which project dependencies have newer versions available using `bun
  outdated`. Use when the user wants to audit dependency freshness, spot major
  version updates before upgrading, decide between `bun update` (in-range) and
  `bun update --latest`, or review a single package. Triggers: "check outdated",
  "what can be upgraded", "show newer versions", "review dependency updates".
args: "[package]"
argument-hint: "Optional package name to check specific dependency"
allowed-tools: Bash, Read
created: 2025-12-20
modified: 2026-04-19
reviewed: 2025-12-20
name: bun-outdated
---

# /bun:outdated

Check which dependencies have newer versions available.

## Execution

```bash
bun outdated
```

## Output Format

Shows table with:
- Package name
- Current version
- Wanted version (within semver range)
- Latest version

## Follow-up Actions

**Update within ranges:**
```bash
bun update
```

**Update to latest (ignore ranges):**
```bash
bun update --latest
```

**Interactive update:**
```bash
bun update --interactive
```

**Update specific package:**
```bash
bun update <package>
```

## Post-check

1. Report count of outdated packages
2. Highlight major version updates (breaking changes)
3. Suggest `bun update` or `bun update --latest` based on findings
