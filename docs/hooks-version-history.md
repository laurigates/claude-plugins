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
| 2.1.72 | Permissions | A `PreToolUse` hook returning `"allow"` could bypass `deny` rules, including managed ones. `deny` rules now always take precedence. |
| 2.1.74, 2.1.268 | `SessionEnd` | `SessionEnd` hooks were hard-capped at 1.5 seconds regardless of `hook.timeout`. 2.1.74 let `CLAUDE_CODE_SESSIONEND_HOOKS_TIMEOUT_MS` raise it for hooks with an explicit per-hook `timeout`; hooks without one stayed capped until 2.1.268. |
| 2.1.214 | Exit codes | Exit code 2 was silently downgraded to a pass-through when the hook's stdout JSON failed schema validation. It now blocks. |
| 2.1.233 | `Notification` | `Notification` hooks were silently skipped for permission prompts under Claude Desktop and VS Code. They now fire. |
| 2.1.275 | Matchers | A `SubagentStop` hook with a specific `matcher` also fired for every stopping subagent whose agent type was empty. |
| 2.1.285 | Background processes | A synchronous hook that started a background process (`some-daemon &`) holding stdout open hung Claude Code. The hook now finishes shortly after its own process exits. |
| 2.1.290 | `updatedInput` | Some permission rules and safety checks were not re-applied after a hook rewrote the input with `updatedInput`. |
| 2.1.292 | Permissions | A hook `allow` (or auto mode) skipped the prompt for file reads from network (UNC) paths. |
| 2.1.295 | Output | Hooks in background sessions inherited `FORCE_COLOR=3`, which put color escape codes into the output Claude reads. |
| 2.1.295 | Async | An async hook's JSON output was ignored when printed over several lines, and an async `SessionStart` hook's unchanged context was re-added on every resume. On older clients, emit async JSON on one line (`jq -c`). |
| 2.1.304 | `PreToolUse` | A `PreToolUse` hook's deny reason was replaced by a timeout error when an Agent SDK callback hook on the same tool call timed out. |
| 2.1.304 | Headless runs | A plugin could keep a headless run going past `--max-turns`, Stop or ended input by spawning or re-running subagents. |
