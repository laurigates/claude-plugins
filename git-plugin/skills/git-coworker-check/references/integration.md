# Integration

Moved verbatim from `SKILL.md`. Read when wiring this check into another skill or hook.

## Integration

Other git-plugin skills should invoke this via SlashCommand before destructive operations or fan-out:

```markdown
Before staging (or before starting a per-plugin commit loop):
Use SlashCommand to invoke `/git:coworker-check`.
If the verdict is not `clear`, stop and ask the user how to proceed.
```

Bulk-edit / commit-loop skills (`git-commit-workflow`, per-plugin release-please loops, mass refactors) must invoke this **before staging any files** — see [SKILL.md § Bulk-edit / commit-loop precondition](../SKILL.md#bulk-edit--commit-loop-precondition) for why an opportunistic mid-loop check is insufficient.

Hook-based enforcement (blocking `git stash` / `git reset --hard` when a coworker is detected) belongs in `hooks-plugin`, not here.

## Related Skills

- `/git:maintain` — invokes this before any stash/clean operation
- `/git:commit` — invokes this before staging when working in a shared checkout
- `git-commit-workflow` — invokes this as a precondition for bulk-edit / per-plugin commit loops
- `git-branch-pr-workflow` — recommends worktrees as the structural fix
- `/taskwarrior:task-claim` — sister signal; writes the `+ACTIVE` claim that this skill now reads
- `/taskwarrior:task-release` — drops the claim that contributes to `TW_CLAIM_COUNT`
