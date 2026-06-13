# Cross-Model Skill Evaluation

How we measure skill effectiveness reproducibly, across models (opus / sonnet /
haiku), without burning tokens — so we notice when a skill needs adjusting,
especially when a new Claude model ships.

This is a design + prototype. The prototype lands the token-frugality lever (the
deterministic grader) and the report format against the one existing eval set
(`git-plugin/skills/git-commit/evals.json`). Populating a golden set and the
`/evaluate:matrix` orchestration skill are follow-ups.

## The problem

`evaluate-plugin` already grades a single skill's behaviour against assertions
with a `--baseline` delta. Three things were missing for the question "are our
skills still effective, and which model are they effective on?":

1. **No cross-model dimension** — runs use whatever model is active.
2. **Token cost** — every assertion routes through an Opus `eval-grader`
   subagent, N runs each. Fine for one skill; ruinous as a regular signal
   across 348 skills.
3. **No reproducibility / cadence contract** — nothing pins model IDs or says
   "re-run this fixed set when a model drops and diff against last time."

## Design principles

### 1. Tier the cost; only the top tier spends real tokens

| Tier | Cost | Scope | Cadence |
|------|------|-------|---------|
| 0 — static | free | all 348 skills | every PR (`plugin-compliance-check.sh`, lints) |
| 1 — deterministic evals | ~free (no judge) | skills with `evals.json`, single active model | CI on changed skill |
| 2 — cross-model matrix | budgeted | **golden set only**, opus/sonnet/haiku | monthly + on model release |

Tier 0 catches structural rot for free. Tier 2 is the only thing that costs
tokens, and it is bounded to the golden set.

### 2. Split assertions into deterministic vs judged — the biggest lever

