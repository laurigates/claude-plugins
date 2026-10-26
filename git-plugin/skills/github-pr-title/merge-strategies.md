# Merge Method — Which One, and What release-please Reads

This file is the single source for choosing a PR's merge method. Other skills
link here instead of restating `--squash` or `--rebase`.

**House default: rebase-merge, unless there is a reason to squash.** Rebasing
keeps each conventional commit on `main`, so a multi-concern PR stays
revertable and cherry-pickable per commit, and stacked children rebase cleanly
because their base commits land as patch-equivalent commits. Squash fits a
single-concern PR, a PR with in-PR fixups or review churn, and anything with
merge commits in its branch.

## The decision rule

git-plugin's `pr-merge-method.py` script decides. Rules run in order and the
first match wins:

| # | When | Method | Why |
|---|------|--------|-----|
| 1 | A human set the label `merge:squash` or `merge:rebase` | that label's method | Explicit override (`OVERRIDE=<label>`) |
| 2 | Bot author, or a `release-please--*` head branch | squash | release-please documents squash and merge commits for release PRs, not rebase; release PRs carry one bot commit |
| 3 | The PR has one commit | squash | Keeps ` (#N)` in the subject on `main` |
| 4 | Any merge commit in the branch | squash | A merge commit cannot be rebased onto `main`. Rebase the branch onto `origin/main` to make it rebase-eligible |
| 5 | Any `fixup!`, `squash!` or `amend!` subject, or a review-churn subject: `address review`, `review findings`, `review gaps`, `review issues`, `after/from/per (code) review`, `apply suggestion`, `wip` (case-insensitive, anywhere in the subject) | squash | The churn would land as its own commits |
| 6 | Any non-conventional subject | squash | release-please silently skips non-conventional commits |
| 7 | Every commit has the same `(type, scope)` | squash | Single concern; one commit says it |
| 8 | In-PR correction: a later commit (a) of type `fix`, `style`, `chore`, `refactor` or `test` touches only files an earlier commit in the PR already changed, or (b) is a `fix` with the same scope as earlier commits that already changed at least half of its files. A PR over 50 commits also squashes, because file overlap is not checked past 50 | squash | A fix to code not yet on `main` would become a phantom changelog line. `docs` commits are exempt from (a): release-please hides `docs` in the changelog, so a docs polish commit does not force a multi-concern PR to squash |
| 9 | Otherwise | rebase | Two or more clean, independent conventional commits |

Rules 4, 5 and 8 are heuristics calibrated against the last 400 merged
claude-plugins PRs (2026-08-29 to 2026-10-24). Over that set the script picks
rebase for 24 and squash for 376: 129 bot or release, 126 with merge commits,
92 single-commit, 14 in-PR corrections, 10 single-concern, 5 review churn. A
`merge:*` label overrides a call you disagree with.

### Running it

```bash
python3 "${CLAUDE_PLUGIN_ROOT}/scripts/pr-merge-method.py" --repo <owner>/<repo> --pr <n>
```

It prints a `KEY=VALUE` contract: `METHOD=rebase|squash`, `REASON=<code>`,
`OVERRIDE=<label|none>`, and `BODY_LINT=<n>` followed by one `LINT_*` line per
finding. Merge with `gh pr merge <n> --<METHOD>`.

Three surfaces use the same script:

| Surface | What it does |
|---------|--------------|
| git-plugin's `check-pr-merge-method.sh` hook (PreToolUse on `gh pr merge`) | Blocks a `--squash`/`--rebase` that disagrees with `METHOD` when no override label is set, and prints the correct command |
| `laurigates/.github` `reusable-merge-method.yml` (caller: `.github/workflows/merge-method.yml`) | Posts a non-required `merge-method` check run whose title names the method, and sets a bot-applied `merge:rebase` or `merge:squash` label |
| `ghm` in the dotfiles zsh config | Merges with the recommended method |

The GitHub merge button defaults to the last method each user used in that
repo (`viewerDefaultMergeMethod`, read-only). The check run title and the label
exist so the right choice is visible in the merge box.

