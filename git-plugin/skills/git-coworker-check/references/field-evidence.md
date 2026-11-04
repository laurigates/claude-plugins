# Field Evidence

Moved verbatim from `SKILL.md`. Worked examples behind the bulk-edit precondition and the verdict-to-action table.

### Why the check is front-loaded

**Why front-loaded, not opportunistic.** A real divergence scenario from the field: two Claude sessions converged on the same trim-descriptions task. Session A used `general-purpose` subagents in the main checkout; session B used worktrees + per-plugin commits. Session B landed 11 clean per-plugin commits and stopped. Session A's first commit then grabbed **all 30 remaining plugins** in a single mega-commit, because session A had previously hit a `git commit -a` failure that left everything pre-staged, and session B's loop never noticed because it ran `/git:coworker-check` *during* its work rather than *before*. The end result was correct, but the commit history said `docs(configure-plugin): ...` for changes spanning 30 plugins.

### Worked example: detection enables defensive restoration (#1277)

A second positive scenario from the field — the "stop and inspect" rather than "stop and abort" branch. A description-trimming refactor agent ran in a checkout that already had ~7 active `claude` processes touching the same files. The `coworker_detected` verdict fired off the **process-scan signal** alone (the `ps`-based fallback, well before any taskwarrior coordination existed for this batch). Per the verdict-to-action table in [SKILL.md § Bulk-edit / commit-loop precondition](../SKILL.md#bulk-edit--commit-loop-precondition), the agent did not stash or reset; it scoped its pass to the remaining 17 files and inspected the coworker's already-landed edits before writing.

That inspection caught a real regression: in `git-fork-workflow`, the coworker had cut the description from 358 → 240 chars and dropped the sibling cross-reference `For creating upstream PRs, see git-upstream-pr`. The agent re-added the line on its own pass. Eight other skills had a stale `modified:` date for the same reason and were stamped forward. No work was lost; a silent cross-reference regression became an explicit recovery. `Evidence: issue #1277.`
