---
description: "Bun outdated: check which deps have newer versions. Use when auditing freshness, spotting major updates, or deciding between bun update and bun update --latest."
args: "[package]"
argument-hint: "Optional package name to check specific dependency"
allowed-tools: Bash, Read
created: 2025-12-20
modified: 2026-05-09
reviewed: 2026-04-25
name: bun-outdated
---

# /bun:outdated

Check which dependencies have newer versions available.

## When to Use This Skill

| Use this skill when... | Use bun-lockfile-update instead when... |
|---|---|
| Auditing dependency freshness without making changes | Actually updating dependencies and regenerating bun.lockb |
| Spotting major version updates before deciding to upgrade | Running `bun update` / `bun update --latest` workflows |
| Reviewing a single package's available versions | Resolving lockfile conflicts or security patch updates |

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
