---
name: git-upstream-fix-check
description: "Check upstream HEAD before patching vendored, tarball-installed, or forked code. Use when patching a dependency, custom node, or fork you don't own."
allowed-tools: Bash(gh api *), Bash(gh issue *), Bash(gh pr *), Bash(gh repo *), Bash(base64 *), Read, Grep, Glob
created: 2026-08-19
modified: 2026-08-19
reviewed: 2026-08-19
---

# /git:upstream-fix-check

Fires when you are about to edit third-party code inside the project — a path
under `vendor/`, `site-packages/`, `node_modules/`, `custom_nodes/`,
`third_party/`, or a fork checkout. Every command below is GitHub-specific
(`gh`); vendored code from GitLab/Codeberg/sourcehut has no recipe here. See
`git-plugin:gh-cli-agentic` for the raw `gh api contents` command form,
`git-plugin:git-fork-workflow` once you have confirmed upstream carries the fix,
`git-plugin:git-upstream-pr` for the contribute-back handoff, and
`workflow-orchestration-plugin:workflow-verify-before-filing` for the different
case of a *backlog* of N accumulated bug candidates you are about to file.

Before patching third-party code that lives inside the project (a
custom ComfyUI node, a vendored library, a tarball-installed package,
a fork checkout), check whether the bug is already fixed upstream.
A 30-second `gh` lookup often replaces a 30-minute patch and a PR
the maintainer will close as duplicate.

## Quick checks

```sh
# Read one file at upstream HEAD without cloning
gh api repos/<owner>/<repo>/contents/<path> --jq '.content' | base64 -d

# See what changed since the local copy's version
gh api repos/<owner>/<repo>/contents/<path>?ref=<sha-or-tag> ...

# Default branch + last activity (catches dead repos)
gh api repos/<owner>/<repo> --jq '{default_branch, pushed_at, updated_at}'

# Issues / PRs about the same symptom
gh issue list -R <owner>/<repo> --state all --limit 30 --search "<keyword>"
gh issue view <n> -R <owner>/<repo> --json title,body,state,closedAt,comments
gh pr list   -R <owner>/<repo> --state all --limit 20
```

If the most recent push is months old and the issue tracker shows
similar bug reports closed-without-merge, the project is effectively
stale — patch locally and move on. If there's recent activity AND
the file at master no longer matches the local copy, prefer upgrading
the install over patching the snapshot.

## When this matters most

- **Tarball-installed packs without `.git`.** Common with package
  managers that snapshot rather than clone (ComfyUI-Manager,
  pip wheel installs, vendored deps, `npm pack`-style installs).
  Local version is pinned at install time and may be many releases
  behind, so the obvious bug may be obviously fixed upstream.
- **Forks with diverged history.** The bug may already be fixed on
  upstream `main` but never pulled into the fork. Check upstream
  before deciding whether to patch the fork or rebase it.
- **Linter / formatter / generator output checked into the repo.**
  Patching the output is usually wrong — find the generator's bug
  upstream instead.

## When to skip the check

- The bug is in a file the project clearly owns and authored (not
  a vendor / generated / installed path).
- You already know upstream's state from a recent session.
- The local install has explicit downstream patches you'd lose by
  upgrading. (In that case still skim upstream issues for context,
  but don't auto-upgrade.)

## Rationale

Patching a stale snapshot creates two debts: the patch itself, and a
hidden upgrade footgun (your patch silently reverts the next time
something re-fetches the snapshot). Verifying upstream first either
(a) confirms the patch is necessary AND surfaces it for an upstream
PR, or (b) reveals an upgrade is the actual fix.
