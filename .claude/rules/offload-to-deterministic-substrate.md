# Offload Mechanical Work to a Deterministic Substrate — plugin-authoring deltas

The canonical statement of this principle is the global rule
`~/.claude/rules/offload-to-deterministic-substrate.md` (chezmoi source:
`exact_dot_claude/rules/offload-to-deterministic-substrate.md`). Read it first
— this file holds only what is specific to authoring plugins, skills, and hooks
in *this* repo, and names the children that already implement the law here.

> **The law (short form):** anything mechanical, repeatable, and verifiable
> belongs outside the agent's reasoning loop — in a script, hook, or
> structured-output contract the agent invokes and consumes. The agent decides;
> the substrate verifies and remembers.

## Why it bites hardest when authoring plugins

A skill *is* a substrate-authoring act. Every skill you write is a chance to
either (a) bake a mechanical step into a deterministic script the skill calls,
or (b) leave it as prose the consuming agent re-derives every invocation. The
default failure is (b): the skill describes a check in English, and each run
spends context re-implementing it slightly differently.

| When writing a… | Push the mechanical part into… | Don't leave it as… |
|---|---|---|
| Skill that runs diagnostics | A `check-*.sh` emitting `STATUS=`/`KEY=VALUE` (`structured-script-output.md`) | Prose the agent parses by eye |
| Skill that detects drift | The existing sweep script + an autonomous trigger (`drift-detection-triggering.md`) | A "remember to check X" instruction |
| Self-continuing / looping skill | A mechanical stop gate or fresh independent verifier (`loop-integrity.md`) | The worker agent judging its own "done" |
| Guardrail that must always fire | A PreToolUse/SessionStart hook in `hooks-plugin` | A rule the agent is asked to honor each time |
| Bug fix in a skill | A `scripts/check-*.sh` regression check (`regression-testing.md`) | A changelog note and hope |

## The children (each applies the law to one situation)

- `structured-script-output.md` — **context economy**: the `=== SECTION ===` / `KEY=VALUE` / `STATUS=` contract so orchestrating skills roll up checks cheaply.
- `drift-detection-triggering.md` — **enforcement/triggering**: the sweep is already deterministic; mount it on a trigger, don't rewrite the logic.
- `loop-integrity.md` — **independent enforcement**: the stop condition is judged by a fresh actor or a mechanical gate, never the worker.
- `regression-testing.md` — **determinism as memory**: every fixed bug gets a script check so it can't silently return.
- `bash-tool-replacements.md` + the `bash-antipatterns` hook — a hook deterministically enforcing tool hygiene the agent would otherwise re-remember.

## Cautions specific to this repo

- **YAGNI still applies** (`code-quality.md` upstream). A skill used once doesn't need a script extracted; the payoff is in repeated mechanical work.
- **Don't double-gate** (`auto-mode.md`). A new hook that re-implements what auto mode or an existing hook already covers should defer, not stack.

## Related

- `~/.claude/rules/offload-to-deterministic-substrate.md` — the canonical global statement (parent)
- `.claude/rules/structured-script-output.md`
- `.claude/rules/drift-detection-triggering.md`
- `.claude/rules/loop-integrity.md`
- `.claude/rules/regression-testing.md`
- `.claude/rules/bash-tool-replacements.md`
