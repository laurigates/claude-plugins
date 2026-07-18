# ADR-0020: Blueprint Autonomy Levels — Ambient Operations via a Manifest-Gated Level Model

---
id: ADR-0020
date: 2026-07-05
created: 2026-07-05
modified: 2026-07-18
status: Accepted
deciders: claude-plugins team
domain: automation
relates-to:
  - ADR-0005
  - ADR-0011
  - ADR-0016
  - ADR-0017
---

## Context

Blueprint operations are entirely user-initiated today. Work orders require the
human-only `/blueprint:work-order` command (`disable-model-invocation: true`);
maintenance tasks (`sync-ids`, `feature-tracker-sync`, `adr-validate`,
drain-wave) require manual sweeps; and many skills end in `AskUserQuestion`
menus. The goal driving this ADR: make blueprint **ambient** — its bookkeeping
runs itself and work orders get *proposed* automatically, while the user only
interacts with blueprint when they explicitly want to.

Three facts shape the design:

1. **The manifest already carries a dormant automation contract.** Every
   `task_registry` entry has `enabled`, `auto_run`, `schedule`
   (`weekly`/`daily`/`on-change`/`on-demand`), `last_completed_at`, and
   `last_result` fields — and `/blueprint:init` already *asks the user* how
   maintenance tasks should run and stores `auto_run` accordingly. Nothing
   implements the contract: no code computes due-ness or executes a due task.

2. **Registry tasks split into two kinds, and the kind determines which rail
   can run them** (per `.claude/rules/offload-to-deterministic-substrate.md`):
   *deterministic* tasks (the id-registry sweep behind `sync-ids`, tracker
   timestamp bookkeeping, drain-wave evidence moves) are runnable by command
   hooks/scripts with no model in the loop; *agent-judgment* tasks
   (`adr-validate`, `story-audit`, `curate-docs`, work-order drafting) need a
   model, so a command hook can only *surface* them.

3. **The automation rails already exist.** The SessionStart drift-probe →
   `drift-aggregator` pipe (`hooks-plugin/hooks/lib/drift-protocol.sh`) is the
   notify-only rail; PostToolUse hooks like
   `blueprint-plugin/hooks/auto-sync-id-registry.sh` are the working precedent
   for silent bounded auto-apply; `.github/workflows/scheduled-audits.yml`
   already runs a scheduled blueprint health job. What is missing is a
   *coherent, user-facing model* of how much autonomy blueprint has in a given
   repo — and the executors that honor it.

The tension to resolve: work orders are human-only *by design* (WO files are
gitignored and may carry sensitive detail; the committing act mutates
`tasks.pending` and the `id_registry`). Any automation must preserve that
safeguard rather than delete it.

## Decision

Adopt a **tiered autonomy-level model**, expressed in a new manifest
`automation` block (format 3.3.0 → 3.4.0, purely additive):

```json
"automation": {
  "autonomy_level": 0,
  "interaction_mode": "normal",
  "work_orders": { "auto_draft": false, "auto_execute": false }
}
```

