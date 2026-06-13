# Skill Effectiveness Measurement

How we know our skills actually work — and keep working as new Claude models
ship. This rule is the methodology; the tooling lives in `evaluate-plugin`, and
the full design is
[`evaluate-plugin/docs/cross-model-evaluation.md`](../../evaluate-plugin/docs/cross-model-evaluation.md).

`regression-testing.md` keeps a *fixed* bug from recurring. This rule measures
whether a skill still *adds value* — a different question that the static
compliance checks (structure, description length, size) can't answer.

## The tiered cost model

Measurement is tiered so only the top tier spends model tokens. Run the cheap
tiers always; reserve the expensive tier for a small golden set.

| Tier | Cost | Scope | Cadence | Tooling |
|------|------|-------|---------|---------|
| 0 — static | free | all skills | every PR | `scripts/plugin-compliance-check.sh`, the lints |
| 1 — deterministic evals | ~free (no judge) | skills with an `evals.json` | CI on changed skill | `evaluate-plugin/scripts/grade_deterministic.py` |
| 2 — cross-model matrix | budgeted | **golden set only**, opus/sonnet/haiku | monthly + on model release | `/evaluate:matrix`, `render_matrix_report.py` |

Tier 0 catches structural rot for free. Tier 2 is the only thing that costs
tokens, and it is bounded to the canary set.

## Principle 1 — grade deterministically, judge only the fuzzy

Most expectations are machine-checkable (`starts with feat(`, `references #42`,
`no trailing period`). Encode those as **typed checks** (`regex`, `substring`,
`absent_regex`) so they grade for zero model tokens. Reserve the LLM judge for
genuinely fuzzy expectations (tone, mood, "provides context"). On a typical eval
set ~70% of assertions grade for free.

A bare-string expectation defaults to `judge`, so this is opt-in and backward
compatible. See the typed-check schema in
[`evaluate-plugin/references/schemas.md`](../../evaluate-plugin/references/schemas.md).

## Principle 2 — the signal is the with-skill − baseline *delta*, per model

A bare pass rate means nothing; the delta against the model's own baseline
(same prompt, no skill) does. Interpret it as a 2×2:

| | baseline already high | baseline low |
|---|---|---|
| **with-skill high** | possibly **redundant** — the model already knows; candidate to slim or drop | **earns its keep** |
| **with-skill low** | **fighting the model** — adds noise | **ineffective** — rewrite |

Two derived signals:

- **Portability** — a skill that scores ≥20 points higher on opus than haiku
  leans on reasoning the cheap model lacks. Simplify the skill, or pin `model:`
  in its frontmatter (never `haiku` — see `skill-development.md`).
- **Drift on a new model** — store each matrix run; on a model release, re-run
  the golden set and diff the delta column. A canary whose delta collapsed is
  the trigger to audit: either the new model does it unaided (redundant) or does
  it worse (needs adjusting).

## Principle 3 — a golden set, not all 348 skills

Cross-model runs target ~15–25 canary skills chosen to be representative,
high-traffic, or high-risk — covering distinct patterns (CLI wrapper,
multi-step orchestrator, `AskUserQuestion` skill, file generator,
convention-enforcer). The canaries are the weathervane: when a new model
degrades them, that's the cue to sweep the long tail. Everything else stays on
Tier 0/1.

## Principle 4 — reproducibility and cadence

- **Pin model IDs** in the result file (`claude-opus-4-8`, `claude-sonnet-4-6`,
  `claude-haiku-4-5`), single-turn prompts, version-controlled `evals.json`.
- **Cache the baseline per model-version** — baseline only changes when the
  model changes, so a skill edit re-runs only the with-skill side.
- **Trigger on cadence, not per-PR** — monthly cron plus a manual run whenever a
  new model ships. Tier 2 is too expensive for the per-PR path.

## When to apply this

| Situation | Tier to run |
|-----------|-------------|
| Authoring or editing a skill | Tier 0 (always) + Tier 1 if it has `evals.json` |
| Improving a skill that has `evals.json` | Tier 1 best-of-N: `/evaluate:improve --apply --best-of 3` ranks candidate edits by re-running the deterministic evals and applies the winner |
| Adding a skill to the golden set | Write its `evals.json` with typed checks |
| A new Claude model is released | Tier 2 sweep of the golden set; diff deltas vs last run |
| A skill feels redundant or noisy | Tier 2 with `--baseline` to see if it beats the model alone |

## Related

- [`evaluate-plugin/docs/cross-model-evaluation.md`](../../evaluate-plugin/docs/cross-model-evaluation.md) — full design, run engine, token math
- `evaluate-plugin` — the skills and scripts that implement this
- `.claude/rules/regression-testing.md` — keeping a fixed bug fixed (the complement to effectiveness)
- `.claude/rules/skill-quality.md` — the static-quality axis (Tier 0)
- `.claude/rules/skill-development.md` — model-selection rules referenced by the portability signal
