---
created: 2026-06-03
modified: 2026-06-24
reviewed: 2026-07-04
paths:
  - "**/SKILL.md"
  - "**/REFERENCE.md"
  - "renovate.json"
---
# Version Pinning in Skill Examples

Skill markdown ships copy-pasteable examples that pin tool versions — GitHub
Action refs (`uses:`), Docker base images (`FROM`), service/container images
(`image:`), and pre-commit hook revisions (`rev:`). Left unmanaged, every one
of these is a slow-rotting fact: the day it lands it is correct, and every day
after it drifts. The W22 version audit found ~150 such pins across
`configure-plugin` alone, several of them years stale, and one (`trivy-action`)
where a **hand-transcribed commit SHA did not match the version in its own
trailing comment** — the exact failure mode hand-maintenance invites.

This rule makes those pins a managed dependency surface instead of a manual
chore.

## The division of labor

| Concern | Owner | Mechanism |
|---------|-------|-----------|
| Keeping pins *fresh* | Renovate | `customManagers` in `renovate.json` open update PRs |
| Pinning to *immutable* refs (commit SHA / sha256) | Renovate | `pinDigests: true`, scoped to `**/skills/**/*.md` |
| Keeping pins *visible* to Renovate | CI guard | `scripts/check-version-pin-coverage.sh` fails on an executable pin no manager can see |
| Supply-chain settling time | Renovate | global `minimumReleaseAge: 3 days` |

The guard's job is **coverage, not form**: it does not demand a SHA, it demands
that every executable pin matches a shape Renovate manages. SHA-vs-tag is left
to Renovate so the guard never deadlocks against its own first run.

## The pin convention

Pin to an **immutable commit SHA / sha256 digest, with the human-readable
version as a trailing comment** wherever the datasource supports digests:

```yaml
# GitHub Action — SHA pin + version comment (preferred)
- uses: actions/checkout@08c6903cd8c0fde910a37f88322edcfb5dd907a8 # v5.0.0

# Docker base image — digest pin + version comment
FROM python@sha256:abc...def # 3.14-slim

# pre-commit hook — tag rev (github-tags has no stable digest surface here)
- repo: https://github.com/astral-sh/ruff-pre-commit
  rev: v0.15.15
```

**Do not hand-transcribe SHAs.** Renovate resolves them from the API and writes
the matching `# vX.Y.Z` comment itself; the trivy incident is what
hand-transcription buys you. Land examples in tag form (`@v5`) if you must write
them by hand — Renovate's first run converts them to the SHA+comment form
correctly.

## What is managed vs. illustrative

| Pin shape | Managed? | Notes |
|-----------|----------|-------|
| `uses: owner/repo@<ref>` | ✅ | github-tags datasource; both tag and SHA+comment forms |
| `FROM image:tag[@sha256:…]` | ✅ | docker datasource |
| `image: owner/img:tag[@sha256:…]` | ✅ | docker datasource (compose services, CI service containers) |
| `repo: github.com/… ` + `rev:` | ✅ | github-tags datasource |
| `node-version:` / `python-version:` | ❌ | runtime-selector inputs — not a manager surface |
| `additional_dependencies: ["@scope/pkg@x"]` | ❌ | npm-in-pre-commit; out of scope for v1 |
| Version strings in **prose tables** | ❌ | illustrative — prefer referencing the canonical pinned block over restating |

Illustrative versions (prose tables, `*-version:` inputs) are deliberately
unmanaged. When a number must appear in prose, link to the canonical pinned
example rather than copying the digits — a restated version is a second thing to
forget to update.

## Authoring checklist

- [ ] New executable pin uses one of the four managed shapes above
- [ ] Hand-written pins land in tag form; let Renovate add the SHA + comment
- [ ] No version number is *restated* in prose when it can reference a code block
- [ ] `bash scripts/check-version-pin-coverage.sh --strict` passes
- [ ] `npx --yes --package renovate renovate-config-validator renovate.json` passes if you touched `renovate.json`

## Scope

`renovate.json` customManagers and the guard currently cover **this repository's
skill markdown only**. Extending the convention to sibling repos
(`git-repo-agent`, `vault-agent`) is a follow-up, not a precondition.

## Related

- `.claude/rules/regression-testing.md` — the guard is the regression check for the trivy SHA-mismatch class
- `.claude/rules/structured-script-output.md` — the guard emits the `=== … ===` / `STATUS=` / `ISSUE_COUNT=` convention
- `.claude/rules/agentic-optimization.md` — machine-readable pinning as a general principle
- `renovate.json` — the customManagers and the digest-pinning packageRule