| Level | Name | What runs automatically | Executor rail | Work-order stance |
|-------|------|-------------------------|---------------|-------------------|
| 0 | manual | nothing (today's behavior) | — | human `/blueprint:work-order` only |
| 1 | ambient bookkeeping | deterministic due tasks; on-change syncs; session-end drain | SessionStart/PostToolUse command hooks + `scripts/blueprint-autorun.sh` | unchanged |
| 2 | quiet autopilot | + agent-judgment due tasks in-session; quiet interaction mode | `blueprint-autopilot` skill, triggered by the drift nudge | + auto-**draft** WO issues; human promotes via `--from-issue` |
| 3 | scheduled pipeline (opt-in) | + out-of-band cron runs; approved-WO execution → PRs | GitHub Actions + claude-code-action | + auto-execute **approved** WOs; human reviews the PR |

### The deterministic runner (level 1)

`blueprint-plugin/scripts/blueprint-autorun.sh` implements the dormant
contract: it computes due-ness (`schedule` vs `last_completed_at`), executes
**deterministic** due tasks directly (currently: the `sync-ids` id-registry
sweep), writes back `last_completed_at`/`last_result`/`stats`, and reports due
**agent-judgment** tasks without executing them. It emits the
`=== SECTION ===`/`KEY=VALUE`/`STATUS=` convention
(`.claude/rules/structured-script-output.md`) and offers `--report` for a
dry-run. A SessionStart probe (`hooks/blueprint-autorun-probe.sh`, TTL-debounced
per `.claude/rules/drift-detection-triggering.md`) runs it and emits one drift
finding per due agent task into the existing aggregator pipe. `on-change` tasks
are event-driven (PostToolUse hooks), never runner-driven; `on-demand` tasks are
never due.

### The draft-issue side channel (level 2)

Automation never invokes `/blueprint:work-order` — `disable-model-invocation:
true` stays on it (and on `/blueprint:prp-execute`) permanently. Instead, the
level-2 `blueprint-autopilot` skill scans ready PRPs (confidence ≥ 9, via
`confidence-scoring`) that lack a work order and files GitHub issues labeled
`work-order-draft` carrying the full WO packet (or local files under
`docs/blueprint/work-orders/drafts/` in `--no-publish` repos). The *committing*
act — real WO file, `work-order` label, `tasks.pending` + `id_registry`
mutation — remains the human-invoked `/blueprint:work-order --from-issue N`
promotion. Drafts are deduped by label + PRP id and capped (default 5 open).

### Interaction mode

`automation.interaction_mode: "quiet" | "normal" | "interactive"` lets skills
skip their closing `AskUserQuestion` menus and end with a one-line receipt.
Level ≥ 2 defaults to `quiet`. **Direct invocation always wins**: a slash
command the user typed behaves fully interactively at every level — quiet mode
governs automation-initiated flows and closing menus only.

### Safety rails

- `enabled: false` always wins — a disabled task never runs at any level (this
  repo's constrained-dogfooding disables stay authoritative).
- `BLUEPRINT_AUTORUN_DISABLE=1` kills levels 1–2 locally regardless of manifest.
- Probes are read-only and TTL-debounced; auto-apply is bounded to
  deterministic, unambiguous facts (drift rules).
- A missing `automation` block ≡ level 0 — 3.3.0 manifests keep working
  unchanged.
- Level 3 (opt-in per consumer repo) requires the
  `.claude/rules/loop-integrity.md` machinery: an independent verifier (CI +
  fresh reviewer, never the executing agent) and issue-comment state packets
  per iteration; `blueprint-autorun.yml` follows the `blueprint-health` job
  pattern in `scheduled-audits.yml` with `--model opus --effort` pinned.

This repository dogfoods at level 1 with only the already-enabled read-leaning
tasks; consumer repos opt higher.

### Implementation status

Levels 0–2 shipped in PR #2003. **Level 3 shipped (issue #2005) as an opt-in
scaffold**, `/blueprint:autonomy-level3`, rather than as live workflows in this
repo (which is level-1 constrained and cannot exercise level 3). It installs
two templated workflows — `Blueprint: Autorun` (scheduled) and `Blueprint:
Execute approved work order` (`work-order-approved` label trigger) — plus the
deterministic gate/parser scripts, into a consumer repo. The
`blueprint-wo-guard.sh` gate keeps everything dormant until a consumer's
manifest sets `automation.autonomy_level >= 3` (and `work_orders.auto_execute:
true` for the executor). All the safety rails above (independent verifier +
state packets, per-run/per-day budgets + a `max_cycles` stuck ceiling, the
least-privilege + script-injection GitHub Actions baseline for the untrusted
issue-body WO packet) are implemented and guarded by
`scripts/check-blueprint-level3-templates.sh` plus the `blueprint-wo-packet.sh`
/ `blueprint-wo-guard.sh` regression suites.

## Options Considered

1. **Ambient bookkeeping only** (hooks + deterministic script, no model
   executor). Rejected as the whole answer: it never touches work-order
   proposal — the headline ask — and leaves the AskUserQuestion chattiness
   intact. It survives as **level 1**.

2. **Quiet in-session autopilot** (auto-invocable skill runs due tasks and
   drafts WOs). Right for in-session ambience but leaves nothing running when
   no session opens. Survives as **level 2**.

3. **Out-of-band scheduled pipeline** (GitHub Actions runs everything,
   including executing approved WOs into PRs). Highest risk: headless
   execution quality, loop-integrity machinery required up front, and this
   constrained repo cannot dogfood it. Survives as **level 3**, shipped as an
   opt-in scaffold (`/blueprint:autonomy-level3`, issue #2005) rather than live
   in this repo.

4. **Fully autonomous WO creation** (drop `disable-model-invocation` and let
   the model create real work orders). Rejected: it deletes a deliberate
   safeguard on a mutating, potentially sensitive act. The draft-issue side
   channel gets the ambient benefit while the committing act stays human.

5. **A single boolean `auto_run` implementation with no level model.**
   Rejected: the existing per-task flags cannot express "notify vs execute vs
   draft" distinctions, every downstream repo would re-derive its own policy,
   and there would be no single knob to answer "how out-of-the-way is
   blueprint here?".

## Consequences

### Positive

- The manifest's dormant `auto_run`/`schedule` contract finally executes, and
  `blueprint-init`'s existing maintenance-task question maps onto a real
  behavior (`Manual only` → 0, `Prompt` → 0, `Auto-run safe` → 1,
  `Fully automatic` → 2).
- One user-facing knob (`autonomy_level`) answers how ambient blueprint is in
  a repo; each level is an independently shippable rung.
- The human-only work-order safeguard is preserved as level semantics rather
  than deleted; proposals land where humans already review things (labeled
  GitHub issues).
- Deterministic work moves onto the deterministic substrate (ADR-0016), and
  surfacing reuses the existing drift-aggregator pipe (ADR-0017) instead of a
  new nudge channel.

### Negative

- A format bump (3.4.0) with migration surface: `blueprint-upgrade`,
  `blueprint-init`, the drift probe's `CURRENT_FORMAT_VERSION`, and
  `check-blueprint-upgrade-target.sh` all move together.
- Quiet mode threads a manifest read through ~6–12 skills — a recurring
  maintenance surface.
- More autonomy means more silent writes (manifest timestamps, id-registry
  refreshes); the structured output and `last_result` writeback are the audit
  trail, but a user who never reads them sees less of what blueprint does.

### Risks

| Risk | Mitigation |
|------|------------|
| Autopilot mis-fires in sessions where blueprint is irrelevant | Level-gated silent exit; only triggered by a drift finding that says tasks are due |
| Draft-issue noise if confidence scoring is generous | Dedupe by label + PRP id; open-draft cap; drafts are additive and closable |
| Ambient token cost at session start | TTL debounce; deterministic tasks cost zero model tokens; one-task-per-session budget for agent tasks |
| Level 3 runaway loops | Ships only with the loop-integrity verifier + state packets + per-run/per-day budgets + a `max_cycles` stuck ceiling (implemented; opt-in per repo) |

## Related ADRs

- [ADR-0005: Blueprint Development Methodology](0005-blueprint-development-methodology.md) — the document hierarchy this automates
- [ADR-0011: Blueprint State in docs/ Directory](0011-blueprint-state-in-docs-directory.md) — where the manifest and work orders live
- [ADR-0016: Extract Deterministic Skill Procedure into Structured-Output Scripts](0016-deterministic-script-extraction-for-token-efficiency.md) — the deterministic-substrate principle level 1 applies
- [ADR-0017: Hook-Based Behavioral Cues for Multi-Plugin Utilization](0017-hook-based-behavioral-cues-for-plugin-utilization.md) — the token-budget contract the autorun probe's findings obey
