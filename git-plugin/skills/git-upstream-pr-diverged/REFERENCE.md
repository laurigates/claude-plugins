# /git:upstream-pr-diverged — Reference

Detail moved out of [SKILL.md](SKILL.md): the per-project configuration file and the built-in PR body template.

## Configuration

Per-project configuration lives at `.claude/upstream-pr.local.md` (gitignored). All fields are optional; sensible defaults apply.

```markdown
---
upstream_remote: upstream
upstream_repo: owner/repo
branch_prefix: pr-upstream/
linter_cmd: uv run ruff check
test_cmd: uv run pytest -q
pr_body_template_path: docs/UPSTREAM_PR_TEMPLATE.md
---

# Notes

Free-form notes — fork drift hotspots, files to never touch upstream, etc.
```

| Field | Default | Used by |
|-------|---------|---------|
| `upstream_remote` | `upstream` | All scripts |
| `upstream_repo` | Parsed from `git remote get-url <upstream_remote>` | `gh pr create --repo` |
| `branch_prefix` | `pr-upstream/` | Branch name in `prepare-branch.sh` |
| `linter_cmd` | (empty — pre-flight skipped) | Pre-flight stash-roundtrip |
| `test_cmd` | (empty — pre-flight skipped) | Pre-flight stash-roundtrip |
| `pr_body_template_path` | (empty — built-in template) | PR body |

Add `.claude/*.local.md` to `.gitignore`.

## Built-in PR body template

If `pr_body_template_path` is configured, use that template; otherwise use the built-in template:

```markdown
## Description

<one or two paragraphs explaining the problem and the fix from the
maintainer's perspective — not from the fork's perspective>

## Related Issue(s)

None.  <or upstream issue numbers only>

## Type of Change

- [x] Bug fix (non-breaking change that fixes an issue)

## Testing Performed

- [x] `<linter_cmd> <changed-files>` — N issues (matches upstream baseline)
- [x] `<test_cmd>` — M passed (matches upstream baseline)

## Notes

Originally authored on a downstream fork; the branch was cut from
`<upstream_repo>:main` and a single commit cherry-picked onto it so
it applies cleanly.

<If re-derived: "The fork's version of this change collided heavily with
upstream's current code; the diff was re-derived against upstream's files
using the original commit's transformation rules.">
```
