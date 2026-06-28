# Workflow: session-plugin + two-speed feedback architecture

Status: **Phases 0–3 done** — Phase 0 locked 2026-06-04; Phase 1 audit landed via
[#1503](https://github.com/laurigates/claude-plugins/issues/1503); Phases 2–3
landed 2026-06-10 (session-plugin created: generalized `session-spinup` /
`session-wrap`, `project-distill` moved in as `session-distill` per D1,
`session-end` orchestrator per D3, single collapsed Stop nudge per D4).
Phase 4's in-repo deliverables landed 2026-06-28 (`feedback-session` emits the
shared `session-feedback`/`positive-feedback` labels; the `friction-learner`
slow loop reads + corroborates/escalates open `session-feedback` issues and
cross-links them). Remaining: the `gitops/labels.tf` label declaration (Phase 4,
user-owned/external) and the dotfiles-side cleanup (remove chezmoi copies of the
user-level skills/hooks, add the user's vault-specific `session-plugin.local.md`
to the chezmoi source).
Tracking task: taskwarrior `project:claude-plugins.session-plugin` (172)
Epic: [#1504](https://github.com/laurigates/claude-plugins/issues/1504) · Phase 1 remediation: [#1503](https://github.com/laurigates/claude-plugins/issues/1503)

This note is the durable plan produced in the 2026-06-04 design session. It
answers three questions raised that session:

1. How to tie the three end-of-session skills (`session-wrap`,
   `project-distill`, `feedback-session`) together.
2. How that fast-loop capture relates to the weekly `friction-learner` routine.
3. Whether `project-plugin` is up to current standards, and what its skills'
   relationship to `blueprint-plugin` actually is.

## Architecture: two speeds, one tracker

A **fast loop** (per-session, in-context, human-paced) and a **slow loop**
(weekly, autonomous, statistical) that are *complementary, not duplicates* —
each is structurally blind to what the other sees:

- `friction-learner` reads *error-shaped events* from parsed transcripts. It
  cannot see a subtly-wrong skill suggestion the agent quietly corrected (no
  hook block, no tool error), and it has **no positive channel** (friction is
  negative by definition).
- `feedback-session` reads the *live conversation in context*. It catches
  one-offs and positives, but cannot tell a one-off from a systemic pattern.

They meet at the `claude-plugins` issue tracker. The slow loop *reads* open
fast-loop issues as pre-registered signal and escalates a one-off that has
since become recurring.

See `docs/diagrams/two-speed-feedback.d2` (+ `.svg`) for the diagram.

| | Fast loop | Slow loop |
|---|---|---|
| Skills | `session-spinup`, `/session:end` → (`session-wrap`, `project-distill`, `feedback-session`) | `friction-learner` routine |
| Input | one live session, in context | all sessions' transcripts, last 7 days |
| Method | qualitative judgment | quantitative clustering + trend |
| Threshold | none (single notable interaction qualifies) | `--min-count 3` |
| Polarity | bug + enhancement + **positive** | negative only |
| Cadence | manual / nudged at wind-down | weekly, autonomous, idempotent |

## Confirmed decisions (D1–D5)

| # | Decision | Choice |
|---|----------|--------|
| D1 | Move `project-distill` into `session-plugin`? | **Yes** — it is session-meta, not project-scaffolding; moving it also de-vagues `project-plugin`. |
| D2 | Move `feedback-session` too? | **No** — keep it in `feedback-plugin` next to `friction-learner` (the feedback pair). Orchestrator references it by `/feedback:session` name. |
| D3 | Orchestrator behavior | **Decision pass → preview which skills qualify (with reasons) → single confirm → sequence.** Non-qualifying skills are silently skipped (the signal-filter ethic). Not fully auto: filing issues / writing a journal is not `git restore`-able. |
| D4 | Competing Stop nudges | **Collapse** `session-wrap-nudge` + `project-distill-nudge` into one nudge that offers `/session:end`. |
| D5 | Shared label taxonomy | `session-feedback` (fast) + `friction-finding` (slow) co-exist; positive stays `positive-feedback`. **Gated**: `claude-plugins` labels are gitops-managed (`gitops/labels.tf`) — add via a gitops PR the user merges, never `gh label create`. |

## Phases

### Phase 0 — Lock architecture + design note *(this file; done)*
Resolve D1–D5, capture the model, render the diagram. Gates everything else.

### Phase 1 — Audit `project-plugin` (read-only)
Reuse `scripts/plugin-compliance-check.sh`, `scripts/audit-skill-descriptions.py`,
`health-plugin:health-agentic-audit`. Confirmed findings to fix:
- README documents **3 phantom skills** (`/project:new`, `/project:modernize`,
  `/project:modernize-exp`) that do not exist, plus a dead
  `/blueprint:generate-commands` cross-reference.
- `project-continue` is **blueprint-coupled** (reads `docs/blueprint/feature-tracker.json`)
  and references a suspicious `.claude/blueprints/prds/` path (vs blueprint's
  `docs/blueprint/`). Verify and fix the path.
- Broad `Bash` in `project-continue` / `project-test-loop`; `Bash(ls/find/wc *)`
  in `project-discovery` (violates `bash-tool-replacements`).
- Stale `reviewed:` dates.
- **Deliverable: the project↔blueprint when-to-use matrix** — which project
  skills are blueprint-independent (`init`, `discovery`, `test-loop`,
  `skill-scripts`) vs blueprint-coupled (`continue` ↔ `blueprint-execute`).

### Phase 2 — Generalize + promote `session-spinup` / `session-wrap` → `session-plugin` (generalize the journaling backend)
- Extract vault-specific journaling config (vault path `~/Documents/YourVault/Journal/notes/`,
  `## Log`/`## Todo` section targets, `<scope>.*` project-naming map, scope-detection
  heuristics) into per-user config via `agent-patterns-plugin:plugin-settings`
  (`.claude/session-plugin.local.md`).
- Generalize the second destination to an optional **journal/notes** integration
  (Obsidian = one backend). taskwarrior + GitHub-issues destinations stay generic.
- Move reference material to `REFERENCE.md` (both skills are 275/277 lines — WARN band).
- Scaffold the plugin per CLAUDE.md Plugin Lifecycle (plugin.json, README,
  marketplace.json, release-please-config.json, .release-please-manifest.json,
  docs/PLUGIN-MAP.md).
- Migrate the two nudge hooks into the plugin.
- **Write the user's actual vault config to `.local.md` so nothing breaks for them.**
- Remove the chezmoi `exact_dot_claude/skills/{session-wrap,session-spinup}` copies.
- Add regression checks (`.claude/rules/regression-testing.md`).

### Phase 3 — Build `/session:end` orchestrator
- New skill in `session-plugin`; D3 behavior.
- One Stop-hook nudge (D4).
- Sharpen the `project-distill` ↔ `feedback-session` seam: "discovered a better
  flag than the skill suggests" → `feedback-session` enhancement issue; "a
  reusable project pattern/workflow" → `project-distill` rule/recipe.

### Phase 4 — Wire fast ↔ slow integration
- Shared labels via `gitops/labels.tf` (user merges the gitops PR). **Pending — user-owned/external.**
- Update `feedback-session` to emit the shared labels. **Done** — emits
  `session-feedback` / `positive-feedback` with a graceful `gh label create`
  fallback when labels are IaC-managed.
- Update the `friction-learner` routine contract to read open `session-feedback`
  issues as pre-registered signal and corroborate/escalate, cross-linking the
  issue numbers in the findings file. **Done** — `friction-learner` Step 0
  fetches open `session-feedback` issues; Step 3 corroborates/escalates them
  against the quantitative clusters; Step 5 cross-links the issue numbers in the
  PR body / findings file.

### Phase 5 — Verify + document
- Run `plugin-compliance-check.sh`, `audit-skill-descriptions.py`, regression scripts.
- Update CLAUDE.md + `docs/PLUGIN-MAP.md`.
- Smoke-test `/session:end` end-to-end.

## Dependencies
Phase 0 first. Phase 1 and Phase 2 then run largely in parallel (coupled only by
D1). Phase 3 needs Phase 2. Phase 4 is independent after D5 (parallel with 2/3).
Phase 5 last.

## Notes
- `session-spinup` stays the start-of-session read (the bookend); it is **not**
  part of the `/session:end` wrap chain.
- Cross-plugin references use `/plugin:skill` names (the install-independent form),
  never shared `REFERENCE.md` files across plugins.
