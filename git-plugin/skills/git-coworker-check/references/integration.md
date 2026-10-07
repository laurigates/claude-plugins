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
