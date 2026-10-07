# Field Evidence

Moved verbatim from `SKILL.md`. Worked examples behind the bulk-edit precondition and the verdict-to-action table.

### Worked example: detection enables defensive restoration (#1277)

A second positive scenario from the field — the "stop and inspect" rather than "stop and abort" branch. A description-trimming refactor agent ran in a checkout that already had ~7 active `claude` processes touching the same files. The `coworker_detected` verdict fired off the **process-scan signal** alone (the `ps`-based fallback, well before any taskwarrior coordination existed for this batch). Per the verdict-to-action table above, the agent did not stash or reset; it scoped its pass to the remaining 17 files and inspected the coworker's already-landed edits before writing.

That inspection caught a real regression: in `git-fork-workflow`, the coworker had cut the description from 358 → 240 chars and dropped the sibling cross-reference `For creating upstream PRs, see git-upstream-pr`. The agent re-added the line on its own pass. Eight other skills had a stale `modified:` date for the same reason and were stamped forward. No work was lost; a silent cross-reference regression became an explicit recovery. `Evidence: issue #1277.`
