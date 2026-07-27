# Frozen Scoring Rubric — Context Engineering for Claude 5 Generation Models

**Status: FROZEN** (frozen 2026-07-26, before any judging).
Every scored anchor traces to Anthropic's post *"The new rules of context
engineering for Claude 5 generation models"* (see `## Source & provenance`).
House conventions are quarantined in `## House criteria excluded from scoring`
and MUST NOT influence any score — this benchmark **tests** those conventions,
so they cannot also be the yardstick.

## Scope caveat — read before scoring

The post's headline result (">80% of Claude Code's system prompt removed … with
no measurable loss on our coding evaluations") is about an **always-loaded
system prompt**. The units judged here have three different cost models, and
conflating them produces bad recommendations:

| Unit | When it costs tokens | Cutting it buys |
|---|---|---|
| `CLAUDE.md`, unscoped `.claude/rules/*.md` | **every turn of every session** | the most |
| `SKILL.md` body | only once the skill fires | a per-invocation saving |
| `REFERENCE.md`, `scripts/` | only when explicitly read/run | ~nothing (already deferred) |

Judges score each unit against the anchors **for what that unit is**. A 20,000-char
skill body is not the same defect as 20,000 chars of always-loaded rules.

## How to score

- Each dimension is scored **1–5**. Anchors are defined for **1, 3, 5**; **2 and
  4 are interpolations**.
- **Anchor 3 = competent work under the new rules.** **Anchor 5 = exemplary.**
  **Anchor 1 = clearly written for the old rules.**
- Score each unit **against the anchors first**, before any comparison to other
  units.
- **Every score of 1, 2, 4, or 5 requires a verbatim quote** from the unit,
  reproduced exactly so it can be mechanically string-matched against the file.
  A score you cannot quote for must be a 3.
- Judges do **not** see the Channel M scanner's numbers. Channel M (mechanical
  proxies) and Channel J (these judgments) are reported separately and never
  blended.
- Where a dimension does not apply to a unit (e.g. C2 for a unit with no
  arguments), record `"n/a"` rather than inventing a score.

---

## C1 — Judgment over rules

Whether the unit trusts a capable model's judgment or micromanages it. The
question is not "are there rules" but "does each constraint earn its tokens":
a constraint whose violation is a real bug (safety, irreversibility, an
automation contract) earns them; a constraint restating what the model would do
anyway does not.

- **1 — Written for the old rules.** Dense unconditional directives
  (MUST/NEVER/ALWAYS) over matters of style or defaults the model already
  handles; the unit reads as a fence around a model it does not trust.
  Source: the post's own before/after — **then** *"default to writing no
  comments. Never write multi-paragraph docstrings"*; **now** *"Write code that
  reads like the surrounding code: match its comment density"*.
- **3 — Competent.** Constraints are present but proportionate: the hard ones
  concern safety, irreversibility, or a contract, and softer guidance is framed
  as judgment ("match the surrounding code", "prefer X when Y") rather than
  prohibition.
  Source: *"Avoid making them overconstrained, except in highly important
  areas."*
- **5 — Exemplary.** Every remaining constraint is load-bearing and says **why**,
  so the model can generalise to cases the rule does not enumerate; style and
  defaults are delegated to judgment outright.
  Source: *"Avoid making them overconstrained, except in highly important
  areas."* + the comment-density rewrite as the model of delegated judgment.

## C2 — Interface design over examples

Whether the unit makes its interface self-describing — expressive parameter
names, enumerated alternatives, typed options — instead of teaching by
accumulated usage examples. Judge relative to whether the unit *has* an
interface; a pure narrative reference is `n/a`.

- **1 — Written for the old rules.** The interface is opaque (bare
  `<arg>`/free text with no stated alternatives) and understanding it requires
  reading a pile of usage examples.
  Source: the post's shift *examples → interface design*, whose worked case is
  defining task status as an enumeration (`pending`, `in_progress`,
  `completed`) rather than showing examples of it.
- **3 — Competent.** Parameters are named expressively and their alternatives
  are stated (enumerated flags, a parameters table, an `argument-hint`);
  examples illustrate rather than carry the definition.
- **5 — Exemplary.** The interface alone is sufficient — alternatives are
  enumerated at the point of declaration, invalid combinations are impossible or
  named, and the few examples that remain cover genuine ambiguity rather than
  restating the interface.

## C3 — Progressive disclosure

Whether detail is loaded when needed rather than up front, and whether long
material is **split across files** rather than deferred into one large sidecar.

- **1 — Written for the old rules.** One long file carrying everything —
  reference detail, rare paths, and the core procedure inlined together.
  Source: *"For long skills, try and use progressive disclosure as much as
  possible - divide it into many files and split them out."*
- **3 — Competent.** The primary file carries the core path; longer or rarer
  detail lives in a supporting file it references by name.
  Source: *"Think of skills as lightweight guides to let Claude find information
  when needed."*
- **5 — Exemplary.** Multi-level and *multi-file* disclosure — a lean entry
  point, several separately-loadable references split by the path that needs
  them, and executable scripts that run without being read into context.
  Source: *"divide it into many files and split them out"*; and for tools, the
  post's *"deferred loading, which means the agent must search for their full
  definitions using ToolSearch before using them"* as the same principle applied
  one level up.

## C4 — Single source of truth

Whether guidance lives in exactly one place. The defect is the same statement
maintained in two or more surfaces — a skill and a rule, two sibling skills, a
skill and `CLAUDE.md` — where drift is inevitable and every copy is paid for.

- **1 — Written for the old rules.** Substantial duplication: the unit restates
  guidance that already exists in another loaded surface, or repeats itself
  across sections.
  Source: *"Delete redundant instructions across system prompt, tool
  descriptions, and CLAUDE.md files."*