### Making a branch rebase-eligible

| Rule that fired | Fix, then re-run the script |
|-----------------|-----------------------------|
| 4 (merge commit) | `git rebase origin/main` and `git push --force-with-lease`. Sync PR branches by rebase, not by merging `main` in (`git-conflicts`) |
| 5 (fixup or churn) | `GIT_SEQUENCE_EDITOR=: git rebase -i --autosquash origin/main` folds `fixup!` commits into the commits they fix without opening an editor; reword churn commits into `fixup!` form first |
| 8 (in-PR correction) | `REASON` names the earlier commit; `git commit --fixup <sha>` for the correction, then `GIT_SEQUENCE_EDITOR=: git rebase -i --autosquash origin/main` |

Squash is a fine outcome. Rewrite history only when the commits really are
independent concerns worth keeping apart.

### Body lint (PR_BODY repos, squash only)

The PR body lands in the squash commit only where the repo's
`squash_merge_commit_message` is `PR_BODY` ([§ Repo settings](#repo-settings)).
The script reads that setting itself and reports it as `SQUASH_BODY=`; it lints
the PR body only when `SQUASH_BODY=PR_BODY` and `METHOD=squash`. Each finding
is a `LINT_*` line:

| Finding | Why |
|---------|-----|
| `- [ ]` / `- [x]` checklist | Noise in `git log` |
| `<!-- … -->` comment | Template residue, invisible on GitHub, visible in `git log` |
| Markdown heading | Reads poorly as a commit body |
| `Closes #N after merge` | Prose after the keyword still closes `#N`; use `Refs #N` for follow-ups |
| Body last updated before the newest commit | The body likely describes an older state of the branch (same test as `check-pr-metadata-on-push.sh`) |

## Repo settings

Merge settings for laurigates repos are OpenTofu-managed in `laurigates/gitops`
(`main.tf`). Never PATCH them by hand; change them there.

| Setting | Value |
|---------|-------|
| `allow_rebase_merge` | `true` |
| `allow_squash_merge` | `true` |
| `allow_merge_commit` | `false` (the ruleset also requires linear history) |
| `squash_merge_commit_title` | `PR_TITLE` |
| `squash_merge_commit_message` | `COMMIT_MESSAGES` on `release_please` repos (claude-plugins among them), `PR_BODY` elsewhere |

The squash body follows `squash_merge_commit_message`. Release-please repos use
`COMMIT_MESSAGES` because of laurigates/.github#40: release-please's parser
threw on parentheses inside a fenced block in a `PR_BODY` squash body and
silently dropped every commit in the range. The upstream fix,
googleapis/release-please#2936 (merged 2026-10-16), is not in a release yet,
and the pinned release-please-action v4.4.1 bundles `^17.3.0`. The split moves
to `PR_BODY` everywhere once an action release bundles release-please
≥ 17.11.3 (laurigates/gitops#318).

Check a repo rather than assuming:

```bash
gh api repos/{owner}/{repo} --jq '{squash: .allow_squash_merge, rebase: .allow_rebase_merge, merge: .allow_merge_commit, title: .squash_merge_commit_title, message: .squash_merge_commit_message}'
```

## What release-please reads per method

release-please never reads the PR. It reads the **commits that land on the
default branch**, and the merge method decides which text becomes those commits.

| Method | Commits on `main` | Subject comes from | Body comes from | PR title matters? | PR body matters? |
|--------|-------------------|--------------------|-----------------|-------------------|------------------|
| **Squash** (`PR_TITLE` / `PR_BODY`) | 1 | PR title (+ ` (#N)`) | PR body | **Yes — decides type/bump** | **Yes — parsed for footers** |
| **Squash** (`PR_TITLE` / `COMMIT_MESSAGES`, release-please repos) | 1 | PR title (+ ` (#N)`) | Concatenated commit messages | **Yes — decides type/bump** | No (commit messages are used, footers included) |
| Squash, GitHub default settings (`COMMIT_OR_PR_TITLE` / `COMMIT_MESSAGES`) | 1 | PR title, **or the lone commit's subject when the PR has one commit** | Concatenated commit messages | Only for multi-commit PRs | No (commit messages are used) |
| **Rebase** | N (one per PR commit) | Each commit's subject | Each commit's body | **No** | **No** |
| Merge commit | N + `Merge pull request #N …` | Each commit's subject | Each commit's body | No (merge commit is non-conventional, ignored) | No |

### Squash with PR_TITLE / PR_BODY

- The PR title is the *only* place the bump type lives. Intermediate commits
  (`wip`, `fix typo`, `address review`) are discarded and need not be conventional.
- A releasable change under a `chore`/`docs`/`refactor` title ships **no release**.
  Retitle before merge; after merge, use `Release-As:` or a commit override ([§ Fixing after merge](#fixing-after-merge)).
- The PR body becomes the commit body, so release-please **parses it**:
  - `BREAKING CHANGE: …` (or `BREAKING-CHANGE:`) as a footer → **major** bump.
  - A line in the footer block shaped like `feat(x): …` / `fix(x): …` is treated
    as an **additional conventional commit** (release-please's multi-change
    footer feature) → extra changelog entries, possibly an extra bump.
  - `Release-As: 1.2.3` → forces that version.
- Prose that merely *quotes* those forms ("this fixes the `BREAKING CHANGE:`
  parsing") belongs in backticks mid-sentence, never at the start of a line in
  the final paragraph.

### Rebase

- Every commit becomes a changelog entry, so every commit must be conventional
  and correctly typed; non-conventional commits are silently skipped, and a
  `fix` + `feat` pair yields a minor bump with two changelog entries. Rules 5–8
  send the branches where that would misreport to squash.
- In a monorepo each commit is attributed to the packages whose files it
  touches, so a PR spanning two plugins gets an accurate entry per plugin.
- PR title and body are discarded — fixing a bad title after the fact has no
  effect.
- GitHub rewrites every commit, so `main` gets new SHAs and the commits lose
  their signature verification.

### Merge commit

As rebase, plus a `Merge pull request` commit release-please ignores. Disabled
in gitops (`allow_merge_commit = false`).

## Fixing after merge

| Problem | Fix |
|---------|-----|
| Wrong type/scope in a squashed commit | Edit the **merged PR's body** to add a `BEGIN_COMMIT_OVERRIDE` … `END_COMMIT_OVERRIDE` block containing the corrected message(s); release-please uses it on the next run |
| Missed release entirely | Empty commit `chore: release X` with `Release-As: X.Y.Z` footer (see `git-commit-trailers`) |
| Accidental `BREAKING CHANGE` footer | Commit override on the merged PR; if the release PR already exists, regenerate it after the override |

```markdown
BEGIN_COMMIT_OVERRIDE
fix(auth): handle expired refresh tokens
feat(auth): add device-code login
END_COMMIT_OVERRIDE
```

release-please documents the override for squash-merged PRs and states it does
not work with plain merges.

## PR body as commit body

On a `PR_BODY` repo a squash-merged PR's body is permanent `git log` content;
on a `COMMIT_MESSAGES` repo (laurigates/gitops#318) the commit messages are.
Write every PR body as a commit body anyway, not a review form, so it lands
cleanly wherever the setting is `PR_BODY`:

| Keep | Drop or move to a comment |
|------|---------------------------|
| What changed and why, in plain paragraphs or a short list | `- [ ]` checklists (render as noise in `git log`) |
| `Fixes #N` / `Closes #N` / `Refs #N` footers | "How to test" steps for reviewers |
| `BREAKING CHANGE:` footer when intended | Headings, screenshots, HTML comments, template boilerplate |
| `Co-authored-by:` trailers | Bot-generated summaries that duplicate the diff |

Shape:

```markdown
<1–3 sentence summary of the change and its motivation>

- <notable change>
- <notable change>

Fixes #123
Refs #99
```

Trailers and footers go in the **last paragraph**, one per line, with no
headings or blank lines between them — that is where both git
(`git interpret-trailers`) and release-please look for them.
