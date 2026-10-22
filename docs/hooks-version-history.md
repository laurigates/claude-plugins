# Hook Behaviour Fixes: Version History

Dated record of hook bugs Claude Code has since fixed. [`.claude/rules/hooks-reference.md`](../.claude/rules/hooks-reference.md) describes current behaviour; this file holds what used to be broken, moved out so the path-scoped rule stays under the 50,000-char ceiling (`scripts/check-context-engineering.py --strict`). Read it only when debugging a hook on a Claude Code older than the version tagged below.

| Version | Area | What was broken, and the fix |
|---------|------|------------------------------|
| 2.1.141 | Worktree | Hooks fired after an `EnterWorktree` switch received a `transcript_path` pointing at the pre-switch working directory, breaking transcript-reading helpers. The path now reflects the new worktree. |
| 2.1.147 | `if` matching | Hook `if` conditions that scoped a command shape with arguments, e.g. `PowerShell(git push*)`, never matched; only the bare `PowerShell(*)` form worked. Argument-scoped conditions now match as written. |
| 2.1.163 | `if` matching | `if: "Bash(...)"` fired on **every** Bash command containing `$()` or `$VAR`. The condition now also matches commands inside subshells and backticks, so `if: "Bash(git push*)"` fires for `$(git push ...)` and `` `git push ...` `` without matching unrelated commands that merely contain a `$`. |
| 2.1.176 | `if` matching | Path-scoped conditions for Read/Edit/Write (`Edit(src/**)`, `Read(~/.ssh/**)`, `Read(.env)`) silently failed to fire. They now match. |
| 2.1.191 | Matchers | Comma-separated matchers (`"Bash,PowerShell"`) silently never fired. They now match either tool. |
| 2.1.199 | `SessionStart` | `SessionStart`, `Setup` and `SubagentStart` hooks hid stderr on exit code 2; the error text now shows in the transcript like other command hooks. |
| 2.1.239 | Remote sessions | Remote/web sessions now send keep-alives while a long `SessionStart`/`Setup` hook runs, so the container is no longer idle-reaped mid-hook (relevant to the 300-600s `SessionStart` timeout recommendation). |
| 2.1.239 | Working directory | If the session's working directory is deleted mid-session, hooks no longer fail with `posix_spawn ENOENT`; they run from the project root or the user's home directory. |