- **3 — Competent.** Overlapping material is referenced rather than restated;
  where the unit repeats something, it is a one-line pointer, not a copy.
  Source: *"Place tool usage guidance in tool descriptions, not repeated
  systemwide."*
- **5 — Exemplary.** Each piece of guidance is owned by exactly one surface, and
  the unit names that owner where a reader would otherwise re-derive it; the
  ownership boundary is explicit enough that a future edit knows where to land.

## C5 — Always-loaded budget

Applies to `CLAUDE.md` and `.claude/rules/*.md`. Whether always-loaded content is
restricted to what must hold on **every** turn, with everything intent-triggered
moved to an on-demand surface.

- **1 — Written for the old rules.** Always-loaded content states the obvious,
  documents structure a reader could see from the repo, or carries procedures
  that only matter when a specific task is requested.
  Source: *"Avoid stating 'the obvious' things Claude should know by looking at
  your file system or your repo."*
- **3 — Competent.** Lightweight statement of what the repo is, with the tokens
  spent on genuine gotchas rather than on structure or procedure.
  Source: *"Keep your CLAUDE.md lightweight and briefly describe what your repo
  is for, but spend most of the tokens on gotchas inside of the codebase."*
- **5 — Exemplary.** Gotchas only, with every procedure promoted to a skill and
  referenced by name from the always-loaded surface.
  Source: *"Use progressive disclosure heavily, for example if you have several
  unique instructions on how to verify your work, create a verification skill
  and reference it from your CLAUDE.md."*

## C6 — Rich references over prose specs

Whether the unit points at high-fidelity artifacts — runnable scripts, schemas,
test suites, rubrics, real code — instead of describing in prose what an
artifact could state exactly. Judge relative to whether such an artifact could
exist: a genuinely narrative unit is not penalised.

- **1 — Written for the old rules.** Mechanical, repeatable work (parsing,
  counting, fixed transforms, validation) is described in prose for the model to
  re-derive each run, where a script or schema would state it exactly.
  Source: the post's shift *simple specs → rich references*; code gives *"clear,
  high-fidelity instructions"*.
- **3 — Competent.** The deterministic parts are delegated to bundled scripts,
  schemas, or referenced code, and the unit points at them clearly.
- **5 — Exemplary.** References are executable and self-verifying (a script, a
  test suite, a rubric, a fixture), and the unit is explicit about whether the
  model should **run** the artifact or **read** it.

---

## House criteria excluded from scoring

These are house rules under test in this benchmark. They carry **no score** and
must not be cited as anchors. Judges who notice them should score the underlying
published property (leanness, single-sourcing, trigger quality) instead.

- **The mandatory `## When to Use This Skill` decision table** (`skill-quality.md`).
  The post locates when-to-use in the artifact's `description`. Whether the body
  table earns its tokens is the *question*, not the standard.
- **The mandatory `## Agentic Optimizations` table** (`skill-quality.md`). No
  published requirement.
- **The 26,000-char body ceiling and 10,000-char target** (`skill-quality.md`).
  The post supports leanness and file-splitting, not a specific char gate. C3
  scores disclosure structure, not a threshold.
- **The literal `REFERENCE.md` filename** (`skill-quality.md`). The post says
  "divide it into many files"; the filename is house convention.
- **The ~150-char description target / 300-char error band**
  (`skill-quality.md`). Not addressed by this post.
- **`created` / `modified` / `reviewed` frontmatter dates** (`skill-quality.md`).
- **The `opus`/`sonnet` extremes-only model policy, `haiku` banned**
  (`skill-quality.md`).
- **Positive-framing-only writing style** (`skill-quality.md`). Adjacent to C1
  but not the same claim; C1 scores whether constraints are load-bearing, not
  how they are phrased.
- **Conventional-commit scopes, release-please dogfooding, plugin lifecycle
  bookkeeping** (`CLAUDE.md`). Out of scope for context-engineering scoring.
- **The Channel M scanner's own thresholds** (constraint density ≥1.5/1k, example
  ratio ≥0.25, flat-body >10,000 chars, containment ≥0.15). These select *which*
  units get judged; they are not evidence of a defect and judges never see them.

## Source & provenance

Single scored source: **"The new rules of context engineering for Claude 5
generation models"**,
https://claude.com/blog/the-new-rules-of-context-engineering-for-claude-5-generation-models
— retrieved 2026-07-26.

**Provenance caveat, stated so no reader over-trusts the quotes.** The post was
retrieved through a fetch-and-summarise tool, not scraped verbatim. Lines
presented in quotation marks above were returned by that tool as verbatim
extracts; the shift names (*rules → judgment*, *examples → interface design*,
*upfront information → progressive disclosure*, *repetition → single source of
truth*, *manual → automatic memory*, *simple specs → rich references*) and the
enumeration example in C2 came back as summary rather than quotation. Anchors
resting on summarised material are C2's worked example and the C6 shift name;
treat those two as slightly softer than the rest. Anyone re-running this
benchmark should re-fetch the post and re-verify before extending the rubric.

**Deliberately unscored shift.** The post's fifth shift — *manual memory →
automatic memory* ("Claude now auto-saves relevant memories; stop manually
curating CLAUDE.md files for memory storage") — has **no dimension** here. It is
a claim about the harness's behaviour, not a property of an artifact, and acting
on it would mean changing how `session-distill` writes rules. It needs
verification against the installed Claude Code version before it can gate
anything.

## Related

- `docs/benchmarks/2026-07-marketplace-quality/rubric.md` — the prior benchmark
  whose two-channel method, quote-gating, and exclusion-list discipline this run
  reuses
- `.claude/rules/skill-evaluation.md` — the tiered cost model; ablation (Tier 2)
  is the follow-up that would turn these judgments into measurements
