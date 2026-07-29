---
created: 2026-02-14
modified: 2026-07-29
reviewed: 2026-07-29
---

# Conventional Commits Standards

Commit messages **and PR titles** follow `<type>(<scope>): <subject>`. This is
not cosmetic: release-please parses them to decide version bumps, and a
**squash-merge lands the PR title** — not the individual commit subjects — as
the commit message on `main`. So a non-conventional PR title silently breaks
release automation even when every commit inside it was perfectly formatted.

Subjects are imperative, lowercase after the colon, no trailing period.

## Types and the bump each triggers

| Type | Use case | release-please bump |
|------|----------|---------------------|
| `feat` | New feature | **Minor** |
| `fix` | Bug fix | **Patch** |
| `perf` | Performance improvement | **Patch** |
| `refactor` | Code restructure, no behaviour change | None |
| `docs` | Documentation only | None |
| `test` | Test changes | None |
| `ci` | CI/CD configuration | None |
| `build` | Build system or dependencies | None |
| `chore` | Maintenance, tooling | None |
| `revert` | Revert a previous commit | Varies with the reverted type |

A `!` before the colon (`feat(api)!: redesign endpoints`) or a
`BREAKING CHANGE:` footer forces a **major** bump regardless of type.

## Scope is the package name (monorepo)

release-please decides **which package to release** from the scope, so here the
scope must be the plugin directory name:

```
feat(blueprint-plugin): add new command syntax
fix(git-plugin): handle merge conflicts
```

`release-please-config.json` declares 44 plugin components and **no root (`.`)
package**, so a scope that matches no package — including an unscoped bare
`feat:` — produces no release at all. That is the usual reason a merged `feat`
never cut a version, and it is also used deliberately (see the `blueprint`
scope in `CLAUDE.md`, which exists precisely because it matches nothing).

## Issue references

Footer keywords, one per line, after a blank line in the commit body:

| Keyword | Effect |
|---------|--------|
| `Fixes #N` | Closes the issue on merge (bug fixes) |
| `Closes #N` | Closes the issue on merge (features) |
| `Refs #N` | Links without closing |

## Related

- `git-plugin:git-commit-workflow` — staging, composing a message, repairing a wrong one
- `git-plugin:github-pr-title` — PR-title checklist and repair
- `git-plugin:git-commit-trailers` — `BREAKING CHANGE`, `Co-authored-by`, `Signed-off-by`
- `git-plugin:release-please-configuration` — adding a package so a new scope can release
