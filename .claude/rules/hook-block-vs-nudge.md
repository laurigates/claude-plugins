---
created: 2026-06-29
modified: 2026-10-13
reviewed: 2026-07-04
paths:
  - "**/hooks/**"
  - "**/*hook*.sh"
  - "**/bash-antipatterns*.sh"
---

# Hook Enforcement: Block for Safety, Nudge for Style

A PreToolUse hook can **hard-block** (exit 2) or emit a **non-blocking nudge**
(a PostToolUse teach-mode hint, or an advisory message). That choice is not
cosmetic: picking *block* for a non-safety concern imposes a recurring tax and,
worse, can dead-end the agent.

## The rule

Hard-block (exit 2) **only** when the command risks **safety or correctness**
with no easy recovery — data loss, secret exposure, irreversible shared-state
mutation, protected-branch writes. For **style / efficiency / consistency**
preferences ("use tool X instead of shell Y"), prefer a **non-blocking nudge**.

## Why a hard block on a style preference backfires

| Cost | Detail |
|---|---|
| **Subagent dead-end** | PreToolUse hooks fire in **every** context, including subagents — but the tool you redirect to (`Glob`, `Grep`, …) is not granted in every subagent toolset. A hard block can leave an agent with no shell form *and* no tool: no path forward. |
| **Fighting model fluency** | The model writes `find` / `grep` reliably; forcing an alternative it's less fluent in, that's sometimes unavailable, is a bad trade for a style win. |
| **False-positive treadmill** | Every block needs an exemption list (pipelines, flags, edge forms) that accretes patches over time. |

A non-blocking nudge keeps the steer (it teaches the better tool) without any of
these costs — the command still runs, so nothing is ever dead-ended.

## The litigation test (separate safety from style)

When deciding whether an existing block earns its exit-2, look at what it
**exempts**. If the block lets the genuinely dangerous form through, it was never
doing safety work — its only justification is style, which does not warrant a
hard block.

> Canonical tell: the `find`→`Glob` block always **exempted** `find -exec` (the
> arbitrary-execution form) and only blocked simple `find -name` searches. So it
> did no safety work; it fired in subagents lacking `Glob` (dead-ends); and it
> needed 4+ false-positive patches. It was demoted to the opt-in teach nudge in
> `bash-antipatterns-teach.sh` (claude-plugins #1871). The `cat` / `sed` /
> `echo > file` blocks **stayed** — those prevent real data-loss / correctness
> problems, so the exit-2 is earned.

## Quick test before adding (or keeping) a hard block

1. Does the command risk irreversible harm (data, secrets, shared state)? If no → nudge.
2. Does the block exempt the *dangerous* variant while blocking benign ones? If yes → it's style; nudge.
3. Does the redirect target a tool that may be absent in a subagent? If yes → never hard-block; nudge.
4. Add a regression test for whichever you choose (`regression-testing.md`).

## `onFailure: "block"` — fail closed, safety blocks only

By default a hook that cannot start, times out, or exits with a code other than
0 or 2 is a non-blocking error, so the action runs unchecked. Claude Code
2.1.295 added `"onFailure": "block"` on a `command` or `http` hook entry: a
failure then does what exit 2 does on that event. Older clients ignore the key
(2.1.294's `claude plugin validate` accepts any value for it), so the hook still
works there; only the fail-closed behaviour is lost. Set it on a hook whose
block is earned by the test above: `branch-protection`, `repo-deletion-safety`,
`external-pr-merge-guard` and `secret-protection` in `hooks-plugin`. Never set
it on a nudge, a logger, or an advisory guard. A nudge that fails closed turns
a style preference into a hard block that fires on every matching call, which
is the dead-end this rule exists to prevent. A fail-closed hook must exit 0 on
every path where it does not apply, including a missing `jq`/`git`, unparseable
input, a non-git cwd and macOS `/bin/bash` 3.2; `scripts/check-hook-fail-closed.sh`
checks both the key set and those paths.

## Related

- `.claude/rules/bash-tool-replacements.md` — the find/grep/cat substitutions and which ones still block
- `.claude/rules/handling-blocked-hooks.md` — the consumer side: what an agent does when a block fires
- `.claude/rules/offload-to-deterministic-substrate.md` — hooks as deterministic enforcement; don't double-gate auto mode
- `.claude/rules/prompt-agent-hooks.md` — when to reach for prompt/agent hooks
- `hooks-plugin/docs/teach-mode-experiment.md` — the non-blocking PostToolUse teach mechanism this rule points to
