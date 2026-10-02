# Merge Strategy → What release-please Reads

release-please never reads the PR. It reads the **commits that land on the
default branch**. The merge strategy decides which text becomes those commits.

## Strategy comparison

| Strategy | Commits on `main` | Subject comes from | Body comes from | PR title matters? | PR body matters? |
|----------|-------------------|--------------------|-----------------|-------------------|------------------|
| **Squash** (`squash_merge_commit_title=PR_TITLE`, `squash_merge_commit_message=PR_BODY`) | 1 | PR title (+ ` (#N)`) | PR body | **Yes — decides type/bump** | **Yes — parsed for footers** |
| Squash, default message settings | 1 | PR title, **or the lone commit's subject when the PR has one commit** | Concatenated commit messages | Only for multi-commit PRs | No (commit messages are used) |
| **Rebase** | N (one per PR commit) | Each commit's subject | Each commit's body | **No** | **No** |
| Merge commit | N + `Merge pull request #N …` | Each commit's subject | Each commit's body | No (merge commit is non-conventional, ignored) | No |

Check the repo setting rather than assuming:

```bash
gh api repos/{owner}/{repo} --jq '{squash: .allow_squash_merge, rebase: .allow_rebase_merge, merge: .allow_merge_commit, title: .squash_merge_commit_title, message: .squash_merge_commit_message}'
```

## Consequences per strategy

**Squash + PR_TITLE/PR_BODY** (this house default):

- The PR title is the *only* place the bump type lives. Intermediate commits
  (`wip`, `fix typo`, `address review`) are discarded and need not be conventional.
- A releasable change under a `chore`/`docs`/`refactor` title ships **no release**.
  Retitle before merge; after merge, use `Release-As:` or a commit override (below).
- The PR body becomes the commit body, so release-please **parses it**:
  - `BREAKING CHANGE: …` (or `BREAKING-CHANGE:`) as a footer → **major** bump.
  - A line in the footer block shaped like `feat(x): …` / `fix(x): …` is treated
    as an **additional conventional commit** (release-please's multi-change
    footer feature) → extra changelog entries, possibly an extra bump.
  - `Release-As: 1.2.3` → forces that version.
- Prose that merely *quotes* those forms ("this fixes the `BREAKING CHANGE:`
  parsing") belongs in backticks mid-sentence, never at the start of a line in
  the final paragraph.

**Rebase**:

- Every commit must be conventional and correctly typed; non-conventional
  commits are silently skipped, and a `fix` + `feat` pair yields a minor bump
  with two changelog entries.
- PR title and body are discarded — fixing a bad title after the fact has no
  effect. Clean the branch history (`git rebase -i` locally, or squash the
  noise commits) before merging.

**Merge commit**: as rebase, plus a `Merge pull request` commit release-please ignores.

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

## PR body as commit body

Under squash + PR_BODY the body is permanent `git log` content. Write it as a
commit body, not a review form:

| Keep | Drop or move to a comment |
|------|---------------------------|
| What changed and why, in plain paragraphs or a short list | `- [ ]` checklists (render as noise in `git log`) |
| `Fixes #N` / `Closes #N` / `Refs #N` footers | "How to test" steps for reviewers |
| `BREAKING CHANGE:` footer when intended | Screenshots, HTML comments, template boilerplate |
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
(`git interpret-trailers`) and release-please look for them. Markdown headings
(`## Summary`) are tolerated but read poorly in `git log`; prefer plain prose.
