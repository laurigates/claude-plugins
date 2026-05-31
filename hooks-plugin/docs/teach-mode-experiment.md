# bash-antipatterns teach-mode experiment

Status: **phase 1 — opt-in via env var.** Wired into `plugin.json` as a
PostToolUse Bash hook, but the script no-ops unless
`CLAUDE_HOOKS_ENABLE_BASH_ANTIPATTERNS_TEACH=1` is set. The existing
PreToolUse `bash-antipatterns.sh` blocks are unchanged.

## Motivation

The 2026-W20 friction analysis showed `grep`/`rg` vs the `Grep` tool
sitting at a **21% same-session
repeat-block rate** — about 2× the rate for established `bash-antipatterns`
blocks like `git &&` chains (8%) or `find` vs `Glob` (12%).

The hook itself is doing its job — every flagged event is a successful
PreToolUse block (exit 2). The agent never gets to run the antipattern.
But the block is also the *only* thing the agent sees. It reads:

> REMINDER: Use the Grep tool instead of 'grep' or 'rg' commands…

…has nothing concrete to compare against, and reaches for the same idiom
the next time it needs to search. For `git &&` the fallback is mechanical
("issue two Bash calls"), so one block teaches. For `grep`/`rg` the
fallback is abstract ("call a different tool with different ergonomics"),
so the lesson decays within the same session 21% of the time.