Most skill-output expectations are machine-checkable. From the git-commit set:
"starts with `feat(`", "does not end with a period", "references `#42`",
"both `#100` and `#101`" are regex/substring checks that cost **zero** model
tokens. Only genuinely fuzzy ones ("uses imperative mood", "body provides
context") need an LLM judge.

`scripts/grade_deterministic.py` grades the typed checks and reports the fuzzy
ones as `DEFERRED`, so the judge agent only ever runs on those. On the
git-commit set this is ~70% of assertions graded for free.

Expectations stay backward compatible: a bare string is treated as `judge`
(existing behaviour); a typed object opts into deterministic grading.

```json
{ "assertion": "Commit message starts with feat(", "check": "regex",
  "pattern": "^feat\\(", "scope": "subject" }
```

Check types: `regex`, `substring`, `substring_all`, `absent_regex`, `judge`.
Optional `scope` (`full` | `subject` | `body`) and regex `flags`. Full schema
in [`references/schemas.md`](../references/schemas.md).

### 3. The signal is the with-skill − baseline *delta*, per model, over time

A bare pass rate means nothing; the delta against the model's own baseline does.
The cross-model interpretation is a 2×2:

| | baseline already high | baseline low |
|---|---|---|
| **with-skill high** | possibly **redundant** — model already knows; candidate to slim | **earns its keep** |
| **with-skill low** | **fighting the model** — adds noise | **ineffective** — rewrite |

`render_matrix_report.py` computes the verdict per model from these thresholds
and flags **portability**: a skill that scores ≥20 points higher on opus than
haiku leans on reasoning the cheap model lacks — simplify it or pin `model:`.

This is what "noticing a new model needs adjusting" reduces to: store each
matrix run, and on a new model release re-run the golden set and diff the delta
column (`Δ vs prev`). A canary whose delta collapsed gets flagged — either the
model now does it unaided (redundant) or now does it worse (needs adjusting).

### 4. Reproducibility = pin everything, run on a trigger not per-PR

- Pinned model IDs (`claude-opus-4-8`, `claude-sonnet-4-6`, `claude-haiku-4-5`),
  recorded in `model-matrix.json metadata.models`.
- Single-turn prompts, version-controlled fixtures (`evals.json`).
- **Baseline cached per model-version** — baseline only changes when the model
  changes, so a skill edit re-runs only the with-skill side.
- Trigger: monthly cron + manual "new model dropped" run.

> Note: testing a skill *on* haiku here is unrelated to the repo ban on
> `model: haiku` in skill frontmatter. We evaluate the skill across models; we
> still don't author skills that pin themselves to haiku.

## Run engine: in-session subagents

Cross-model runs reuse the existing `Task`-subagent approach, parameterized by
model (the `Agent`/`Task` `model` field selects opus / sonnet / haiku). This
keeps real tool execution (Bash/Edit) so skills that produce artifacts — not
just text — are evaluated faithfully. The orchestrating `/evaluate:matrix` skill
(follow-up) loops models × evals × {with_skill, cached_baseline}, captures each
transcript, runs `grade_deterministic.py` first, and only dispatches the
`eval-grader` agent for the `DEFERRED` assertions.

Mind `.claude/rules/skill-fork-context.md`: do **not** add `context: fork`, and
serialize subagent dispatch to avoid the `[1m]` concurrent-rate-limit trap.

## Golden set criteria

Don't test all 348 skills × 3 models. Pick ~15–25 canaries that are
representative, high-traffic, or high-risk, covering distinct patterns:

| Dimension to cover | Example canary |
|--------------------|----------------|
| CLI-wrapper skill (mechanical) | `tools-plugin` rg/jq/fd skill |
| Multi-step orchestrator | a `blueprint` or `git` workflow skill |
| `AskUserQuestion` interactive skill | a `configure-plugin` skill |
| Generator (produces files) | a scaffolder skill |
| Convention-enforcing (text output) | `git-plugin/git-commit` ← prototype anchor |

When a new model degrades the canaries, that's the trigger to audit the long
tail. The other ~320 skills stay on Tier 0/1.

## Token math for a full Tier-2 sweep

≈ 20 skills × ~4 evals × 3 models × 2 configs (with-skill + cached baseline)
≈ 480 single-turn runs. At a few k tokens each → low single-digit millions per
monthly sweep. With ~70% of assertions graded deterministically, the judge
agent fires on a fraction of that. Cheap enough to automate; expensive enough to
be worth not eyeballing.

## Prototype status

| Piece | Status |
|-------|--------|
| Typed-check schema on `expectations` | done — `git-commit/evals.json` migrated, back-compatible |
| `scripts/grade_deterministic.py` | done — regex/substring/absent, scope, JSON + KEY=value out |
| `scripts/render_matrix_report.py` | done — delta table, verdicts, portability flag |
| `scripts/tests/test_grade_deterministic.sh` | done — 14 assertions, wired for CI |
| `model-matrix.json` schema | done — documented; example fixture renders |
| `/evaluate:matrix` orchestration skill | done — runs the matrix, grades deterministic-first, renders the executability flag |
| Golden set definition (`golden-set.json`) | done — 16 canaries across 6 patterns |
| Fixture / scaffolding layer (`evals[].fixture`, `apply_fixture.sh`) | done — opt-in, isolated temp workdir, golden-set scope |
| Cron / model-release trigger | follow-up |

## Related

- `.claude/rules/skill-evaluation.md` — the top-level methodology this design
  implements (tiered cost, delta signal, golden set, cadence)
- [`references/schemas.md`](../references/schemas.md) — evals.json (typed
  checks) and model-matrix.json schemas
- [`skills/evaluate-skill/SKILL.md`](../skills/evaluate-skill/SKILL.md) —
  single-skill / single-model evaluation this extends
- `.claude/rules/skill-fork-context.md` — why subagents are serialized and
  `context: fork` is avoided
- `.claude/rules/regression-testing.md` — every check ships a test
- `.claude/rules/structured-script-output.md` — the `=== SECTION ===` /
  `STATUS=` grader output convention
