# Frozen Scoring Rubric — Claude Code Plugin Marketplace Quality Benchmark

**Status: FROZEN.** Every scored anchor traces to a published, non-house source
(see `## Source list`). House-only conventions are quarantined in
`## House-only criteria excluded from scoring` and MUST NOT influence any score.

## How to score

- Each dimension is scored **1–5**. Anchors are defined for **1, 3, 5**; **2 and 4
  are interpolations** (2 = between the 1 and 3 anchors; 4 = between 3 and 5).
- **Anchor 3 = competent, typical published-guidance-compliant work.**
  **Anchor 5 = exceptional, evidence-heavy.** **Anchor 1 = clearly deficient.**
- **Symmetry:** the same defect scores the same regardless of which side exhibits
  it. Anchors do not presuppose either side's architecture. Where a dimension
  depends on what risks/needs an artifact actually has (B4 scripts, A2 CI surface,
  A4 supply chain), judge **relative to the risks that artifact actually has** — an
  artifact with no exposure to a risk is not penalized for lacking a control for it.
- **Tier B** (skill/plugin-authoring) is judged **blind, per pair** on artifact
  content alone. **Tier A** (marketplace/infrastructure) is judged **open-book, per
  repo**.

---

## Tier B — Plugin-authoring quality (judged blind, per pair)

### B1 — Trigger & discoverability

Whether an artifact's frontmatter/description lets Claude (and the user) know
*when* to invoke it: a description that states what the thing does **and** the
concrete conditions under which to use it, written in the third person, with a
name distinct enough not to overlap sibling artifacts. Descriptions are the
primary triggering mechanism and are truncated from the end in the skill listing,
so the key use case belongs first.

