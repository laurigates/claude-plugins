# Git Fork Workflow — Reference

Detail moved out of [SKILL.md](SKILL.md): remote-identification one-liners, the `BEHIND`/`AHEAD` count table, keeping a fork-internal PR from backlinking upstream, cross-fork PR syntax, and secondary sync recipes.

## Identifying Fork vs Upstream

```bash
# Check if upstream remote exists
git remote get-url upstream

# Get fork owner
git remote get-url origin | sed -E 's#.*github\.com[:/]##; s#\.git$##'

# Get upstream owner
git remote get-url upstream | sed -E 's#.*github\.com[:/]##; s#\.git$##'
```

## Reading the Counts

The script's `BEHIND` / `AHEAD` come from
`git rev-list --left-right --count upstream/main...origin/main`:

| `BEHIND` `AHEAD` | Meaning |
|--------|---------|
| `0  0` | Perfectly in sync |
| `5  0` | Fork is 5 behind upstream (upstream has 5 new commits) |
| `0  3` | Fork is 3 ahead (fork has 3 commits not on upstream) |
| `5  3` | Diverged: upstream has 5 new, fork has 3 unique |

## Keep the staging PR's text from reaching upstream

A fork-internal PR or issue body is not private to the fork. GitHub autolinks
`owner/repo#N`, `owner/repo@sha` and full issue/PR URLs in conversations, and
"by default, references generate a backlink" on the referenced issue
([Autolinked references and URLs](https://docs.github.com/en/get-started/writing-on-github/working-with-advanced-formatting/autolinked-references-and-urls)).
The backlink is a `cross-referenced` timeline event ("The issue or pull request
was referenced from another issue or pull request",
[Issue event types](https://docs.github.com/en/rest/using-the-rest-api/issue-event-types#cross-referenced)),
so upstream maintainers see your review PR before you have submitted anything.

- **Wrap upstream and third-party references in backticks.** A code span is not
  autolinked. Rendered via `gh api markdown -f mode=gfm -f context=<fork>`,
  bare `owner/repo#1` became a link to upstream; `` `owner/repo#1` `` stayed a
  `<code>` element. That shows the link is suppressed; whether every
  backlink path (title, edits after posting) is also suppressed is unverified.
- **For a clickable link without a backlink**, the docs give `redirect.github.com`
  in place of `github.com` in the URL.
- **A bare `#N` resolves in the repo it is written in.** In a fork PR body, or
  in a commit message pushed to the fork, `#1` links the fork's `#1`, not
  upstream's.

Check the body file before publishing, then control-test the pattern against a
line holding one bare and one backticked reference — only the bare one may match:

```bash
rg -nP '(?<![`\w.-])[\w.-]+/[\w.-]+(#[0-9]+|@[0-9a-f]{7,40})\b' body.md
rg -n 'https://github\.com/[^/ ]+/[^/ ]+/(issues|pull)/[0-9]+' body.md
```

The lookbehind only sees the character directly before the reference (it also
rejects a match that starts inside a hyphenated or dotted owner name such as
`my-org`), so a reference in the middle of a longer code span or a fenced block
also matches; review those by hand. The bare `user@sha` form is not covered.

> Observed 2026-10 (`laurigates/dust#1`, a review PR in the fork before anything
> went to `bootandy/dust`): references to the upstream issue and to third-party
> repos' issues/PRs were backticked so they would not autolink from the fork.

## Cross-Fork PR Syntax

```bash
# Create PR from fork branch to upstream repo
gh pr create \
  --repo owner/upstream-repo \
  --base main \
  --head your-username:feat/branch-name \
  --title "feat: description" \
  --body "PR description"
```

The `--head` must include the fork owner prefix (`your-username:branch`) when targeting a different repository.

## Common Patterns

### Check if Working in a Fork

```bash
# Has upstream remote = likely a fork
git remote get-url upstream 2>/dev/null && echo "Fork" || echo "Not a fork"
```

### Periodic Sync Workflow

```bash
# Weekly sync routine
git fetch upstream
git switch main
git merge --ff-only upstream/main || echo "Diverged - manual sync needed"
git push origin main
```

### View Upstream Changes Since Last Sync

```bash
git fetch upstream
git log --oneline origin/main..upstream/main
```