Claude Code 2.1.121 added `PostToolUse` `hookSpecificOutput.updatedToolOutput`
for **all** tools (PR #1301, `.claude/rules/hooks-reference.md`). That
unlocks a different teaching shape: let the command run, then prepend
the corrective hint to the result the agent sees. The agent gets the
data it asked for *and* the right-tool note in the same response.

## Hypothesis

> Replacing the PreToolUse exit-2 block with a PostToolUse output
> augmentation reduces the W20 same-session repeat-block rate on
> `grep`/`rg`/`find -name`/`cat`/`head`/`tail`/`ls *.glob` from ~21% to
> the established ~10% floor seen for `git &&` chains and `find -name`
> (post-hook).

The W21 friction pass will measure this directly.

## Scope: what teach-mode covers, what stays blocking

The existing `bash-antipatterns.sh` mixes three concerns. The experiment
splits them.

### Convert to PostToolUse teach (this draft)

| Pattern | Why it's a teach candidate |
|---|---|
| `cat <file>` (non-pipeline) | Read returns line-numbered content; command output is benign |
| `head`/`tail <file>` (non-pipeline) | Same as above |
| `find . -name …` (without `-maxdepth`/`-type`/`-print0`) | Glob is the right tool; `find` still works |
| `grep`/`rg` (non-pipeline, non-`-q`) | Grep tool is the right tool; output is benign |
| `ls <glob>` | Glob handles it better; output is benign |

For each of these, the command produces output the agent wants, and the
right response is "here is your output + the right tool to use next time."

### Stay PreToolUse blocking (no change)

| Pattern | Why it must remain a hard block |
|---|---|
| `git reset --hard` | Destroys uncommitted work |
| `curl … \| bash/sh/sudo` | Arbitrary code execution from network |
| `chmod 777` | Security risk |
| Writes to `/dev/sd*`, `/dev/nvme*`, … | Destroys filesystem |
| Fork bombs | Resource exhaustion |
| `git add -A` / `git add .` | Stages secrets / unintended files |
| `git X && git Y` (index-modifying) | `.git/index.lock` race |
| `git push -u origin <other-branch>` on `main`/`master` | Wrong upstream |
| `cat > /tmp/commit_msg.txt` heredoc pattern | Wrong workflow shape |
| Reading `*.output` task files with cat/tail | Should use TaskOutput tool |
| `sed -i` / `awk > file` / `echo > file` / `cat > file` | Better via Edit/Write; mutating |
| Long pipelines (5+ pipes) | Over-complexity signal |
| `timeout` wrapper | Redundant; Bash tool has its own |

These either destroy state, leak data, or change files. PostToolUse is
too late — the damage is done by the time the hook fires.

## Files in this draft

| Path | Purpose |
|---|---|
| `hooks-plugin/hooks/bash-antipatterns-teach.sh` | New PostToolUse hook (added) |
| `hooks-plugin/hooks/bash-antipatterns.sh` | **Unchanged** during phase 1 |
| `hooks-plugin/docs/teach-mode-experiment.md` | This doc |

Phase 1 deliberately leaves the existing hook intact. The teach hook is
purely additive and produces no output for commands it doesn't recognise,
so it's safe to enable alongside the existing block. The repeat-block
metric in W21 will tell us whether to flip the default.

## Phased rollout

### Phase 1 — Side-by-side (this PR, opt-in via env var)

1. Ship `bash-antipatterns-teach.sh`.
2. Wire it into `hooks-plugin`'s `plugin.json` as a PostToolUse `Bash`
   matcher with a 5000ms timeout.
3. Gate it with `CLAUDE_HOOKS_ENABLE_BASH_ANTIPATTERNS_TEACH=1` at the
   top of the script (matches `event-logger.sh`'s opt-in convention),
   so the hook fires on `plugin.json` but no-ops unless the user
   explicitly enables it.
4. Leave the existing PreToolUse `bash-antipatterns.sh` blocks
   completely unchanged.

Opt in for a session by exporting the env var before launching:

```bash
CLAUDE_HOOKS_ENABLE_BASH_ANTIPATTERNS_TEACH=1 claude
```

Or set it durably via the env-var table in `hooks-plugin/README.md` —
`.claude/settings.json` `env` block, shell profile, or `mise` env file.

**Important caveat** — the teach hook only fires when the PreToolUse
block didn't. With the env var on and the existing
`bash-antipatterns.sh` still blocking `grep`/`rg`/`find -name`/etc., the
matched commands never run, so PostToolUse never fires either. To
actually observe teach-mode in phase 1, also override the PreToolUse
block for the soft-teach set — either via narrow allow rules in
`.claude/settings.json` or by forking a project-local copy of
`bash-antipatterns.sh` with the soft-teach blocks removed. Phase 2
(W21 evaluation) decides whether to drop the soft-teach blocks from
`bash-antipatterns.sh` itself.

### Phase 2 — W21 friction evaluation (2026-05-18)

Measure on sessions running the teach config:

- Same-session repeat-block rate for `grep`/`rg`/`find -name`/`cat`/`head`/`tail`/`ls *.glob`
- Per-session attempt rate (does the count fall as agents learn?)
- Cost: tokens added per teach event (the corrective hint is ~30 tokens)

Compare against the W20 baseline (21% repeat-block on `grep`/`rg`).

Success criterion: **repeat-block rate ≤ 12%** on sessions using teach
mode, with no measurable increase in mistaken-tool-use downstream
(i.e. the agent doesn't start treating the augmented hint as adversarial
noise and stop reading tool output).

### Phase 3 — Promote or revert (W22+)

- **If success criterion met**: promote teach mode in `hooks-plugin`'s
  default `hooks.json`, strip the soft-teach blocks from
  `bash-antipatterns.sh` (keep the security-critical ones), document
  the new shape in `.claude/rules/bash-tool-replacements.md`.
- **If not met**: revert. Document why in the W2X friction analysis
  and re-investigate.

## Implementation notes

### Pattern detection

The teach hook reuses the exact regex/anchor logic from
`bash-antipatterns.sh` for the five soft-teach patterns. Tests should
share fixtures so the matcher stays in lock-step across both hooks. A
follow-up PR can extract the regex set into a shared helper.

### Output shape

`hookSpecificOutput.updatedToolOutput` is a **string**, and it
**replaces** what the model sees as the tool result — not appends to it.
So the hook stringifies `tool_response` and constructs the full
augmented payload:

```
<original tool_response>

--- bash-antipatterns hint ---
💡 <one-line corrective hint with concrete tool example>
```

The leading blank line and the divider keep the hint visually distinct
from command output. The 💡 prefix mirrors the existing reminder hook's
voice without re-using the "REMINDER:" prefix (which signals
exit-2-blocking to model and reader).

### What we don't try in phase 1

- **Stripping the soft-teach blocks from `bash-antipatterns.sh`.** That
  changes the default for every existing user. Phase 1 is opt-in.
- **Tracking per-session lesson decay inside the hook.** Tempting
  ("after 2 hints, switch to exit-2 blocking"), but adds state to a
  stateless hook and is best left to the friction analyser.
- **Augmenting the security-critical blocks.** They stay exit-2.
  No data benefit, real security cost.
- **Updating `.claude/rules/bash-tool-replacements.md`.** The rule
  documents the *current* hook behaviour. We change the rule when
  phase 3 promotes the teach config.

## Risks

| Risk | Mitigation |
|---|---|
| Agent treats the augmented output as adversarial and stops reading tool results | Phase 1 is opt-in; W21 metric catches this |
| `updatedToolOutput` not yet on the user's Claude Code version (<2.1.121) | Document the version requirement; teach hook degrades to silent passthrough on older versions |
| Hint adds tokens to every soft-teach call | Tracked in phase 2 metric; ~30 tokens/call is small vs the typical Bash result, but real |
| The five soft-teach patterns drift between the two hooks | Phase 3 consolidates into a shared matcher; phase 1 documents the duplication |

## Open questions for review

1. **Phase 1 default = opt-in.** Should the default `hooks.json` ship the
   teach hook disabled (current draft) or enabled-alongside-blocking
   (more data, but every user pays the token cost)? Current draft errs
   conservative.
2. **Hint voice.** Current is `💡` + one short imperative sentence with
   a concrete tool-call example. Alternative: drop the emoji, use
   plain `NEXT TIME:` prefix. No strong opinion.
3. **`find` `-name` handling.** The existing hook allows `find` with
   `-maxdepth`/`-type`/`-print0`. The teach hook matches the same
   exemption. If we ever want to teach `find -maxdepth -name` → "Glob
   handles this too, only need find for `-type d`", that's a separate
   rule change, not part of this experiment.
4. **`ls <glob>` priority.** The matcher currently picks the most
   specific pattern; `ls -1 src/*.ts` matches the `ls *` hint. That's
   correct, but if `ls -1 *.ts` was meant to feed a pipeline, the hint
   is noise. Should the matcher exempt `ls` when stdout is being
   redirected or piped? (Currently no — but neither does the existing
   PreToolUse block.)

## Related

- `.claude/rules/hooks-reference.md` — `PostToolUse` / `updatedToolOutput` reference
- `.claude/rules/bash-tool-replacements.md` — current rule prose (no edits in phase 1)
- `hooks-plugin/hooks/bash-antipatterns.sh` — existing PreToolUse hook