- **1 — Deficient.** Description is tool-centric or vague ("Provides guidance for
  X", "Do the thing"), states no trigger conditions, is written in the second
  person, or is absent; or the name collides/overlaps with a sibling so Claude
  cannot tell which to load.
  Sources: skills (description "what the skill does and when to use it… Claude
  uses this to decide"); best-practices (name/description drive triggering);
  skill-development (bad-description examples).
- **3 — Competent.** Description states what the artifact does **and** concrete
  conditions or user contexts for invoking it, in the third person; the name is
  distinct and non-overlapping.
  Sources: best-practices; skill-development (third-person + specific trigger
  phrases); skills (frontmatter `description`).
- **5 — Exceptional.** As 3, plus trigger conditions cover realistic phrasings and
  near-miss contexts, the key use case is front-loaded so it survives description
  truncation, and the artifact is explicitly disambiguated from sibling artifacts
  that could otherwise both match.
  Sources: skills ("Put the key use case first"; 1,536-char end-truncation);
  skill-creator (should-trigger / should-not-trigger coverage, near-misses).

### B2 — Instruction quality

Whether a zero-context agent could execute the instructions correctly: concrete
ordered steps, correct and runnable commands, unambiguous phrasing, output format
stated where it matters, and degrees of freedom constrained appropriately (neither
under-specified nor smothered in rigid MUST/NEVER directives). The skill is written
for another Claude instance, so it should carry the non-obvious procedural detail.

- **1 — Deficient.** Instructions are vague ("process the document appropriately"),
  skip required steps, or give commands that are wrong or won't run; a fresh agent
  would have to guess to proceed.
  Sources: skill-creator (vague instruction → inconsistent behavior in
  analysis.json example); skill-development (imperative, concrete steps).
- **3 — Competent.** Concrete, ordered, imperative-form steps; commands are correct
  and runnable; output format is specified where relevant; a zero-context agent
  could follow them to a correct result.
  Sources: skill-creator (imperative form, define output formats, examples
  pattern); skill-development (Step 4, imperative/infinitive).
- **5 — Exceptional.** As 3, plus the reasoning ("the why") is given so the agent
  generalizes beyond the literal steps, freedom is constrained just enough (not
  over-rigid, not under-specified), and input→output examples remove ambiguity.
  Sources: skill-creator ("Explain the why"; theory-of-mind; ALWAYS/NEVER is a
  "yellow flag"); skill-development.

### B3 — Context economy / progressive disclosure

Whether the always-loaded surface (SKILL.md body) is lean and detail is pushed to
supporting files/scripts loaded only on demand, rather than bloat that taxes the
context window on every load. Every line of the body is a recurring token cost.

- **1 — Deficient.** The body is bloated — large reference material, exhaustive
  options, or rarely-used detail inlined so it is always loaded when the artifact
  triggers.
  Sources: skill-development (Mistake 2, single 8,000-word file); skills ("Keep the
  body concise… every line is a recurring token cost").
- **3 — Competent.** The body is reasonably lean and focused on the core procedure;
  longer or infrequently-needed detail lives in supporting files that the body
  references by name.
  Sources: skills ("Keep SKILL.md under 500 lines. Move detailed reference material
  to separate files"); best-practices (progressive disclosure); skill-development.
- **5 — Exceptional.** Clear multi-level progressive disclosure — concise body,
  on-demand reference files, and executable scripts that run without being read
  into context — with mutually-exclusive or rarely-combined paths split so unused
  detail costs nothing.
  Sources: best-practices (three-level disclosure; conditional bundling to reduce
  token usage); skill-development; skill-creator (add a hierarchy layer near the
  limit).

### B4 — Determinism offload

Whether mechanical, repeatable, or deterministic work (parsing, counting, fixed
transforms, validation) is delegated to bundled scripts or dedicated tools rather
than left as prose the model re-derives each run — and whether those scripts are
robust. Judge relative to whether such work actually exists: a pure-reference
artifact with no mechanical work is not penalized for having no scripts.

- **1 — Deficient.** Clearly mechanical/repeatable work is left as prose the model
  re-derives every invocation, with no script or tool where one would plainly help.
  Sources: best-practices ("sorting a list via token generation is far more
  expensive than running a sorting algorithm"); skill-creator (bundle a repeatedly
  rewritten script).
- **3 — Competent.** Deterministic/repetitive operations are delegated to bundled
  scripts or dedicated tools, and the artifact points to them clearly.
  Sources: skill-development (scripts/ for deterministic reliability / repeatedly
  rewritten code); best-practices (code as executable tools).
- **5 — Exceptional.** As 3, plus scripts are robust (handle their inputs/errors,
  are documented, run standalone) and the artifact makes explicit whether Claude
  should *run* a script or *read* it as reference.
  Sources: best-practices ("clear whether Claude should run scripts directly or
  read them into context"); skill-development (scripts executable and documented).

### B5 — Safety & permissions

Whether tool allowances are least-privilege, shell is injection-safe, defaults are
non-destructive, destructive actions are gated, and the artifact's effect matches
its stated intent. `allowed-tools` grants standing permission, so a skill can grant
itself broad access; the hard enforcement of allow/deny belongs to the permission
system, and shell that interpolates untrusted input must be injection-safe.

- **1 — Deficient.** Over-broad or unnecessary tool access (e.g. blanket
  `Bash(*)` where narrow rules would do); shell built from unquoted/unsanitized
  interpolation (injection-prone); destructive or irreversible actions run without
  any gate; or content whose effect exceeds or contradicts its stated intent.
  Sources: skills ("a skill can grant itself broad tool access"); hooks
  (shell-form requires careful quoting; injection risk); skill-creator (Principle
  of Lack of Surprise — no malware/exfiltration; intent must match).
- **3 — Competent.** Tool allowances are scoped to what the artifact needs; shell
  is injection-safe (exec-form or quoted paths; safe `jq` parsing of inputs); no
  dangerous defaults; behavior matches stated intent.
  Sources: skills (`allowed-tools` scoping; deny rules); hooks (exec form vs shell
  form; `jq` safe extraction); skill-creator.
- **5 — Exceptional.** As 3, plus destructive/irreversible actions are explicitly
  gated (confirmation, manual-only invocation, or a hard permission/hook backstop),
  and least-privilege is applied consistently across every bundled component.
  Sources: hooks (PreToolUse deny / permission system for hard enforcement; exit 2
  to block); skills (deny rules; `disable-model-invocation` for side-effecting
  workflows).

### B6 — Robustness & maintainability

Whether references resolve, content is internally consistent (no contradictions or
duplication across files, no stale material), and the workflow has error/verification
paths where it needs them. Information should live in one place, not two.

- **1 — Deficient.** Broken or missing references, contradictory or duplicated
  content across files, visibly stale material, TODO/debug leftovers, or no
  error/verification path where the workflow plainly needs one.
  Sources: skill-development (referenced files must exist; "information should live
  in either SKILL.md or references, not both"); marketplace-considerations (no
  TODO/debug code; comprehensive error handling).
- **3 — Competent.** References resolve and are consistent; content is internally
  coherent with no obvious staleness; the workflow includes basic error handling or
  a verification step.
  Sources: skill-development (validation checklist; no duplication);
  marketplace-considerations (anticipate mistakes; helpful diagnostics).
- **5 — Exceptional.** As 3, plus explicit failure paths and a verification/
  self-check step, single-source-of-truth content, and evidence the artifact is
  maintained as a coherent whole (graceful degradation, idempotency where relevant).
  Sources: skill-development (no duplicated information; validate); best-practices
  (iterate; capture successful approaches and common mistakes);
  marketplace-considerations (graceful degradation, idempotency, diagnostics).

---

## Tier A — Marketplace/infrastructure quality (judged open-book, per repo)

### A1 — Manifest schema & integrity

Whether `marketplace.json` and each `plugin.json` carry required fields with valid
values, names are kebab-case, sources resolve, and there are no duplicate names or
orphaned entries. `marketplace.json` requires `name`, `owner`, and `plugins`; each
plugin entry requires `name` and `source`; `plugin.json` requires a kebab-case
`name` and uses semver for `version`; source paths must be relative without `..`.

- **1 — Deficient.** Manifests miss required fields, use invalid values (non-kebab
  name, non-semver version, `..` in a source path), contain duplicate plugin names,
  or list entries whose plugin/source does not exist (orphans).
  Sources: plugins-reference / manifest-reference (name regex; semver; relative
  `./` paths, no `..`); plugin-marketplaces (required fields; duplicate-name error;
  source path-traversal check).
- **3 — Competent.** Both manifests carry all required fields with valid values;
  names are kebab-case; every source resolves; no duplicates or orphans; the repo
  passes `claude plugin validate`.
  Sources: plugin-marketplaces (required fields; `claude plugin validate`);
  manifest-reference.
- **5 — Exceptional.** As 3, plus complete recommended metadata (description,
  version, author, license, keywords/category, repository/homepage) that is
  consistent between each marketplace entry and its `plugin.json`; a `$schema` for
  editor validation; and rename/removal history maintained so identifier changes do
  not break existing installs.
  Sources: manifest-reference (recommended metadata block); plugin-marketplaces
  (`$schema`; entry-vs-`plugin.json` version-mismatch warning; `renames`).

### A2 — Validation CI depth

Whether automated validation gates the repo, and how deep it goes — syntax/schema
only, versus semantic gates plus a regression culture. Judge relative to the repo's
surface: a large multi-plugin marketplace has more that can break than a single-
plugin repo, and the anchor is "checks scale to what could actually break."

- **1 — Deficient.** No automated validation; malformed manifests, duplicate names,
  path traversal, or unparseable frontmatter can merge undetected.
  Sources: plugin-marketplaces (the validator exists and reports these classes —
  its absence is the deficiency).
- **3 — Competent.** Automated syntax/schema validation runs in CI (equivalent to
  `claude plugin validate`), catching malformed manifests, duplicate names, source
  path traversal, and unparseable skill/agent/command frontmatter.
  Sources: plugin-marketplaces (validator scope: schema errors, duplicate names,
  path traversal, per-entry `plugin.json`, YAML frontmatter, `hooks.json`).
- **5 — Exceptional.** As 3, plus semantic gates beyond syntax (schema validation
  of evals/behavior, hook-schema and hook-behavior tests, or content/quality
  checks) and a regression culture where a fixed defect gains a guarding check.
  Sources: skill-creator (`quick_validate.py`, `run_eval` harness); plugin-dev
  (`validate-hook-schema.sh`, `test-hook.sh`, `validate-settings.sh`).

### A3 — Versioning & release discipline

Whether versions are valid semver (or a deliberate commit-SHA scheme), bumped on
release, declared in a single authoritative place, and supported by changelog/
release automation. Claude Code resolves a version from `plugin.json`, then the
marketplace entry, then the git SHA; a stale pinned version silently starves users
of updates.

- **1 — Deficient.** No versioning strategy — versions absent where pinning is
  intended, or pinned versions that never bump so users never receive updates; no
  changelog.
  Sources: plugin-marketplaces (Warning: a stale pinned `version` "does nothing for
  existing users").
- **3 — Competent.** Consistent, valid semver (or deliberate commit-SHA
  versioning), bumped on release, with the version declared in one authoritative
  place (not conflictingly in both `plugin.json` and the marketplace entry).
  Sources: manifest-reference (semver MAJOR/MINOR/PATCH); plugin-marketplaces
  (version resolution order; "avoid setting version in both").
- **5 — Exceptional.** As 3, plus automated release/changelog generation and a
  coherent, documented version-resolution or release-channel strategy applied in
  practice.
  Sources: plugin-marketplaces (release channels; version resolution);
  manifest-reference (maintain a changelog; bump version on changes).

### A4 — Supply-chain & distribution safety

Whether the supply-chain risks the distribution model **actually has** are
controlled: external sources pinned against mutable refs, provenance/integrity,
license correctness, scope guards, and plugin references that stay inside the
plugin. A self-contained repo with no external refs has no pinning risk and is
judged on license and path-safety alone — it is not penalized for lacking pins it
has no use for.

- **1 — Deficient.** The model's real risks are uncontrolled — external plugin or
  dependency sources tracked from mutable refs with no pin or provenance, a missing
  or incorrect license, or scripts/configs referencing paths outside the plugin
  (e.g. `..`) instead of `${CLAUDE_PLUGIN_ROOT}`/relative paths.
  Sources: plugin-marketplaces (SHA pinning; relative-path rule, no `..`);
  manifest-reference (SPDX license); plugin-marketplaces (`${CLAUDE_PLUGIN_ROOT}`).
- **3 — Competent.** The risks the model actually has are controlled — external
  sources pinned to a tag/SHA where mutability matters, license declared, and all
  plugin references resolve within the plugin via `${CLAUDE_PLUGIN_ROOT}` or
  relative paths with no `..`.
  Sources: plugin-marketplaces (`ref`/`sha` pinning; relative paths resolve within
  marketplace root); manifest-reference (license SPDX).
- **5 — Exceptional.** As 3, with provenance/integrity strengthened to the model's
  risk profile: exact 40-character SHA pins (or npm version/registry pins),
  liveness/reachability handled, scope or allowlist guards where the repo
  distributes to others, and licenses validated across bundled components.
  Sources: plugin-marketplaces (full-SHA pin; npm `version`/`registry`;
  `strictKnownMarketplaces`; read-only seed); manifest-reference (license).

### A5 — Docs & navigability

Whether the marketplace and each plugin carry accurate descriptions and docs, the
catalog is discoverable, and its claims (plugin list, counts) match what is on
disk. A missing top-level description is a documented warning; per-plugin READMEs
and metadata aid discovery.

- **1 — Deficient.** Sparse or misleading docs — no marketplace/plugin
  descriptions, no README, or catalog claims (counts, plugin lists) that do not
  match the repo contents.
  Sources: plugin-marketplaces ("No marketplace description provided" warning);
  manifest-reference (description; README; "keep description current").
- **3 — Competent.** The marketplace and each plugin carry accurate descriptions
  and a README; the catalog is discoverable and its claims match disk.
  Sources: manifest-reference (description, README, keywords); plugin-marketplaces
  (top-level `description`).
- **5 — Exceptional.** As 3, plus per-plugin (and per-skill) documentation, a
  navigable catalog/index using keywords/categories and homepage/repository links,
  and counts/claims kept in sync with source as a single source of truth.
  Sources: manifest-reference (homepage, repository, keywords, changelog);
  plugin-marketplaces (`category`, `tags`).

### A6 — Governance & eval infrastructure

Whether there is an ownership/contribution signal (license, author, repository,
contribution guidance) and whether skill quality is *measured* rather than asserted
— the baseline-comparison eval loop, trigger-accuracy tuning, and blind A/B being
the published mechanisms.

- **1 — Deficient.** No license, ownership, or contribution signal, and no
  quality-evaluation tooling; quality rests entirely on ad-hoc judgment.
  Sources: manifest-reference (license/author/repository for attribution &
  contribution); skills ("Evaluate and iterate on a skill" — its absence is the
  gap).
- **3 — Competent.** An ownership/contribution signal exists (license, author,
  repository, or basic contribution guidance) and some quality evaluation is
  practiced (e.g. a baseline-comparison eval loop or equivalent).
  Sources: skills (baseline comparison: with-skill vs disabled); skill-creator;
  manifest-reference.
- **5 — Exceptional.** As 3, plus systematic evaluation infrastructure — measurable
  skill effectiveness (baseline-vs-with-skill benchmarking, trigger-accuracy
  tuning, blind A/B), a documented governance/contribution process, and evidence it
  is actually used.
  Sources: skill-creator (benchmark mode with mean±stddev deltas; description
  optimization loop; blind comparison); skills (eval workflow; `/doctor` for
  listing health).

---

## House-only criteria excluded from scoring

These appear in the house rules (`skill-quality.md`, `skill-argument-handling.md`)
but are **not independently supported** by the allowed sources, so they carry **no
score**. The neutral, published-supported version (where one exists) is what the
anchors above use instead.

- **Specific character-count size thresholds** (≤10,000 chars OK / 26,000-char hard
  ceiling) — house `skill-quality.md`. Published guidance supports *leanness* ("under
  500 lines", "<5k words") but not these literal char gates. B3 scores leanness/
  progressive disclosure, not a char count.
- **Mandatory "When to Use This Skill" decision table** placed immediately after the
  title, with a "Use X instead when…" column — house `skill-quality.md`. Published
  guidance puts "when to use" in the `description`, not a required body section.
- **Mandatory "Agentic Optimizations" table** near the end — house
  `skill-quality.md`. No published requirement for this section.
- **Literal "Use when…" clause** in the description — house `skill-quality.md`. The
  neutral, published version is "description states concrete trigger conditions"
  (B1); the exact phrase is not required.
- **Specific description-length band** (≤150-char target, >300-char ERROR) — house
  `skill-quality.md`. The *listing budget and 1,536-char truncation* are published
  and inform B1's front-loading anchor, but the 150/300 numbers are house thresholds.
- **`created` / `modified` / `reviewed` date frontmatter fields** — house
  `skill-quality.md`. Not in the published frontmatter schema; not scored.
- **Model-selection policy** (`opus`/`sonnet` extremes-only; `haiku` banned) — house
  `skill-quality.md`. The `model` field is published, but this policy is a house
  convention.
- **`allowed-tools` as a *required* frontmatter field** — house `skill-quality.md`.
  Published schema marks only `description` as recommended and `name`/`allowed-tools`
  as optional. B5 scores whether tool allowances are *least-privilege when present*,
  not their mandatory presence.
- **Literal `REFERENCE.md` filename** (uppercase, specific name) — house
  `skill-quality.md`. Published guidance uses a `references/` directory with any
  filename; B3 scores on-demand supporting files, not a filename.
- **Positive-only writing style** ("describe what to do, not what to avoid") as a
  scored requirement — house `skill-quality.md`. Related to skill-creator's
  "explain the why / avoid rigid MUSTs" (which B2 uses) but the strict positive-
  framing rule is house-specific.
- **The 9-axis argument-handling rubric and the haiku-vs-opus cold-read sweep
  methodology** — house `skill-argument-handling.md`. This is house *evaluation
  tooling*, not a scored artifact property. The underlying published concepts —
  `argument-hint` indicates expected arguments, `$ARGUMENTS`/`$N` substitution — are
  folded into B2 (instruction quality) where relevant, without the house rubric.
- **Repo-specific commit/PR conventions** (conventional-commit scopes, plugin-name
  scoping, release-please dogfooding) — house `CLAUDE.md`. Out of scope for
  artifact-content scoring.

---

## Source list

Published Anthropic documentation (consulted):

- Extend Claude with skills — https://code.claude.com/docs/en/skills
- Best Practices for Writing Effective Agent Skills (Anthropic engineering / agent
  skills best-practices) — https://www.anthropic.com/engineering/equipping-agents-for-the-real-world-with-agent-skills
  and https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices
- Create and distribute a plugin marketplace — https://code.claude.com/docs/en/plugin-marketplaces
- Plugins reference (plugin manifest schema, components) — https://code.claude.com/docs/en/plugins-reference
- Safety & permissions in hooks — https://code.claude.com/docs/en/hooks

Official marketplace repo authoring references (local, read in full):

- `official/plugins/skill-creator/skills/skill-creator/SKILL.md` (skill-creator)
- `official/plugins/skill-creator/skills/skill-creator/references/schemas.md`
  (eval / grading / benchmark / comparison JSON schemas)
- `official/plugins/plugin-dev/skills/skill-development/SKILL.md`
- `official/plugins/plugin-dev/skills/plugin-structure/references/manifest-reference.md`
- `official/plugins/plugin-dev/skills/command-development/references/marketplace-considerations.md`
- Referenced as evidence of semantic validation tooling: `skill-creator/.../scripts/`
  (`quick_validate.py`, `run_eval.py`, `aggregate_benchmark.py`) and
  `plugin-dev/skills/hook-development/scripts/` (`validate-hook-schema.sh`,
  `test-hook.sh`), `plugin-settings/scripts/validate-settings.sh`

Diff-only inputs (read to build the exclusion list; **not** anchor sources):

- `laurigates/claude-plugins/.claude/rules/skill-quality.md`
- `laurigates/claude-plugins/.claude/rules/skill-argument-handling.md`
