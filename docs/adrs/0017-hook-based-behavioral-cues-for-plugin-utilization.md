# ADR-0017: Hook-Based Behavioral Cues for Multi-Plugin Utilization

---
date: 2026-06-13
created: 2026-06-13
modified: 2026-06-13
status: Proposed
deciders: claude-plugins team
domain: architecture
relates-to:
  - ADR-0003
  - ADR-0015
  - ADR-0016
github-issues:
  - 1599  # Behavioral forcing functions and point-of-performance hooks
---

## Context

The plugin collection has grown to ~40 plugins and 300+ skills across many
domains. Issue #1599 observes that high-leverage, specialized plugins
(`blueprint-plugin`, `evaluate-plugin`, `taskwarrior-plugin`,
`codebase-attributes-plugin`, …) are **underutilized**: because tool selection
relies on the model's latent attention over a large, flat manifest, agents
frequently drop into generic edit loops instead of routing work to the right
specialized plugin. The issue proposes moving from *implicit discovery* to an
*explicit, system-designed* environment using four behavioral mechanisms —
forcing functions, point-of-performance cues, deterministic task chaining, and
poka-yoke — and one concrete action item: **"add a `next_action_hints` array to
the base schema of all plugin tools."**

Two findings reshape that proposal.

### Most of the assumed infrastructure already exists

The repository already ships a mature, multi-mechanism behavioral layer through
the two surfaces Claude Code actually supports — **hooks** (scripts the harness
runs at lifecycle events) and **skills** (markdown the model reads):

- **Forcing functions / gates** are live in `hooks-plugin`.
  `hooks/branch-protection.sh` (PreToolUse, matcher `Bash`) emits
  `permissionDecision: deny|ask` to gate `git commit`/`push`/`reset`/`rebase`
  on protected branches. `hooks/bash-antipatterns.sh` (PreToolUse) blocks ~15
  dangerous or wasteful idioms via exit-2. `hooks/task-completeness.sh` and the
  `TaskCompleted` test-verification hook gate completion.
- **Point-of-performance cues** exist as the non-blocking counterpart.
  `hooks/bash-antipatterns-teach.sh` (PostToolUse) appends a corrective hint via
  `updatedToolOutput` and **deduplicates per session** under
  `${TMPDIR}/claude-bash-teach-seen/<session_id>`.
  `session-plugin/hooks/session-spinup-nudge.sh` (SessionStart) injects
  `additionalContext` offering `session-spinup`; `session-end-nudge.sh` (Stop)
  offers `session-end` — both fire at most once per session.
