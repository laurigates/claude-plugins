# Wave-Based Dispatch — Gating on a Green PR vs a Landed Merge

Moved verbatim from [SKILL.md](../SKILL.md). Open when a human reviews and merges
each wave, so wave N cannot land before wave N+1 is due.

### Gating on a green PR vs a landed merge

The six gates assume wave N **landed on `main`** (Gate 6: clean tree). That
holds when the orchestrator merges each wave itself. But when **a human reviews
and merges** — so waves can't land before wave N+1 is due — don't stall the
pipeline waiting for the merge. Gate wave N+1 on wave N's foundation **PR being
green** (CI passing on the open PR) and **stack wave N+1 on wave N's branch**
(`gh pr create --base <wave-N-branch>`), so it builds on wave N's content
without waiting on the merge. Two adjustments:

- **Gate 6 becomes "wave N's PR is green," not "merged."** Gates 1–5 (build,
  tests, smoke, task/tracker drain) still apply — run them on wave N's branch.
- **CI scoped to `pull_request: [main]` does not run on the stacked children**
  (their base is a feature branch), so their gate is a **local** build/test
  until they're retargeted to `main`.
- **Honor stacked-PR merge order at landing time:** retarget children to `main`
  *before* the base PR merges and deletes its branch, then rebase
  `--onto origin/main <old-base-tip>` to drop the squashed base commits. See
  `git-plugin:git-pr` (Stacked PRs) and `git-plugin:git-conflicts` (rerere can
  replay the resolution across the base merge and each child rebase).
