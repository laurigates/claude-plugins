# Stacked-Chain Merges: Push by SHA, Mergeability and CI Races

Moved from `SKILL.md` §3; its CI-registration bullet (the rollup gate) diverges from the chezmoi copy, as [sync-notes.md](sync-notes.md) records. Read before any force-push or merge while working down a stacked-PR chain.

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
- **Waiting for CI races check *registration*, not just completion.** A loop on
  "zero pending checks" can exit **immediately** after a push/`update-branch`:
  zero pending is trivially true before the jobs are registered. Observed
  2026-07: `state=CLEAN` on a **single** check while three CI jobs had not yet
  appeared — merging there merges untested. A count of checks does not close the
  race either. An expected count breaks on path-filtered workflows, whose check
  set changes with the diff (`.claude/rules/gh-json-fields.md`), and a count gate
  passed while a second `lint` run for the same head was still registering
  (ForumViriumHelsinki/.github-private #13, #15, #19). Gate on the rollup, and merge only when all five
  hold:
  1. `headRefOid` equals the full SHA you pushed. A read right after a push can
     return the old tip, and ForumViriumHelsinki/.github-private #17 merged on a pre-push run.
  2. `statusCheckRollup` is non-empty.
  3. No entry has a `status` other than `COMPLETED`.
  4. Every `conclusion` is `SUCCESS`, `SKIPPED` or `NEUTRAL`. Skipped and neutral
     are not failures (`gh-json-fields.md`), and a SUCCESS-only gate would
     deadlock on jobs a path filter skipped on purpose. Any other value blocks,
     including `null` while a job still runs.
  5. Checks 2 to 4 hold on two reads about 30 seconds apart, with the same number
     of entries. One completion read cannot close the window before a second run
     registers. The second read can. The gate loop in the bash block of this rule
     takes both reads. It stops at the first read that shows the PR is no longer
     `OPEN`: a PR that merged while you waited keeps reporting its rollup, so a
     poll without that escape never exits. It also stops at a 30-minute deadline.

  Set `n` to the child's PR number and `sha` to the pushed SHA, then run the loop:

  ```bash
  deadline=$((SECONDS + 1800))
  prev=""
  ok=0
  while [ "$SECONDS" -lt "$deadline" ]; do
    snap=$(gh pr view "$n" --json state,headRefOid,statusCheckRollup 2>/dev/null) || snap=""
    case "$(jq -r '.state // ""' <<<"$snap")" in
      OPEN) ;;
      MERGED|CLOSED) break ;;
      *) prev=""; sleep 30; continue ;;
    esac
    if jq -e --arg sha "$sha" '
        (.headRefOid == $sha)
        and (.statusCheckRollup | length > 0)
        and all(.statusCheckRollup[]; (.status // "COMPLETED") == "COMPLETED")
        and all(.statusCheckRollup[];
          (.conclusion // .state) as $c | ($c == "SUCCESS" or $c == "SKIPPED" or $c == "NEUTRAL"))' \
        <<<"$snap" >/dev/null; then
      count=$(jq '.statusCheckRollup | length' <<<"$snap")
      if [ -n "$prev" ] && [ "$count" = "$prev" ]; then ok=1; break; fi
      prev=$count
    else
      prev=""
    fi
    sleep 30
  done
  [ "$ok" -eq 1 ]
  ```

  The loop can run for 30 minutes, longer than a foreground Bash call allows (2
  minutes by default, 10 at most). Run the block with `run_in_background: true` and
  an explicit `timeout` of `2100000` (35 minutes). The default background limit is
  also 30 minutes, equal to the gate's own deadline, so without a larger `timeout`
  a gate that never settles ends as a killed task after its last `sleep`, not by the
  block's own `[ "$ok" -eq 1 ]` exit. Read the exit status when the task finishes:
  0 means the gate passed, and any other status means do not merge.

  A failed `gh` read never passes: its state is empty, so the loop takes no pass
  from it and polls again. `SECONDS` is the loop's clock: the block reads it once
  at its first line, so the 30 minutes run from there. A legacy commit status
  (`StatusContext`) has no `status`, so the gate reads it as complete, and its
  `state` stands in for the conclusion: `SUCCESS` passes, while `PENDING`,
  `FAILURE` and `ERROR` block. Same root cause as the **single mergeability read**
  race: an async field read once, too early.

- **Check** before every force-push: `git log --oneline origin/main..<sha>` —
  expect *exactly* the child's commits, nothing more, never empty.
- **Recovery** when auto-closed: the rebased commits survive in local objects
  (`git reflog`) — `git push --force-with-lease origin "${sha}:refs/heads/<branch>"`,
  open a fresh PR from the branch, comment "Superseded by #new" on the closed
  one. The full refname matters most here: the branch may not exist on the
  remote yet, and the short form cannot create it.
