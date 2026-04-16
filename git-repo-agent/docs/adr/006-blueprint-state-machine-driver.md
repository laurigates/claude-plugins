# ADR-006: Python State-Machine Driver for the Blueprint Lifecycle

- **Status:** Accepted
- **Date:** 2026-04-15
- **Deciders:** @laurigates

## Context

The `blueprint` subagent (`agents/blueprint.py` + `prompts/blueprint.md`) was a
single LLM Task call loaded with several compiled skills from
`prompts/compiler.py::SUBAGENT_SKILLS["blueprint"]`. It was expected to internally
sequence the entire init workflow — create the blueprint structure, derive PRDs,
derive ADRs, assign IDs, validate ADR relationships, sync feature tracker — in
one conversation.

### The Problem

An audit (2026-04-15) against `blueprint-plugin/skills/` found:

- The subagent referenced only 7 of ~25 user-invocable blueprint skills.
- The blueprint plugin had shipped v3.3 monorepo support (PR #1026, 2026-04-13)
  adding `blueprint-workspace-scan`, `blueprint-feature-tracker-status`, and
  `blueprint-feature-tracker-sync`, plus monorepo-aware behavior in
  `blueprint-init`, `blueprint-status`, and `blueprint-adr-validate`. The agent
  was unaware of all of it.
- The "just append the missing skills" remedy would balloon the subagent prompt
  to 20+ compiled skills in a single LLM call. Every invocation would pay the
  token cost for skills it doesn't need that run, and the LLM might still skip
  mandatory steps (`sync-ids`, `adr-validate`) because they feel secondary.

### Why a Deterministic Driver

Blueprint skills are already designed as discrete, idempotent units that
communicate through disk artifacts (`docs/blueprint/manifest.json`,
`feature-tracker.md`). That makes them a natural fit for a Python state
machine: each step is one LLM call with exactly one compiled skill, and
Python reads the filesystem between steps to decide branching.

Precedent: ADR-003 already established the multi-`ClaudeSDKClient` pattern
(`_stream_interactive()` in `orchestrator.py` runs a two-phase flow for
`maintain` where Python collects user input between phases).

## Decision

Replace the monolithic `blueprint` subagent with a Python driver module,
`blueprint_driver.py`, that sequences the blueprint lifecycle as discrete
phases. Each phase:

1. Loads exactly one compiled skill as its system prompt, via the new
   `get_compiled_skill()` helper in `prompts/compiler.py`.
2. Opens a fresh `ClaudeSDKClient` session with that system prompt and a
   focused user-turn invocation.
3. Streams the result, then closes.

Between phases, Python reads the manifest and directory state so subsequent
phases can skip or adapt (e.g., `init` is skipped if `manifest.json` exists).

Onboard sequence (9 phases):

| # | Phase | Skill | Model |
|---|---|---|---|
| 1 | `workspace_scan` | `blueprint-workspace-scan` | haiku |
| 2 | `init` | `blueprint-init` | sonnet |
| 3 | `derive_prd` | `blueprint-derive-prd` | sonnet |
| 4 | `derive_adr` | `blueprint-derive-adr` | sonnet |
| 5 | `derive_rules` | `blueprint-derive-rules` | sonnet |
| 6 | `derive_tests` | `blueprint-derive-tests` | sonnet |
| 7 | `sync_ids` | `blueprint-sync-ids` | haiku |
| 8 | `adr_validate` | `blueprint-adr-validate` | haiku |
| 9 | `feature_tracker_sync` | `blueprint-feature-tracker-sync` | haiku |

`orchestrator.run_onboard()` invokes the driver immediately after worktree
creation. When the driver finishes it sets `blueprint_already_done=True`,
which flips `SKIP_BLUEPRINT=True` in the orchestrator agent's environment so
the LLM does not re-delegate to the `blueprint` Task.

The legacy `agents/blueprint.py` and `prompts/blueprint.md` remain in the
tree as a fallback for any future caller that still relies on the Task-based
path; they can be deleted once `maintain` / `diagnose` also migrate.

## Consequences

### Positive

- **No prompt bloat.** Each LLM call sees one skill, not twenty.
- **Guaranteed ordering.** Python runs every phase in sequence; the LLM
  cannot skip `sync-ids` or `adr-validate`.
- **Per-phase model tiering.** Mechanical phases use `haiku`; derivation
  phases use `sonnet`.
- **Resumable.** Phases persist their work to disk. A failure in phase 5
  leaves phases 1–4 intact; rerun from phase 5.
- **Testable.** Each phase is a unit with well-defined I/O.
- **Extensible.** Adding `blueprint-upgrade`, `blueprint-status`, etc. is
  a new `Phase` dataclass entry, not a prompt surgery.
- **Covers the v3.3 monorepo gap automatically** — `workspace_scan` and
  `feature_tracker_sync` are in the default sequence.

### Negative

- **More Python code to maintain.** Partially offset by simpler prompts.
- **Less adaptive.** The LLM can't invent novel orderings when the repo
  has unusual state. Mitigated by the driver reading manifest state and
  letting each skill be idempotent.
- **Cross-phase state travels through disk.** This is by design — the
  blueprint skills were already built to read/write `manifest.json` and
  `feature-tracker.md` as the canonical state store.

### Neutral

- `agents/blueprint.py` / `prompts/blueprint.md` remain for now. The
  `blueprint` entry in `SUBAGENT_SKILLS` also remains so the legacy Task
  path still compiles its skills if someone calls it.

## Alternatives Considered

1. **Append the 15 missing skills to the existing subagent.**
   Rejected — prompt bloat, and doesn't fix the LLM-skips-steps problem.
2. **Split blueprint into multiple subagents.**
   Rejected — still LLM-orchestrated, still no determinism guarantee.
3. **Replace the orchestrator entirely with a Python state machine.**
   Rejected as too large a change. Scope this ADR to blueprint only;
   revisit for `configure`, `docs`, etc. if similar problems emerge.

## Implementation Status

Shipped (2026-04-15):

**Static phase registries** (`git-repo-agent blueprint <mode>`):

- `onboard` — 9 phases, wired into `run_onboard()`.
- `status` — `blueprint-status` + `blueprint-feature-tracker-status`.
- `upgrade` — `blueprint-upgrade` → `sync-ids` → `adr-validate`.
- `sync` — `blueprint-sync` (drift detection, non-interactive).
- `scan` — `workspace-scan` → `feature-tracker-sync` → `feature-tracker-status`.
- `adr-list` — `blueprint-adr-list` (read-only).
- `derive-plans` — `blueprint-derive-plans` (one-shot PRD/ADR/PRP derivation).
- `generate-rules` — `blueprint-generate-rules` (rules from PRDs).

**Dynamic phase factories** (arg-taking CLI subcommands):

- `promote <target>` — `make_promote_phase(target)`.
- `prp-create <feature>` — `make_prp_create_phase(feature)`.
- `prp-execute <prp-name>` — `make_prp_execute_phase(prp_name)`.
- `work-order [--from-issue N] [--no-publish]` — `make_work_order_phase(...)`.

Factories build one-off `Phase` objects with the runtime argument
interpolated into the invocation text. The driver runs them via the
same `run(phases)` entry point used by static registries, so CLI,
state management, and streaming output are unified.

All lifecycle commands run in-place on the target repository — no
worktree, no PR — because they are typically read-only or targeted
updates rather than broad onboarding work.

Not yet shipped — candidates for a follow-up:

- `blueprint-rules` — heavily interactive "manage modular rules"
  flow; does not fit the non-interactive driver model cleanly.
- Deletion of the legacy `agents/blueprint.py` / `prompts/blueprint.md`
  once `run_maintain` and `run_diagnose` also migrate (they still reference
  the Task-based subagent).

## Related

- ADR-001 — Pre-compute repo context in Python.
- ADR-003 — Multi-`ClaudeSDKClient` precedent (`_stream_interactive`).
- ADR-004 — Worktree isolation (the driver runs inside the worktree).