- **Poka-yoke / defect prevention** is the loud-failure contract in
  `agent-patterns-plugin/skills/parallel-agent-dispatch/SKILL.md`, which mandates
  a `status: success|partial|failed` return so a one-word `Terminal.` cannot
  pass as success (#1422), with optional `SubagentStop` enforcement.

### The headline proposal rests on a category error

Plugins do **not** expose "tools with a base schema." They ship skills (markdown
instructions read by the *model*) and hooks (scripts run by the *harness*). The
Claude Code harness does **not** introspect arbitrary tool output for a
plugin-defined `next_action_hints` array — there is no such field and no code
path that scans for one. The only channels that can inject a behavioral cue are
fixed by the harness and documented in `.claude/rules/hooks-reference.md`:

| Channel | Event | Effect |
|---|---|---|
| `permissionDecision: allow\|deny\|ask` | PreToolUse | gate a tool call |
| `hookSpecificOutput.updatedToolOutput` | PostToolUse | append/replace a tool's result text |
| `{"decision":"block","reason":…,"continueOnBlock":true}` | PostToolUse | feed a reason back and continue the turn |
| `hookSpecificOutput.additionalContext` | SessionStart, UserPromptSubmit | prepend context to a turn |
| `{"decision":"block","reason":…}` | Stop, SubagentStop | nudge before the turn ends |

Critically, every channel that reaches the model carries a **transcript-replay
cost** (`hooks-reference.md`, "Transcript Replay Cost"): injected text is
re-sent on every subsequent turn. A hint on a high-frequency tool costs its
token count × every remaining turn. This is exactly why the existing cue hooks
fire conditionally, dedup per session, and self-extinguish — and why a blanket
per-tool hint array would be the single most expensive possible shape.

## Decision

**Adopt hooks as the substrate for behavioral cues that route work toward
underutilized plugins, governed by a token-budget contract. Reject the literal
`next_action_hints` tool-schema item as infeasible and substitute the
hook-based equivalents below. Implement cues distributed across each plugin's own
manifest, one narrow worked example at a time, each with a regression test.**

### Reframe: issue mechanism → feasible form

| Issue mechanism | Feasible hook-based mechanism | Status today | Evidence |
|---|---|---|---|
| Forcing function / gate | PreToolUse `deny`/`ask`; Stop/TaskCompleted `block` | **Exists** | `branch-protection.sh`, `bash-antipatterns.sh`, `task-completeness.sh` |
| Point-of-performance cue | PostToolUse `updatedToolOutput`; SessionStart `additionalContext` — conditional, deduped, self-extinguishing | **Partial** | `bash-antipatterns-teach.sh`, `session-spinup-nudge.sh`, `drift-aggregator.sh`. Broad per-plugin coverage is the **gap** this ADR opens |
| Deterministic task chaining | SlashCommand invocation between skills; session bookends | **Partial** | `session-plugin` spinup→work→end; no declarative "after tool X suggest Y" surface |
| Poka-yoke / defect prevention | Mandated return-contract schema; optional `SubagentStop` enforcement | **Exists** | `parallel-agent-dispatch` loud-failure contract (#1422) |

The realizable form of "next-action hints on every tool" is already the
PostToolUse `updatedToolOutput` cue pattern — and its own author comments
document why it must be capped and deduped rather than emitted on every call.

### The token-budget contract

A cue is text the model sees, so it is never a one-time cost — it is
`~tokens × every remaining turn`. Every behavioral-cue hook MUST:

1. **Be conditional** — exit 0 silently when there is no concrete signal. An
   unconditional cue pays full replay cost for zero value.
2. **Be deduped** — fire at most once per session, keyed on
   `~/.cache/<hook-name>/<session_id>` (the convention `session-spinup-nudge.sh`
   already uses).
3. **Be terse** — a single sentence naming the underused plugin and the trigger;
   no narration (per `.claude/rules/agentic-optimization.md`).
4. **Prefer the cheapest event** — SessionStart fires once; a PostToolUse cue on
   a frequent tool is the most expensive shape.

| Event | Replays each turn? | Indicative cost | Verdict for cues |
|---|---|---|---|
| SessionStart `additionalContext` | yes (from first turn) | ~30 tok × remaining turns | **Preferred** — amortized |
| Stop `block` reason | yes, until cleared | ~30 tok × turns until cleared | Good when self-extinguishing |
| UserPromptSubmit context | yes, every turn | ~30 tok × every turn | Only if hard-gated + deduped |
| PostToolUse `updatedToolOutput` | yes (× calls) | ~30 tok × calls × remaining turns | **Avoid** unless rare-tool + deduped |
| Exit 0, disk only | no | 0 | Free, but invisible — not a cue |

### Worked example (first MVP): blueprint cue on structural change

A `PostToolUse` hook owned by `blueprint-plugin` that detects
architecture-affecting edits and, **once per session**, injects a terse cue to
check blueprint context. This ADR specifies it; implementation is a follow-up PR.

- **Trigger.** Matcher `Edit|Write`. Detection starts **narrow** and fires only
  on concrete structural signals, never on every edit: (1) `tool_input.file_path`
  basename is `plugin.json` or `marketplace.json`; (2) the edit adds/removes a
  public-symbol line (`new_string`/`content` matches
  `^[+-]?\s*(export|pub |public |module\.exports|def __all__)`); (3) `file_path`
  matches `docs/adrs/**` or `docs/prds/**`. Absent all three → exit 0 silently.
  False negatives are cheap; false positives train the model to ignore the cue.
- **Dedup.** Marker file `~/.cache/blueprint-structural-cue/<session_id>`,
  fire-once. Empty/absent `session_id` → graceful no-op. Shell follows
  `set -uo pipefail` with prefixed variable names (`.claude/rules/shell-scripting.md`).
- **Channel.** `additionalContext` is **not** a valid PostToolUse field (verified
  against `hooks-reference.md` — it is SessionStart/UserPromptSubmit only).
  Use `hookSpecificOutput.updatedToolOutput` to append the cue to the edit's own
  result (cleanest — no turn-flow interaction); `{"decision":"block",
  "continueOnBlock":true,"reason":…}` is the alternative when the cue should make
  the model actively re-decide. Cue text, ≤25 words: *"Structural change detected
  (manifest / public API / ADR). Consider `/blueprint:blueprint-derive-plans` or
  `blueprint-adr-validate` to keep blueprint context current."*
- **Wiring.** `blueprint-plugin/hooks/blueprint-structural-cue.sh`, registered
  under `PostToolUse` (matcher `Edit|Write`) in
  `blueprint-plugin/.claude-plugin/plugin.json`.
- **Regression test** (`.claude/rules/regression-testing.md`).
  `test-blueprint-structural-cue.sh` asserts semantic invariants: (a) a structural
  edit fires once and the output contains the `blueprint-derive-plans` cue; (b) a
  trivial edit (README/comment) is silent (empty stdout, exit 0); (c) a second
  structural edit with the marker present is silent (proves fire-once); (d)
  absent `session_id` is a no-op. A `CUE_CACHE_DIR` test seam redirects the marker
  to a tmp dir, and the test **pins the JSON field name** so a bulk edit cannot
  silently swap to the unsupported `additionalContext`.

### Discussion-point answers (#1599)

- **Q1 — avoid context/token bloat?** Bind every cue to the token-budget
  contract above: conditional firing, per-session dedup, one terse line, cheapest
  event. This caps a cue's lifetime cost at roughly one amortized injection
  rather than per-turn or per-call accumulation. Caveat: per
  `.claude/rules/auto-mode.md` the auto-mode classifier sees tool results
  *stripped*, so cues nudge the **model**, never the **classifier** — they must
  not be relied on to gate permissions.
- **Q2 — centralized manifest vs distributed metadata?** **Distributed.** Each
  plugin owns its cue hook in its own `plugin.json`, exactly as `session-plugin`
  and `hooks-plugin` already register their nudges, governed by the shared
  token-budget contract. Rationale: locality (the cue lives beside the plugin it
  promotes), independent release-please versioning, and no central
  merge-contention bottleneck. Tradeoff: no single file lists every cue —
  mitigate with a lightweight generated registry doc (cue hooks, events, dedup
  keys), keeping enforcement in the shared rule and visibility in docs.

## Consequences

### Positive

- **Explicit discovery without manifest bloat** — cues steer the model toward
  specialized plugins at the point of performance, addressing #1599's core
  problem through proven infrastructure rather than a new tool schema.
- **Reuses battle-tested patterns** — the conditional / deduped / terse hook is
  already validated by `bash-antipatterns-teach.sh` and the session nudges.
- **Distributed ownership** keeps each cue versioned and reviewed beside its
  plugin.

### Negative

- **Every cue is replayed-transcript cost** — the contract bounds it but cannot
  eliminate it; cues compete for the same context budget they aim to save.
- **Two-surface maintenance** — a cue hook plus its regression test per plugin,
  and a registry doc to keep current.

### Risks

| Risk | Mitigation |
|------|------------|
| Cue fatigue / over-firing trains the model to ignore cues | Dedup-once-per-session + narrow signal gating; start with one cue |
| "Structural" detection misjudged (false positives) | Start narrow (manifests + public-symbol lines + ADR/PRD paths); widen only on evidence |
| Cue collisions (multiple plugins nudge at once) | Registry doc lists all cues, events, dedup keys for audit |
| Unsupported hook field used (`additionalContext` on PostToolUse) | Verified channel table here; regression test pins the field name |

## References

- `.claude/rules/hooks-reference.md` — authoritative hook event/output schemas and replay cost
- `.claude/rules/prompt-agent-hooks.md` — when to use command/prompt/agent hooks
- `.claude/rules/agentic-optimization.md` — machine-readable / compact-output principle
- `.claude/rules/auto-mode.md` — classifier sees stripped tool results (cue caveat)
- `.claude/rules/regression-testing.md` — test-per-fix requirement for the worked example
- `hooks-plugin/hooks/branch-protection.sh`, `bash-antipatterns-teach.sh` — existing gate + cue references
- `session-plugin/hooks/session-spinup-nudge.sh`, `session-end-nudge.sh` — dedup-per-session nudge pattern
- `agent-patterns-plugin/skills/parallel-agent-dispatch/SKILL.md` — loud-failure / poka-yoke contract
- [ADR-0003: Auto-Discovery Component Pattern](0003-auto-discovery-component-pattern.md)
- [ADR-0015: Adopt Agent Teams and Deprecate Manual Orchestration](0015-agent-teams-adoption.md)
- [ADR-0016: Extract Deterministic Skill Procedure into Structured-Output Scripts](0016-deterministic-script-extraction-for-token-efficiency.md)
- `blueprint-plugin/docs/behavioral-cue-registry.md` — registry of all cue hooks: events, matchers, channels, dedup keys
