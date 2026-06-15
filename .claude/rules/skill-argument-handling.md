# Skill Argument-Handling Audit

A skill's argument surface — its `args` / `argument-hint` frontmatter and the
`$ARGUMENTS` parsing in its body — should match how a user or agent would
*naturally* invoke it. When it doesn't, the friction is silent: the user pastes
a form the skill ignores (a GitHub issue **URL** instead of a bare number), or
hands a judgment skill a focus directive it never reads. This rule is the
rubric for spotting that mismatch, plus the cold-read **agent sweep** that finds
it at scale and the haiku-vs-opus delta that calibrates the sweep.

Companion to `skill-development.md` (the `$ARGUMENTS` / `$N` substitution
table), `skill-execution-structure.md` (the `## Parameters` section), and
`skill-quality.md` (description length). The canonical fixes that motivated this
rule are `git-plugin:git-issue` (issue URLs/`#N`) and `project-plugin:refocus`
(optional focus directive).

## The 9-axis rubric

Score each axis `ok` / `gap` / `n/a` with one evidence phrase. A skill is a
*mismatch* if any axis is a `gap`.

| # | Axis | A `gap` looks like |
|---|------|--------------------|
| 1 | **Input-form coverage** | Operates on issues but accepts bare `N` only — not `#N`, not a pasted `…/issues/N` URL. (Generalizes to path/glob/branch/PR/free-text for what the skill targets.) |
| 2 | **Plurality / batch intent** | Naturally-bulk work (issues, files, PRs) takes one target, or takes many but offers no sequential **and** parallel path. |
| 3 | **Steering-directive support** | A judgment skill (triage/refocus/review/plan) can't take a free-text focus/exclude directive. Mechanical skills: `n/a`. |
| 4 | **Declared-vs-parsed consistency** | An `args` token has no `## Parameters` entry or body reference; a flag is parsed but undeclared; a form is advertised but never normalized. |
| 5 | **argument-hint quality** | The hint says *when* to invoke, not *what to type* (refocus's old hint is the anti-pattern). |
| 6 | **No-arg / default behavior** | A bare invocation silently no-ops instead of an interactive prompt, a clear default, or a clean error. |
| 7 | **Scope / target narrowing** | The default over-scopes and the user can't constrain it (path, label, component). |
| 8 | **Flag collision & ordering** | Positionals vs flags are ambiguous, or a flag's comma-value is mis-split into positionals. |
| 9 | **Cross-context refs** | A target in another repo/dir/branch isn't addressable when the skill's job implies it. |

`n/a` is a first-class verdict. A `user-invocable: false` reference skill (a CLI
knowledge base like `tools-plugin:jq-json-processing`) has no argument surface —
**most axes are `n/a` and the verdict is `matches`.** Do not invent a
hypothetical invocable form to score it against (see the haiku failure mode
below).

## The cold-read sweep

Modeled on `agent-patterns-plugin:cold-read-gate`: isolated, cheap, single-file
readers that judge an artifact they have no context for. Here the question is
"does this skill's argument surface match its stated purpose?" rather than "is
this text legible?".

**Dispatch.** One skill per reader, **single-message parallel** `Agent` batch
(the `parallel-agent-dispatch` contract). Each reader reads **only** that
skill's `SKILL.md` by absolute path — no `REFERENCE.md`, no repo exploration
(exploration restores the context the cold read removes). Give it the 9 axes,
the path, and the output schema; tell it to ignore date fields and
`allowed-tools` (test artifacts).

**Output schema** (the reader's final message *is* the deliverable):

```json
{"skill":"plugin:name","verdict":"matches|mismatch",
 "axes":[{"axis":"input-form-coverage","status":"gap","evidence":"…"}],
 "top_gap":"one sentence or 'none'",
 "suggested_fix_shape":"frontmatter+normalization-step|add-parameters-section|accept-plural|add-steering-directive|none"}
```

Validate each reader's JSON; on a parse failure re-dispatch that one reader once
(cold-read-gate's "re-read only on failure"), then drop it rather than block the
batch. Keep wave width modest — the `[1m]`-model concurrent-subagent rate-limit
caveat in `skill-fork-context.md` applies; do **not** use `context: fork`.

**Two reader pools, same sample.**

| Pool | Dispatch | Role |
|------|----------|------|
| **haiku** | `Agent(subagent_type: general-purpose, model: haiku)` | The busy-maintainer proxy / measurement instrument. The `model: haiku` ban is on skill *frontmatter* (AskUserQuestion formatting) — a haiku **reader subagent** with no AskUserQuestion is the documented cold-read-gate exception, not a violation. |
| **opus** | `Agent(subagent_type: general-purpose, model: opus)` | The conservative second opinion — better at declared-vs-parsed nuance and at distinguishing a real defect from a wishlist. |

> **Effort is not per-dispatch expressible.** The `Agent` tool exposes `model`
> but not effort; "opus low effort" can't be set on a subagent (effort is a
> session/harness setting — see `skill-development.md`). Opus readers run at the
> parent's inherited effort. Record this when reporting the delta.

## haiku-vs-opus delta (pilot, 8 skills, 2026-06-15)

The pilot ran both pools over 8 stratified skills. The clean comparison is the 6
skills not edited mid-flight (`git-issue` was edited between the haiku and opus
dispatch, so its opus read is contaminated — exclude it from the delta).

| Signal | What we saw | Takeaway for the sweep |
|--------|-------------|------------------------|
| **Agreement on structural gaps** | Both models flagged `git-issue-manage`'s `#N`/URL input-form gap; both passed `git-triage`, `blueprint-sync-ids`, `jq`. | Both-agree gaps are high-confidence — fix them. Clear structural mismatches don't need opus. |
| **haiku over-flags reference skills** | On `tfc-run-logs` (`user-invocable: false`), haiku invented a hypothetical invocable form and returned `mismatch`; opus correctly returned `matches` (n/a). | Pre-filter the sweep to user-invocable skills, or trust opus to veto a haiku `mismatch` on a `user-invocable: false` skill. |
| **haiku catches user-desired features opus rationalizes away** | On `refocus`, haiku flagged the steering-directive gap (exactly the feature the user wanted); opus called steering `n/a` ("not its purpose") but instead caught the argument-hint mis-use (axis 5). | haiku is the better "what would a user want to type" proxy on axes 1 & 5; opus is the better axis-4/5 *consistency* auditor. Keep both — they are complementary, not redundant. |
| **haiku wishlists; opus picks the defensible one** | On `code-refactor`, haiku flagged steering + scope (feature requests); opus flagged one ergonomic (no-arg default). | A haiku-only gap on a subtle axis with opus disagreement is likely wishlist noise — downgrade. A haiku-only gap on input-form/hint (axes 1, 5) is signal — keep. |

**Confidence rule for reconciliation:**

- **Both flag the same axis** → high confidence; fix this pass.
- **haiku-only on axes 1 or 5** (input-form / hint quality) → signal (the cheap
  reader is the user proxy); keep.
- **haiku-only on a reference skill, or a subtle axis opus passed** → likely
  false positive; opus's disagreement is the filter — downgrade.
- **opus-only** → second-tier; usually a real but ergonomic gap.

## Scope: sample first, sweep second

Do **not** run all ~160 user-invocable skills twice on day one.

1. **Pilot** ~15–25 stratified skills (bulk-work, judgment, ID/URL-takers,
   mechanical CLI wrappers as expected-`matches` controls), both pools, to
   calibrate the rubric and the delta.
2. **Full sweep**: haiku on all user-invocable skills (cheap), opus only on the
   haiku-`mismatch` set + a ~10% random audit slice (catches haiku
   false-negatives without paying opus corpus-wide).

Each surfaced mismatch becomes its own fix-with-regression-check task (per
`regression-testing.md`): a body change to the SKILL.md **and** a semantic guard
in `plugin-compliance-check.sh` `check_skill_body()` asserting the new form is
both advertised and parsed.

## Related

- `agent-patterns-plugin:cold-read-gate` — the isolated-reader pattern this sweep reuses
- `agent-patterns-plugin:parallel-agent-dispatch` — single-message batch contract
- `.claude/rules/skill-development.md` — `$ARGUMENTS` / `$N` substitutions, model selection, effort
- `.claude/rules/skill-execution-structure.md` — the `## Parameters` section contract
- `.claude/rules/skill-evaluation.md` — the broader cross-model delta methodology this mirrors
- `.claude/rules/regression-testing.md` — every surfaced fix gets a semantic guard
