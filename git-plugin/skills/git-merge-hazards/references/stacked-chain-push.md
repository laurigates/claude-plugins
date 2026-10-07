# Stacked-Chain Merges: Push by SHA, Mergeability and CI Races

Moved verbatim from `SKILL.md` §3. Read before any force-push or merge while working down a stacked-PR chain.

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
  refspec the bullet above just told you to use:

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
  reason about. It compounds with the brace rule immediately above rather than
  replacing it: `"$sha:refs/heads/x"` is the `:r` word-modifier row in that
  table — unbraced, zsh silently sends `<sha>efs/heads/x`.
- **An empty-diff force-push auto-closes the PR — and a closed PR whose *head*
  moved after closing cannot be reopened.** Sibling of #2's
  base-branch-deleted variant. GitHub saw the branch == main, closed the PR,
  and refused `gh pr reopen` because the head ref had moved since closing.
- **A single mergeability read after a force-push is a race.** GitHub
  recomputes `mergeable` asynchronously; `gh pr merge` right after a push
  fails with "not mergeable" on a perfectly clean PR. Poll
  `gh pr view <n> --json mergeable` until it leaves `UNKNOWN`.
- **Waiting for CI races check *registration*, not just completion.** A loop on
  "zero pending checks" can exit **immediately** after a push/`update-branch`:
  zero pending is trivially true before the jobs are registered. Observed
  2026-07: `state=CLEAN` on a **single** check while three CI jobs had not yet
  appeared — merging there merges untested. Gate on **both** nothing-pending
  **and** `--jq 'length'` ≥ the expected check count. Same root cause as the
  mergeability race above: an async field read once, too early.

- **Check** before every force-push: `git log --oneline origin/main..<sha>` —
  expect *exactly* the child's commits, nothing more, never empty.
- **Recovery** when auto-closed: the rebased commits survive in local objects
  (`git reflog`) — `git push --force-with-lease origin "${sha}:refs/heads/<branch>"`,
  open a fresh PR from the branch, comment "Superseded by #new" on the closed
  one. The full refname matters most here: the branch may not exist on the
  remote yet, and the short form cannot create it.
