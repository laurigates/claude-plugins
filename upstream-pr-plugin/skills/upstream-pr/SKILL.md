---
name: upstream-pr
description: |
  Submit a single commit from a heavily-diverged fork back to upstream as a
  clean PR. Handles eligibility checks (patch-id matching against upstream),
  cherry-pick with re-derive fallback when conflicts are too dense, commit-
  message scrubbing of fork-local context, and pre-flight regression
  verification against the upstream baseline. Use when the fork has
  substantially diverged from upstream and direct rebase is not viable, or
  when the user asks to "send X upstream", "backport to upstream", or
  "open an upstream PR".
args: "<sha> [--topic <slug>]"
allowed-tools: Bash(git status *), Bash(git diff *), Bash(git log *), Bash(git show *), Bash(git remote *), Bash(git fetch *), Bash(git switch *), Bash(git checkout *), Bash(git cherry-pick *), Bash(git reset *), Bash(git commit *), Bash(git push *), Bash(git stash *), Bash(git rev-list *), Bash(git rev-parse *), Bash(git branch *), Bash(git cat-file *), Bash(git patch-id *), Bash(gh pr *), Bash(gh repo *), Bash(bash *), Bash(uv *), Bash(pytest *), Bash(ruff *), Bash(python3 *), Read, Edit, Write, Grep, Glob, TodoWrite
argument-hint: "<sha-to-send-upstream>"
created: 2026-04-29
modified: 2026-04-29
reviewed: 2026-04-29
---

# /upstream-pr

Submit a single commit from a heavily-diverged fork back to upstream as a clean, regression-free PR.

## When to Use This Skill

| Use this skill when... | Use `/git:upstream-pr` instead when... |
|------------------------|----------------------------------------|
| Fork has substantially diverged from upstream | Fork and upstream are roughly aligned |
| Cherry-pick may produce many conflicts on shared modules | Single commit applies cleanly |
| You need patch-id matching for already-applied content | You want a quick cherry-pick + cross-fork PR |
| The change touches files that may be fork-only | All touched files exist upstream |
| The PR needs commit-message scrubbing (fork issue refs, Claude trailers) | Commit messages are already upstream-clean |
| Pre-flight regression check against upstream baseline matters | The change is trivial enough to skip pre-flight |

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

## Context

- Current branch: !`git branch --show-current`
- Working tree: !`git status --porcelain=v2 --branch`
- Remotes: !`git remote -v`
- Config file: !`find .claude -maxdepth 1 -name 'upstream-pr.local.md'`

## Parameters

Parse from `$ARGUMENTS`:

| Parameter | Required | Description |
|-----------|----------|-------------|
| `<sha>` | Yes | Commit SHA on the fork to send upstream |
| `--topic <slug>` | No | Topic slug for branch name; auto-derived from commit subject if omitted |

## Execution

Execute this upstream-PR workflow:

### Step 1: Check eligibility

Run the eligibility check before touching any branch:

```bash
bash "${CLAUDE_SKILL_DIR}/scripts/check-eligibility.sh" <sha>
```

Exit codes drive next steps:

| Exit | Meaning | Action |
|------|---------|--------|
| `0` | Every touched file exists upstream and content is novel | Proceed to Step 2 |
| `1` | At least one fork-only file | Stop. Tell the user the change isn't standalone-PR-able; predecessor feature must land first |
| `3` | Content already applied upstream under a different SHA | Stop. Report the matching upstream commit; nothing to PR |

The patch-id check (`git patch-id --stable`) catches re-applied content from maintainer re-merges or squashes — even when the SHA differs.

### Step 2: Prepare the branch

Derive a topic slug from the commit subject if `--topic` was not provided. Then:

```bash
bash "${CLAUDE_SKILL_DIR}/scripts/prepare-branch.sh" <topic-slug> <sha>
```

The script:

1. Verifies a clean working tree
2. Re-runs the eligibility check
3. Fetches the upstream remote
4. Creates `<branch_prefix><topic-slug>` from `<upstream_remote>/main` (or `/master`)
5. Cherry-picks `<sha>`
6. Reports any conflict files

### Step 3: Resolve conflicts (if any)

When the cherry-pick produces conflicts, **preserve upstream's surrounding shape**, not the fork's. The goal is the smallest readable diff against upstream — a maintainer must see the change make sense in upstream's current code, not in the fork's.

#### When to abort and re-derive

If the cherry-pick produces dozens of conflict blocks across multiple files (typical when upstream and fork have drifted heavily on shared modules), abort and re-derive instead of fighting hunks:

```bash
git cherry-pick --abort
git checkout -b <branch> <upstream_remote>/main
# Re-apply the change against upstream's actual current files.
```

Re-derive is the right call when:

- The original commit is a **mechanical, re-applicable transform** (e.g. `print()` → logging, deprecation rename, lint-rule auto-fixes) — the rules transfer cleanly even if line numbers don't.
- Upstream's version of the file has **additional lines the fork removed** — re-derive lets you cover them with the same heuristic rather than rationalizing missing hunks.
- The cherry-pick conflict count exceeds roughly **20 blocks across >2 files**.

Heuristic: extract the original commit's `before → after` map (e.g. `git show <sha> | grep -E '^[-+].*pattern'`) and use it as the rulebook when re-applying against upstream. The PR body should disclose the re-derive (see template below).

### Step 4: Pre-flight regression check

For refactor / cleanup PRs, verify lint and test parity against the **pristine upstream baseline**, not against the fork. This catches stray formatter touches, accidental import reordering, and indentation drift from Edit-tool replacements.

If `linter_cmd` and `test_cmd` are configured, run a stash roundtrip:

```bash
# Baseline (pristine upstream):
git stash push -- <changed-files>
<linter_cmd> <changed-files> 2>&1 | tail -1   # error count
<test_cmd> 2>&1 | tail -1                     # pass count
git stash pop

# After (with your changes): run the same two commands and compare.
```

Both numbers must match (or improve). Quote both in the PR body's "Testing Performed" section.

For Python files, also run `python3 -c "import ast; ast.parse(open(F).read())"` on every edited file — catches indentation breaks that ruff might miss on already-warning-laden upstream code.

### Step 5: Scrub the commit message

Run the scrub helper:

```bash
bash "${CLAUDE_SKILL_DIR}/scripts/scrub-commit.sh" --check
```

If violations are reported, run without `--check` to amend interactively:

```bash
bash "${CLAUDE_SKILL_DIR}/scripts/scrub-commit.sh"
```

The scrub rules:

- **Strip local issue references** — `Closes #74`, `Addresses #19`, etc. point at the fork's tracker, not upstream's.
- **Strip Claude trailers** — `Co-authored-by: Claude ...`, `Generated with [Claude Code]`. Upstream doesn't follow that convention.
- **Soften fork-specific tooling** — if the body cites a tool upstream doesn't run (`bandit B607`, `ty`, `vulture`), describe the underlying problem instead.
- **Keep the conventional-commit prefix** — `fix(security):`, `feat(parser):`, etc.

The amend wraps `git commit --amend` with `PRE_COMMIT_ALLOW_NO_CONFIG=1` because upstream may have no `.pre-commit-config.yaml` and a locally-installed pre-commit hook would otherwise refuse the commit.

### Step 6: Verify diff hygiene

Before pushing, verify with:

```bash
git diff <upstream_remote>/main..HEAD
```

Every hunk should be defensible to a maintainer who has never seen the fork.

- Don't bundle formatter cleanups with the fix. Keep upstream's existing import order even if the fork's linter would reformat. Upstream may have unusual indentation (e.g. 21-space rather than 20-space blocks) — preserve it; Edit-tool replacements that change leading whitespace by even one character will break the parse.
- One commit per PR. If the cherry-pick produced multiple commits, squash before pushing.

### Step 7: Push and open the PR

```bash
git push origin <branch>

gh pr create --repo <upstream_repo> --base main \
  --head <fork-owner>:<branch> \
  --title "<conventional-commit subject>" \
  --body "<see body template below>"
```

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

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Eligibility check | `bash check-eligibility.sh <sha>` (exit 0/1/3) |
| Prepare branch | `bash prepare-branch.sh <topic> <sha>` |
| Scrub check (CI mode) | `bash scrub-commit.sh --check` |
| Diff against upstream | `git diff <upstream_remote>/main..HEAD --stat` |
| Cross-fork PR | `gh pr create --repo <upstream_repo> --head <fork-owner>:<branch>` |
| Patch-id of HEAD | `git show HEAD \| git patch-id --stable` |

## Related Skills

- [git-plugin: git-upstream-pr](../../../git-plugin/skills/git-upstream-pr/SKILL.md) — simpler cherry-pick path for low-divergence forks
- [git-plugin: git-fork-workflow](../../../git-plugin/skills/git-fork-workflow/SKILL.md) — fork management and upstream sync
- [git-plugin: git-conflicts](../../../git-plugin/skills/git-conflicts/SKILL.md) — conflict resolution patterns
