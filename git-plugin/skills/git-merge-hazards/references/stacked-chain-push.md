# Stacked-Chain Merges: Push by SHA, Mergeability and CI Races

Moved from `SKILL.md` §3; its CI-registration bullet (which points at `scripts/merge-chain.sh`) diverges from the chezmoi copy, as [sync-notes.md](sync-notes.md) records. Read before any force-push or merge while working down a stacked-PR chain.

## 3. Stacked-chain merges: push by SHA, never `HEAD:` — and expect auto-close races

Working down a stacked-PR chain (retarget child → merge base → rebase child →
force-push → merge, per #2) has several traps of its own (observed 2026-07,
claude-plugins #1979→#1987):

- **`HEAD:` in a push refspec is a race in a shared checkout.** HEAD is
  process-global repo state; a coworker session can move it *between two of
  your Bash calls*. Observed: rebase left HEAD at the child's new tip; by the
  next call HEAD was `main`'s tip, so `git push --force-with-lease origin
  HEAD:<child-branch>` overwrote the branch with main. Resolve the tip to an
  **explicit SHA in the same command that creates it** and push
  `git push --force-with-lease origin <sha>:refs/heads/<branch>`.
- **Brace that variable — `"$sha:<branch>"` is a zsh word-modifier expansion.**
  Stock zsh (reproduces under `zsh -f`) eats the character after the colon as a
  history modifier whenever it happens to be one, silently rewriting the
  refspec the **`HEAD:` … is a race** bullet just told you to use:

  | Written | zsh actually sends | |
  |---|---|---|
  | `"$sha:refs/heads/x"` | `<sha>efs/heads/x` | `:r` |
  | `"$sha:feat/x"` | `at/x` | `:f`+`:e` |
  | `"$sha:chore/x"` | `<sha>hore/x` | `:c` |
  | `"$sha:test/x"` / `release/` / `ci/` / `hotfix/` / `refactor/` | mangled | `:t :r :c :h :r` |
  | `"$sha:style/x"` | **hard error** `bad substitution` | `:s` |
  | `"$sha:fix/x"` / `docs/` / `perf/` / `build/` / `main` | correct | not modifiers |

  Half the conventional-commit prefixes break and half don't, which is why it
  reads as a baffling one-off instead of a rule. Always
  `git push --force-with-lease origin "${sha}:refs/heads/<branch>"`. Observed
  2026-08 pushing `feat/justfile-pr-triage`: `src refspec <sha>efs/heads/… does
  not match any` — the error names a ref you never typed, so it looks like a
  stale SHA rather than a quoting bug.
- **Spell the destination `refs/heads/<branch>`, always.** A `<sha>:<branch>`
  refspec works only when `<branch>` **already exists on the remote**: git has a
  bare commit object on the left, so there is no ref namespace to infer the
  destination from, and it refuses rather than guessing — `error: The
  destination you provided is not a full refname (i.e., starting with
  "refs/")`. git wraps that message right after `(i.e.,`, so triage by grepping
  the `not a full refname` fragment, not the whole sentence. The full refname
  is accepted whether or not the branch exists, so there is no branch state to
  reason about. It compounds with the **Brace that variable** rule rather than
  replacing it: `"$sha:refs/heads/x"` is the `:r` word-modifier row in that
  table — unbraced, zsh silently sends `<sha>efs/heads/x`.
- **Pin a lease to a full 40-hex SHA, never a short one.**
  `--force-with-lease=<ref>:<short>` fails with `cannot parse expected object
  name` when the abbreviation is not in the local object store or is ambiguous,
  so the push is refused before it reaches the remote. A full 40-hex SHA always
  parses, because git reads it as an object name without looking it up. Resolve
  it first: `lease=$(git rev-parse origin/<branch>)`, then
  `git push --force-with-lease="refs/heads/<branch>:${lease}" origin "${sha}:refs/heads/<branch>"`.
- **An empty-diff force-push auto-closes the PR — and a closed PR whose *head*
  moved after closing cannot be reopened.** Sibling of #2's
  base-branch-deleted variant. GitHub saw the branch == main, closed the PR,
  and refused `gh pr reopen` because the head ref had moved since closing.
- **A single mergeability read after a force-push is a race.** GitHub
  recomputes `mergeable` asynchronously; `gh pr merge` right after a push
  fails with "not mergeable" on a perfectly clean PR. Poll
  `gh pr view <n> --json mergeable` until it leaves `UNKNOWN`.
- **Waiting for CI races check *registration*, not just completion. Wait and
  merge with `scripts/merge-chain.sh`, never a hand-written poll.** A loop on
  "zero pending checks" can exit **immediately** after a push/`update-branch`:
  zero pending is trivially true before the jobs are registered. Observed
  2026-07: `state=CLEAN` on a **single** check while three CI jobs had not yet
  appeared — merging there merges untested. A count of checks does not close the
  race either. An expected count breaks on path-filtered workflows, whose check
  set changes with the diff (`.claude/rules/gh-json-fields.md`), and a count gate
  passed while a second `lint` run for the same head was still registering
  (ForumViriumHelsinki/.github-private #13, #15, #19).

  Take `--review-ts` from the **Check** bullet of this section, which records it once the
  check passes and before the force-push. A rebase gives every commit a new
  committer date, so a time taken before the rebase makes the script refuse the
  child's own commits. A time taken after the push stops guarding the gap: a
  commit anyone pushes between the Check and the push is older than that time,
  so the script would merge it unreviewed. Shell variables do not survive
  between Bash calls, so paste the value the Check printed. After the push, run
  the script on the child alone:

  ```bash
  REVIEW_TS=<the REVIEW_TS= value the Check printed>
  bash "${CLAUDE_SKILL_DIR}/scripts/merge-chain.sh" --repo OWNER/REPO --prs <child> --review-ts "$REVIEW_TS"
  ```

  It runs `gh pr update-branch` (a no-op on a child just rebased onto `main`),
  waits until every check on the head has completed and two consecutive reads
  agree, keeps only the latest run of each check, refuses any commit newer than
  `--review-ts` and a head that moved after CI settled, and merges with
  `--match-head-commit` and the full 40-character SHA. Its `HEAD_SHA=` line must
  equal the SHA you pushed. The script takes no expected SHA: a read that still
  returns the pre-push tip settles on that tip, and the guard's fresh read then
  stops it with `GUARD_LATE_COMMIT` (`head_moved`), so a stale read fails closed.
  Flags, statuses and what to do on each: [merge-shepherd.md](merge-shepherd.md).

  The call can run longer than a foreground Bash call allows (2 minutes by
  default, 10 at most), and longer than its own `--timeout`. `--timeout`
  (default 1800 seconds) bounds one CI wait. When the base moves while CI runs,
  the script updates the branch and waits again, up to `MC_MAX_UPDATES` (3)
  waits per PR, and each wait can overrun its budget by one poll interval
  (`MERGE_CHAIN_POLL_SECONDS`, default 20). After the merge it reads the state
  back up to 5 times, one poll apart. For one PR at the defaults that is
  3 x (1800 + 20) + 5 x 20 = 5560 seconds. Run the block with
  `run_in_background: true` and an explicit `timeout` of `6000000` (100 minutes).
  The default background limit is 30 minutes, no more than a single wait's own
  budget, so without the larger `timeout` the harness can kill the script
  mid-wait, and it then prints no `STATUS=` at all. Scale the `timeout` with the
  PR count and with any `--timeout` you pass. Read the child's `STATUS=` when the
  task finishes: anything other than `MERGED` means it did not merge.

  This bullet used to carry its own `jq` poll over `statusCheckRollup`. It read
  every rollup entry alike, so a run cancelled by workflow concurrency, sitting
  beside the run that superseded it, blocked the merge as a failure: the false
  `CI_RED` that #3380 fixed in `merge-chain.sh`.

  **Not covered: waiting on a PR you are not merging now.** The script always
  merges a PR whose CI settles green, and it skips a PR that is a draft or whose
  author is neither you nor a bot. To only wait, for a child pushed before its
  base merges or a PR someone else wrote, use
  `gh pr checks <n> --watch --fail-fast` (or `gh run watch`, per
  `git-plugin:gh-workflow-monitoring`). It reports only the checks registered so
  far and does not pin the head SHA, so its exit 0 is not a merge gate: merge
  through `merge-chain.sh`.

- **Check** before every force-push: `git log --oneline origin/main..<sha>` —
  expect *exactly* the child's commits, nothing more, never empty. When it
  passes, record the review time before the push, for the CI-registration
  bullet's `--review-ts`:

  ```bash
  git log --oneline origin/main..<sha>
  REVIEW_TS=$(date -u +%Y-%m-%dT%H:%M:%SZ); echo "REVIEW_TS=$REVIEW_TS"
  ```

- **Recovery** when auto-closed: the rebased commits survive in local objects
  (`git reflog`) — `git push --force-with-lease origin "${sha}:refs/heads/<branch>"`,
  open a fresh PR from the branch, comment "Superseded by #new" on the closed
  one. The full refname matters most here: the branch may not exist on the
  remote yet, and the short form cannot create it.
