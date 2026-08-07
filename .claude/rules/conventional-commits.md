---
created: 2026-02-14
modified: 2026-08-07
reviewed: 2026-08-07
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

## Scope is a label; the files touched decide what releases

Three inputs, routinely conflated:

| Input | Decides |
|-------|---------|
| Commit **type** (`feat`, `fix`, …) | the bump **size** |
| **Files touched** | **which packages** bump |
| **Scope** | the changelog label — nothing else |

`release-please-config.json` is a 44-package manifest keyed by plugin
directory, so a commit is routed to **every package whose directory it
touches**. A scope matching no package does *not* suppress the release:

| Commit | Released |
|--------|----------|
| `fix(testing-plugin): …` (#2196) | code-quality-plugin, documentation-plugin, testing-plugin — patch |
| `feat(scripts): …` (#2254) | comfyui-plugin, migration-patterns-plugin, testing-plugin — minor |
| `feat(repo): …` (#1971) | all five plugin dirs it touched — minor |

Still write the scope as the plugin directory name: it is what readers see, and
a wrong one mislabels every package the commit touched (`code-quality-plugin`
1.22.1 carries `**testing-plugin:**`). But do not rely on it to *contain* a
release. To keep a plugin unpublished, change no files under its directory, or
use a type that does not bump.

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
