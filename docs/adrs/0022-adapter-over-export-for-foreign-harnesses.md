# ADR-0022: Adapter over Export — Runtime Skill Discovery for Foreign Harnesses

---
date: 2026-07-17
created: 2026-07-17
modified: 2026-07-17
status: Accepted
deciders: claude-plugins team
domain: architecture
relates-to:
  - ADR-0001  # plugin-based architecture (the canonical source the adapters index)
  - ADR-0004  # marketplace registry model (marketplace.json is the adapter's discovery root)
  - ADR-0021  # OKF substrate convergence (the Agent Skills convergence this ADR builds on)
---

## Context

This marketplace's skills run on two foreign harnesses today, each through a
hand-maintained **export pipeline**:

| Harness | Pipeline | Curation artifact |
|---------|----------|-------------------|
| pi (pi.dev) | `install-pi.sh` copies curated skills into pi's scopes | `pi/tiers.yaml` (tier per plugin, `skills:` cherry-picks, `exclude` list), enforced by `check-pi-tiers.sh` in pre-commit + CI |
| OpenCode | rulesync export with normalization scripts (`rewrite-skill-name-to-dir.py`, `normalize-skill-allowed-tools.py`) | the export config itself |

Both exist because neither harness budgets its skill listing the way Claude
Code does (`skillListingBudgetFraction`). Measured on pi 0.80.6: every
installed skill costs **~111 tokens/turn** of standing context, dead linear
and uncapped — all ~400 marketplace skills would cost ~45K tokens/turn and
hang the turn outright on a 128K local context. OpenCode's
`<available_skills>` listing (embedded in its `skill` tool description) has
the same linear shape. The tier manifest was the interim answer: curate a
subset small enough to afford.

Three developments changed the calculus:

1. **Both harnesses converged on the Agent Skills standard.** pi loads Claude
   Code `SKILL.md` unmodified; OpenCode now natively discovers SKILL.md —
   including from `.claude/skills/` paths — making most of the rulesync
   conversion obsolete.
2. **Both harnesses grew extension APIs sufficient for runtime discovery.**
   Verified against upstream docs/types: pi extensions have
   `pi.registerTool()`, `before_agent_start` (system-prompt modification +
   message injection, with `systemPromptOptions.skills` exposed), and
   extension-contributed skill paths. OpenCode plugins have custom tools
   (`tool: {}`), `tools: { skill: false }` / `permission.skill` /
   `tool.definition` to suppress or rewrite the native listing, and
   `experimental.chat.system.transform` / `experimental.chat.messages.transform`
   for per-turn injection.
3. **The curation manifests drift.** `pi/tiers.yaml` restates facts about
   skills (which harness they make sense on, which are core) in a parallel
   artifact that must be hand-synced with the marketplace — the
   documentation-authoring anti-pattern applied to tooling. Two overlapping
   solutions (manifest + any future search mechanism) would be worse than
   either alone.

The goal restated: the Claude Code experience on foreign harnesses — **every
skill at arm's reach, without filling the context**. Claude Code achieves
this with three mechanisms: a bounded always-on listing, on-demand bodies,
and pull-based discovery for the long tail (deferred tools + ToolSearch).
The foreign harnesses have the middle one natively; the adapter supplies the
other two.

## Decision

**Foreign harnesses get runtime adapters, not exports.** claude-plugins
stays Claude-Code-native; each foreign harness gets a thin binding over one
shared discovery core, and the export pipelines are superseded.

