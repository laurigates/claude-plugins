---
name: tool-result-traps
description: Tool results that mean something other than they look — a pattern that never compiled, a glob that cannot match a directory, one tier searched but reported absent, a rejected flag reading as "no results". Use when an empty result is about to gate an action, land in a doc, or be reported as done.
allowed-tools: Read, Glob, Grep, Bash(rg *), Bash(git grep *), Bash(git log *), Bash(git status *), Bash(git worktree *), Bash(gh api *), Bash(gh pr view *), Bash(python3 *), TodoWrite
model: opus
created: 2026-08-21
modified: 2026-10-07
compatibility: claude-code
reviewed: 2026-08-21
---

# Tool Result Traps

Promoted from the always-loaded `~/.claude/rules/tool-use-patterns.md` rule,
whose stub points here. The section bodies below are that rule's verbatim text.

One law across all of them: **an empty result, a green exit, and a well-formed
line of output are each claims about *mechanics*, not about *content*.** Every
trap here produces output that is indistinguishable from a correct answer —
no error, no warning, nothing on stderr — and the damage lands when that
output is used as a verdict: "no duplicate exists", "the rename is complete",
"nothing was lost", "the agent got its input". In one case the diagnostic *was*
written — and the caller's own `2>/dev/null` is what made it disappear.

The recurring fix is equally uniform: **control-test any negative that gates an
action.** Re-run the same command shape against something you *know* is
present. If the control also comes back empty, the tool is broken, not the tree
clean. One control run is cheap; a wrong negative is a confidently-reported
non-finding.

## When to Use This Skill

| Use this skill when... | Skip when... |
|---|---|
| A zero-match or empty result is about to be reported as "clean", "complete", or "none found" | The result is non-empty and you are acting on what it contains |
| Deduping before filing an issue, or concluding nobody reported something | Reading a single known file whose path you just listed |
| Declaring a bulk rename, migration, or sweep finished | Mid-sweep, still transforming matches |
| A verification loop's input set is built from a relative path | The path was resolved absolutely in the same command that used it |
| Batching parallel tool calls whose siblings may exit non-zero | A single call, or a batch of confirmed-present paths |
| A `Workflow` script's agents report thin or generic findings on rich material | Agents are returning specific, grounded detail |
| An `rg`/`git grep` result contradicts something you read directly | Output matches an independent read of the same file |
| Concluding a skill, command, recipe, or binary "does not exist" | You enumerated every tier it could be defined in |
| A `-g`/`--glob` filter is doing the narrowing, and the name you want is a directory | The glob is `**/<name>/**`, or the search is on content not names |
| The command that produced the empty result had its stderr redirected away | You read the command's stderr, or have seen it fail before |

## The traps

## Grep / rg — `-r` is `--replace`, not a bundled short flag

See [references/search-traps.md](references/search-traps.md) when an `rg` result contradicts a direct read of the file.

## `git grep -E` has no `\b` — the pattern matches nothing, silently

See [references/search-traps.md](references/search-traps.md) before trusting a zero-match `git grep -E` sweep verdict.

## A wrapped string defeats a source grep — the code is unchanged, the grep says fixed

See [references/search-traps.md](references/search-traps.md) before closing a task because a grep for a message came back empty.

## A pipe discards the command's exit code — `| tail` reports success for a failed run

See [references/search-traps.md](references/search-traps.md) before reporting a piped build, test, or CI watch as green.

## A `-g '*name*'` glob cannot match a **directory** name

See [references/search-traps.md](references/search-traps.md) when a `-g`/`--glob` filter is hunting a directory name.

## One search tier is not the search universe

See [references/search-traps.md](references/search-traps.md) before concluding a skill, command, recipe, or binary does not exist.

## A rejected flag looks exactly like "no results"

See [references/rejected-flags.md](references/rejected-flags.md) when an empty pipeline result is about to dedup an issue, or a silent mutating call is about to be reported as done.

## Your own `2>/dev/null` turns a loud rejection into a clean negative

The section above is about a tool that stayed quiet. This one is its mirror, and
the difference is the whole point: **the tool did its job.** It rejected the
command, printed a diagnostic, and exited non-zero — and the caller's own
redirect threw all three away. No tool-side improvement reaches this: the
message was written and then discarded downstream of the tool.

```
# Wrong — gh pr diff takes no pathspec, and the rejection goes to /dev/null
gh pr diff 36 -- .env.example 2>/dev/null | grep -E "^[+-]"
      ← empty stdout, reads as "this PR does not touch that file"

# The same command with the redirect dropped
gh pr diff 36 -- .env.example
accepts at most 1 arg(s), received 2      ← rc=1, and it said so all along
```

Observed 2026-08 reviewing a PR that claimed `Closes #29`: the empty result was
one step from being reported as "the change was never made". The file was
`+34/-5`. The exit code was lost as well — a pipeline reports the status of its
**last** command, so `grep`'s status is what survived, not `gh`'s.

**The control test does not catch this class.** Re-running the same shape
against a file the PR definitely touches comes back empty too — the shape is
broken for every input, so the control agrees with the false negative and
confirms it. What breaks it open is dropping the redirect, not changing the
input.

- **Suppress stderr only on a command whose failure mode you have already seen.**
  `2>/dev/null` is a claim that you know what would have been printed. On a
  first-time shape — a new flag, a new subcommand, a line copied from
  elsewhere — it mutes the one channel that would say the command never ran.
- **Re-run without the redirect before believing a negative that gates an
  action.** One run, and the diagnostic is either there or it is not. Prefer
  keeping stderr and reading it (`2>&1`) over muting it while you are still
  learning a command's shape.
- **Correct forms for the case above**: `gh pr diff <N>` and filter the unified
  diff yourself, or `gh pr view <N> --json files` for per-file additions and
  deletions.

For the worktree-shell wedge, the vacuous path-scoped verification, the
`Workflow` `args` JSON-string trap, the control that must exercise the failing
part of the pattern (the `parseFloat` case), and the parallel-batch / agent
fan-out hazards, see [REFERENCE.md](REFERENCE.md).
