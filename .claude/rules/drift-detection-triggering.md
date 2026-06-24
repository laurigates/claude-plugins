---
paths:
  - "**/hooks/**"
  - "**/*drift*"
  - "**/*reconcile*"
  - "**/*sync*"
---
# Drift Detection: Triggering, Not Logic

When some local state goes stale relative to an authoritative source — a
taskwarrior task vs. its GitHub issue, a local branch vs. its PR, a vendored
copy vs. upstream, a cache vs. the data it mirrors — the recurring complaint is
"it drifts unless I remember to sweep." The instinct is to go write the
sweep. Usually the sweep **already exists** as a deterministic script; what's
missing is **autonomous triggering**. Separate the two before building.

## The three observations

| Observation | Consequence |
|---|---|
| **The fix is often a triggering gap, not a logic gap.** The reconcile/sweep computation is deterministic and frequently already scripted (e.g. `reconcile.sh`). | Don't rewrite the logic. Mount the existing script on a trigger that fires without a human. |
| **State that isn't a local event must be polled, not awaited.** A forge issue/PR closing fires nothing on your machine; a dead process *is* locally observable (`kill -0`). | Poll-only for remote/derived state (SessionStart probe + scheduled job); event/hook for locally-observable state. This is why `bugwarrior` is a cron tool, not a daemon. |
| **An expensive (network) drift check must stay cheap at SessionStart.** | Debounce the poll behind a **per-project TTL cache** so the `gh`/API round-trips run at most once per interval; the fast path reads the cache and costs nothing. Claim the debounce window *before* the slow call so a killed run degrades to "no change" rather than re-polling every session. |

## Routing a drift check to its trigger

| Is the change observable as a local event? | Mechanism |
|---|---|
| **No** — remote/derived state (forge issue/PR, upstream HEAD, an external API) | **Poll**: a `drift-protocol` SessionStart probe (debounced) and/or a scheduled job. Reuse the existing reconcile script in **dry-run** to *surface*; reserve mutation for an explicit/scheduled apply. |
| **Yes** — local state (a dead PID, a missing file, a config hash) | **Event/hook**: a SessionStart/PreToolUse hook or native `on-modify` hook can act deterministically, no poll needed. |

## Safety rails for an autonomous drift surfacer

- **Read-only by default.** A probe *surfaces* (a `drift_add_finding` nudge); it never closes/deletes. Mutation needs an explicit skill invocation or a bounded scheduled apply.
- **Never act on uncertainty.** If upstream state can't be read (`GH_AVAILABLE=false`, network down), emit nothing — never "0 drift" and never a close.
- **Bounded auto-apply only on facts.** A scheduled apply may auto-resolve only *unambiguous* verdicts (issue closed, PR merged) — never the ambiguous ones (PR closed-unmerged: abandoned? superseded?).
- **Opt-out + tunable cadence.** Expose an env opt-out and a TTL override; the network poll is a cost some users won't want at every session start.

## Canonical implementation

`taskwarrior-plugin/hooks/taskwarrior-drift-probe.sh` — extends a UDA-check
SessionStart probe to also run `task-reconcile`'s `reconcile.sh` in dry-run,
debounced behind a per-project TTL cache, emitting a `stale_linked_tasks`
finding. The locally-observable sibling (dead-PID claim release) and the
scheduled-poll sibling are tracked as follow-ups (laurigates/claude-plugins
#1792, #1793).

## Related

- `.claude/rules/agent-coworker-detection.md` — local-event drift signals (the hook/event side)
- `.claude/rules/pr-branch-sync.md` — the remote PR-drift probe family this pattern generalizes
- `.claude/rules/structured-script-output.md` — the `STATUS=`/`KEY=VALUE` shape a reconcile script emits and a probe parses
- `.claude/rules/parallel-safe-queries.md` — the `export | jq` (exit-0-on-empty) idiom drift queries follow
