# Fix Phase — Applying `/configure:all --fix` Across One Repo

Order and mechanics for turning a compliance report into merged PRs. Taken from
a run on a Node bridge-server repo (FoundryVTT local REST API: 4 follow-up PRs
after the first), where the first pass of the fix phase produced a conflicting
PR stack and three agents that started from the wrong base.

## 1. Branch and commit

- Cut from the remote, never from the checked-out branch:
  `git fetch origin && git switch -c <branch> origin/main`.
- One commit per theme, and one PR per concern. Themes that worked:
  tooling baseline (pre-commit, justfile, mise, editorconfig, gitattributes,
  worktreeinclude, Renovate, SECURITY.md, `.project-standards.yaml`), then the
  Claude plugin setup (`/configure:claude-plugins`), then docs (`/configure:readme`).
- A formatter goes in its own PR as two commits: config and wiring first, the
  mechanical reformat second. It rewrote 60 files and conflicted with every
  other open PR.
- Stage with one `git add -- <explicit paths>` call, then commit in a separate
  call. Never `git add -A`; the git-plugin hook blocks chaining two
  index-modifying git commands with `&&`.
- Pre-commit hooks rewrite whitespace in every file a commit touches. A one-line
  edit to an old workflow file becomes a whole-file diff and conflicts with any
  other PR that touches it. Expect this, and sequence such PRs.

## 2. Config values come from tools, not templates

| Value | Source |
|-------|--------|
| Hook `rev:` pins | write the config, then `pre-commit autoupdate`; `pre-commit validate-config` |
| Action pins | `gh api repos/<o>/<r>/git/ref/tags/<tag>`; dereference an annotated tag (`.object.type == "tag"`) with `gh api repos/<o>/<r>/git/tags/<sha> --jq .object.sha` |
| Env var names, ports, defaults in docs | read the source (`rg 'process\.env' <dir>`); a README example used the wrong variable until it was checked |
| Standards version | `STANDARDS_VERSION=` from `scripts/list-components.sh`; do not invent one |
| Tool versions | the registry (`npm view <pkg> version`), then pin exactly in `package.json` |

## 3. Verify before claiming

Run `pre-commit run --files <changed>`, the project's linter and its test suites,
and quote each count with the command that produced it. Say what did not run
(CI workflows that need the merge to trigger, recipes only syntax-checked).
Test commands that override a config's ignore list need all the ignores, see
[gotchas.md](gotchas.md).

## 4. Open the PR

Assignee and a label that exists (`gh label list --limit 500`; never create
one). Body: what changed per commit, verification with commands, what was not
done, follow-up issue links. Pick the merge method with
`python3 <git-plugin>/scripts/pr-merge-method.py --pr <n>`: several independent
conventional commits rebase, a single commit squashes.

## 5. File deferred findings as issues

Search for duplicates first. Findings from this kind of run that became issues:
no formatter yet, a `package.json` script pointing at a missing file, ten
broken anchors in an old PRD, advisories reported by `npm audit`, an unpublished
container image, a Knip baseline to clear.

## 6. Parallel agents

- A worktree agent is cut from `origin/main`, not from the branch you are on
  (`worktree.baseRef` is `fresh`). All three agents in the run started without
  the first PR's files, and one reported that `claude.yml` "does not exist".
  That report is the symptom of a wrong base, not a finding.
- Brief each agent with the base branch. Have it run
  `git fetch origin && git rebase origin/<base>` before its first push, and check
  that `git log origin/<base>..HEAD` lists only its own commits.
- Give each agent disjoint files (Dockerfile and `engines` / `test.yml` and
  coverage thresholds / lint, Knip and MCP config), and say which files belong
  to a sibling. Run the formatter PR last.
- Re-read every agent report against the PR before relying on it: `gh pr view
  <n> --json baseRefName,files,commits`.

## 7. Merge a stacked chain

The skill `git-plugin:git-merge-hazards` carries the full procedure. The order
that worked:

1. Retarget every child to `main` while the base PR is still open:
   `gh pr edit <child> --base main`. A closed PR whose base branch was deleted
   cannot be reopened.
2. Merge the base with `--match-head-commit <40-char SHA>`. Paste the SHA from a
   separate `git rev-parse` call; the guard refuses `$(...)`.
3. A rebase-merged base leaves each child carrying the old copies of the base's
   commits, so each child shows `DIRTY` / `CONFLICTING`. Rebase the child onto
   `origin/main`: git skips the already-applied commits ("skipped previously
   applied commit"). Push with
   `--force-with-lease=<branch>:<old-sha> origin <new-sha>:refs/heads/<branch>`
   using literal SHAs, and only with the owner's approval.
4. Checks register a few seconds after a push; `gh pr checks` first prints
   "no checks reported". Wait for them, then merge.
5. A PR that touches a file another merged PR rewrote (a formatter over files
   changed meanwhile) conflicts on every file: take the base's side
   (`git checkout --ours -- <paths>` during a rebase), re-run the formatter, and
   re-add the PR's own edits.