1. **One harness-agnostic core** (`adapters/core/`, plain TS, no harness
   imports): scans the marketplace checkout (`marketplace.json` +
   `*/skills/*/SKILL.md`), builds an **embedding index** over
   name+description (endpoint configurable, default local ollama
   `/api/embed`; cached by content hash) with a **BM25/keyword fallback**
   and hybrid rank fusion, and exposes
   `search(query, k, filters) → [{name, description, path, score}]`.
   Skills are **not copied**: search returns paths, and delivery is the
   model `read`ing the SKILL.md — both harnesses' native progressive
   disclosure. (#2089)

2. **Per-harness bindings**:
   - **pi** (`adapters/pi/`, stable hooks — leads on full hybrid): a
     `search_skills` tool (pull) plus per-turn top-k injection via
     `before_agent_start` (push), suppressing the native uncapped listing.
     Push exists because a small local quant won't search for a skill it
     doesn't know exists — ranking against the user message moves the
     triggering burden into deterministic harness code. (#2090)
   - **OpenCode** (`adapters/opencode/`, pull-first): `search_skills` via
     the stable plugin tool surface, native listing disabled via
     `tools: { skill: false }`; push added behind a version check because
     the relevant hooks are `experimental.*`-prefixed. (#2091)

3. **Curation moves out of manifests**:
   - The *exclude* judgment (Claude-Code-authoring meta is noise on any
     other harness) is a property of the skill, so it moves into the
     skill's own **`compatibility` frontmatter** — an Agent Skills spec
     field both harnesses already recognize. One sweep marks the ~exclude
     set. (#2092)
   - Per-project scoping (the old domain tier) is subsumed by relevance
     ranking plus per-project adapter config (`.pi/settings.json` /
     `opencode.json`) — the same interface shape as Claude Code's
     `enabledPlugins`. An optional `pins:` list covers skills that must
     always be visible; there is no always-on "general tier" to maintain.

4. **The export pipelines are superseded, gated on evidence.** Per the
   tool-migration-cutover rule, nothing is deleted until the adapter is
   *observed operational*: the eval harness in #2089 runs the same task set
   on the same local quant, baseline (tier-install / rulesync export)
   vs adapter, measuring **correct-skill-invocation rate** and **standing
   tokens/turn**. Adapter meets or beats invocation rate at lower standing
   cost → the corresponding pipeline is removed in one complete sweep
   (#2093 for the pi tier system, #2094 for rulesync).

## Consequences

### Positive

- **One source of truth.** The marketplace checkout is the only artifact;
  adapters index it live. No manifest to hand-sync, no export drift, no
  per-ecosystem catering in skill authoring.
- **All skills reachable at bounded cost.** Standing per-turn cost becomes
  ~top-k plus the tool description (~1–2K tokens) instead of linear in
  installed skills (~10.4K for the 94-skill general tier; ~45K for all).
- **The interface claim is tested, not asserted.** Two bindings over one
  core is what makes "adapter over export" real; a third harness is a new
  thin binding, not a new pipeline.
- **Deletions on gate-pass**: `pi/tiers.yaml`, `install-pi.sh`,
  `check-pi-tiers.sh` + its pre-commit/CI wiring, the tier justfile
  recipes, the rulesync pipeline and its normalization scripts, and the
  bulk of both export docs.

### Negative / risks

- **An embedding endpoint becomes a soft dependency.** Mitigated by the
  BM25 fallback (search never hard-fails) and by the target audience
  already running a local model server.
- **OpenCode push rides experimental hooks.** They may break across
  releases; the binding ships pull-first and degrades gracefully. The
  cutover gate (#2094) is passable on pull alone.
- **Ranking misses are the new failure mode.** Curation failed closed
  (skill not installed → invisible); retrieval fails open but fuzzily
  (skill ranked low → not surfaced). The eval gate measures exactly this;
  hybrid BM25+embedding fusion and the push channel are the mitigations.
- **Weak-model initiative remains the hard part.** Pure pull demonstrably
  under-triggers on small quants; the push channel is load-bearing, not
  optional, on pi.

### Neutral

- OpenCode enforces `name` == parent directory (pi doesn't). Bypassing the
  native `skill` tool sidesteps the old `rewrite-skill-name-to-dir`
  normalization entirely; it only resurfaces if a pinned set uses native
  discovery.
- Claude Code ignores `compatibility` frontmatter; the sweep is inert on
  the home harness.

## Alternatives considered

- **Keep the tier system alongside a search tool.** Rejected: two
  overlapping curation mechanisms with different truths — the drift this
  ADR exists to remove.
- **Pure pull (search tool only).** Rejected as insufficient for the
  primary use case: small local quants don't search for skills they don't
  know exist; the original fidelity criterion (does the model *invoke* the
  right skill?) is exactly what pure pull endangers.
- **Pure push (ranked top-k injection only).** Rejected: no recourse when
  ranking misses on vague intents; the explicit search tool is cheap.
- **A separate adapter repo.** Rejected: the marketplace is the data
  source; a second repo re-creates the synchronization problem the adapter
  removes.
- **Static per-model listing caps (mimic `skillListingBudgetFraction`).**
  Rejected: still requires deciding *which* skills make the cap — that's
  the tier system again with a different constant.

## Implementation

| Issue | Scope | Gate |
|-------|-------|------|
| [#2089](https://github.com/laurigates/claude-plugins/issues/2089) | Discovery core + eval harness | — |
| [#2090](https://github.com/laurigates/claude-plugins/issues/2090) | pi binding (hybrid push+pull) | eval vs tier baseline |
| [#2091](https://github.com/laurigates/claude-plugins/issues/2091) | OpenCode binding (pull-first) | eval vs rulesync baseline |
| [#2092](https://github.com/laurigates/claude-plugins/issues/2092) | `compatibility` frontmatter sweep | precedes cutovers |
| [#2093](https://github.com/laurigates/claude-plugins/issues/2093) | Remove pi tier system | gate frozen + PASS (2026-07-22) |
| [#2094](https://github.com/laurigates/claude-plugins/issues/2094) | Retire rulesync export | gate frozen + PASS; OC token calibration still outstanding |

## Amendment (2026-07-22) — the cutover gate is tag-pinned and frozen

The gate threshold was measured on the shipping hybrid configuration and frozen
at `main_hit_at_k_min = 0.57` (measured 0.6727, margin 0.10) in
`adapters/eval/tasks.json`. #2093 and #2094 are now unblocked by a green gate;
the incumbents remain fully operational until those issues execute their own
cutover steps (`tool-migration-cutover`).

Two decisions in this ADR are superseded:

1. **The eval's stratification is pinned to the task set's own `stratum:`
   tags, not derived from `pi/tiers.yaml`.** A tiers-derived partition would
   have inverted the gate: #2093 deletes that file, at which point the in-tier
   metrics went `null` and the frozen threshold would have evaluated FAIL
   forever — failing precisely when it is meant to authorize the deletion.
   `partitionByStratum` therefore takes no `repoRoot` at all, so the coupling
   cannot return. The strata are consequently much larger and differently
   composed (main 27 → **55**, headroom 36 → **8**).

2. **The "in-tier baseline reachability is 1.0 by construction" reading is
   retired.** With membership no longer defining the stratum, `RETRIEVAL_MAIN`
   means exactly *hybrid retrieval quality on the main positives* and asserts
   nothing about any baseline. Reachability-delta reasoning against the pi
   listing no longer applies; `derivePiBaseline` survives only for the
   informational token figure and the calibration meta-test, both of which
   already degrade cleanly when `pi/tiers.yaml` disappears.

The procedure, its guards against a hybrid run that is silently BM25, and the
refuted gate constructions now live in `adapters/CUTOVER.md` — previously they
existed only in an ephemeral scratchpad while shipped source cited them as
"DESIGN §5.6".

## References

- `adapters/CUTOVER.md` — the cutover gate procedure, frozen threshold, and
  refuted constructions
- `docs/pi-export.md` — the measured listing-cost data and the original
  "skill-search extension" deferral this ADR supersedes
- `docs/opencode-export.md` — the rulesync pipeline being retired
- [pi extensions API](https://github.com/earendil-works/pi/blob/main/packages/coding-agent/docs/extensions.md),
  [pi skills](https://github.com/earendil-works/pi/blob/main/packages/coding-agent/docs/skills.md)
- [OpenCode plugins](https://opencode.ai/docs/plugins/),
  [OpenCode skills](https://opencode.ai/docs/skills/)
- [Agent Skills specification](https://agentskills.io/specification)
  (`compatibility` frontmatter)
