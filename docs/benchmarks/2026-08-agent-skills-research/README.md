# 2026-08 Agent-Skill Research Synthesis

Appraisal of published agent-skill research, a rubric derived from it, and an
honest check of whether this marketplace's conventions independently converged
with the literature.

**Status: exploratory. Nothing here is wired into a lint, a gate, or CI**, by
design — see the binding constraints at the top of [`rubric.md`](rubric.md).

| File | Contents |
|---|---|
| [`appraisal.md`](appraisal.md) | Critical evaluation of arXiv:2608.14036 and the two adjacent papers — what holds, what to discount, and why |
| [`rubric.md`](rubric.md) | 8 provisional quality dimensions, each traced to a finding and graded for evidence strength |
| [`results.md`](results.md) | The 16 golden-set canaries scored against the rubric — reliability, per-dimension profiles, and two findings |
| [`judgments/`](judgments/) | 32 raw judge records (2 per canary) with scores, rationales, and verbatim evidence |
| `quote_check.py` | Falsifier: resolves every evidence quote against its source file |
| `summarize.py` | Rolls judgments into per-dimension profiles; deliberately computes no per-skill total |
| `README.md` | This file — the convergence check |

## Source set

| Paper | Date | Role |
|---|---|---|
| [Demystifying Agent Skills: Why They Work—Until They Don't](https://arxiv.org/abs/2608.14036) | 2026-08-14 | Primary. Mechanism and failure taxonomy |
| [SkillsBench](https://arxiv.org/abs/2602.12670) | 2026-02, rev. 06 | Effect size; the only published quality rubric |
| [Skill Coverage](https://arxiv.org/abs/2606.20659) | 2026-06-09 | Instruction-adherence metric |

## The one-line verdict on the study

**Sound mechanism study, weak headline effect, and — decisively for our purpose —
skill quality was never an independent variable in any of the three papers.**
So the rubric is inference from mechanism findings, not measured
quality→outcome relationships. Detail in [`appraisal.md`](appraisal.md) §3.7.

---

## Convergence check: did we independently arrive at the same conclusions?

Broadly **yes** — 5 of 8 dimensions converged, several of them predating the
paper by months. One divergence is defensible on a cost model the papers do not
model, and two are genuine gaps.

> **Revised 2026-08-21 after measurement.** This section was first written from
> a reading of our rules. Scoring the 16 golden-set canaries
> ([`results.md`](results.md)) contradicted the D2 row and put a caveat on D4.
> The pre-measurement claims are preserved in the table so the correction is
> visible rather than silently rewritten.

| Dim | Our position | Verdict |
|---|---|---|
| **D1** Procedural anchoring | `skill-execution-structure.md` (2026-03-02) — "when a skill reads like a specification document, the model summarizes what it could do instead of doing it. **This is the most common skill authoring mistake.**" Prescribes `Phase N:` → `Step N: <verb>`, imperative openers, reference data moved out. | **Converged, 5 months early.** We independently named procedure-vs-description as *the* primary failure. The paper quantifies it (65.7% vs 4.5%); we identified it and built the fix. |
| **D2** Outcome annotation | Dated failure provenance with observed cost is pervasive in `.claude/rules/` — `loop-integrity.md`, `agent-coworker-detection.md` ("force-removed ~24 peer worktrees"), `gh-json-fields.md` § "The `merged` mistake" — but **not** in skill bodies. | **Corrected 2026-08-21 by measurement — see [`results.md`](results.md) Finding 4.** This row originally claimed convergence. Scoring the canaries put D2 at the corpus's **lowest mean (3.09)**, with `file-generator` at 1.5 and `cli-wrapper` at 2.0. The provenance lives in the *rules*, not the *skills* — i.e. in the layer that is absent when the procedure actually fires. Against a grade-B ablated finding (0.7462 → 0.4000), this is the corpus's genuine weak axis. |
| **D3** Execution-layer specificity | `agentic-optimization.md`, `structured-script-output.md`, and exact-command discipline throughout — `task-id-stability.md`'s `task +LATEST uuids` vs the silently-empty `_get uuid` is precisely this dimension. | **Converged strongly.** A repo strength. The paper's largest measured win (env failures 5.3%→0.2%) is the thing our rules obsess over. |
| **D4** Adaptation latitude | `hook-block-vs-nudge.md` — block for safety, nudge for style; a hard block "dead-ends subagents lacking the tool." `bash-tool-replacements.md` demoted `find`/`grep`/`ls` from blocks to nudges. | **Converged — and we are ahead.** The paper measures skill-caused failures at 10.0% vs <1%. We independently found the same pathology *and* built a local empirical metric for it: **same-session repeat-block rate**, which drove the #1871/#1909/#2036 demotions and caught #2148's regression (46.3% break from a 6.3–20.0% band). The literature has no equivalent. |
| **D5** Budget discipline | `skill-quality.md`: target ≤10,000 chars (~2,500 tok), ERROR at 26,000 chars (~6,500 tok). | **Divergent, defensibly.** Our ceiling is **~4.3× the SkillsBench ecosystem median** (~1.5k tokens) and our target ~1.7×. But `context-engineering.md` makes the point the papers miss entirely: a `SKILL.md` body is paid *only when the skill fires*, whereas unscoped rules are paid **every turn** — so ranking cuts by `always-loaded cost × frequency` is a strictly better cost model than raw size. We are less strict on the axis the papers measure and stricter on an axis they ignore. |
| **D6** Retrieval distinctness | Description band (~120–150 chars, trigger keywords front-loaded), `skillListingBudgetFraction`, and the pi adapter's `search_skills` + ranked top-k with a frozen gate at `main_hit_at_k_min = 0.57`. | **Converged and ahead.** `adapters/eval/` is effectively RQ4 run continuously in production over ~400 skills, reporting hit@1 / hit@k / MRR. See the caveat below — the paper partially *undercuts* the premise. |
| **D7** Scope focus | `skill-consolidation.md`, and C4 single-source-of-truth in `context-engineering.md`. | **Converged conceptually**, though we have no equivalent of SkillsBench's "at most three modules" threshold, and "module" does not map cleanly onto our layout. |
| **D8** Constraint checkability | `regression-testing.md` (every fixed bug gets a script check) and `evals.json` typed checks. | **Genuine gap.** We verify that *bugs stay fixed* and that *outputs match expectations*. We do not verify that a skill's own instructions were **followed in a trajectory**. Skill Coverage's finding that agents cover only 38.66–45.51% of extracted constraints suggests this blind spot is large. |

### Scorecard

| | Count |
|---|---|
| Converged (some ahead of the literature) | 5 — D1, D3, D4, D6, D7 |
| Divergent but defensible | 1 — D5 |
| Genuine gaps | 2 — D2 (corrected by measurement), D8 |

> **This scorecard was revised after measurement.** D2 was originally counted as
> converged on the strength of `.claude/rules/` examples; scoring the 16 canaries
> showed skill bodies do not carry that provenance. See
> [`results.md`](results.md) Finding 4. D4 also now carries a caveat: it scored
> 4–5 across every canary with zero inter-judge disagreement, so it currently
> discriminates nothing and cannot be counted as evidence of convergence
> either way (Finding 2).

---

## Two findings that should actually change something

Everything above is confirmation. These two are new information.

### 1. Pool growth did not hurt task success — this is reassuring, and it complicates the adapter's rationale

RQ4: as the pool grew 5 → 100, **actual-use precision collapsed 29.6% → 3.3%
while task success stayed flat (36.4% → 39.3%)**. The authors conclude exact
skill matching is *"neither sufficient nor strictly necessary."*

For a ~400-skill marketplace the headline reading is **good news**: catalog
growth is not, on this evidence, degrading outcomes.

The complication is narrower and worth stating plainly. `adapters/CUTOVER.md`
freezes a cutover gate on `main_hit_at_k_min = 0.57` — a **retrieval-quality**
threshold. RQ4 suggests retrieval precision and task success can decouple
badly, so a retrieval metric may be a weak proxy for the outcome we care about.

This does **not** invalidate the adapter. Its primary justification was a
*token-budget* problem — ~9,900 standing tokens over ~95 curated skills reduced
to ~600 while reaching all ~400 — and that argument is untouched by RQ4. What
deserves revisiting is only the implicit assumption that a higher `hit_at_k`
translates into better task outcomes. On current evidence that link is
unestablished in either direction.

### 2. Skills cause failures that raw execution does not

SC3: `skill_guidance_misapplied_or_ignored` + `timeout_budget_exhaustion` at
**10.0% of skill trials vs <1% of raw trials**. This is a direct measurement
(evidence grade A), not a coded inference.

The framing matters: a skill is not a free addition. It removes execution-layer
failures (D3) and introduces invocation-layer ones. Our `hook-block-vs-nudge.md`
litigation test — *what does this exempt?* — is the closest thing we have to a
control on it, and it currently applies to hooks rather than to skills
generally.

---

## What would make this rubric trustworthy

In priority order (expanded in [`rubric.md`](rubric.md) § Validation):

1. **A study that varies skill quality and measures outcomes.** Nobody has run
   it. Until then the rubric generates hypotheses, not grades.
2. **Local ablation.** `skill-evaluation.md` Tier 2 already computes
   with-skill − baseline deltas across a golden set. Scoring those canaries on
   this rubric and correlating D-scores against measured deltas would be our
   first *local* evidence, at the cost of one matrix run. This is the cheapest
   real validation available to us.
3. **More papers.** Two of three search-summary figures checked during this
   appraisal were **wrong** ([`appraisal.md`](appraisal.md) §5) — extend this
   synthesis only from primary sources.

## Deterministic-check roadmap

Not a backlog — nothing here should be built before validation. Full table in
[`rubric.md`](rubric.md).

| Priority | Check | Why it's first |
|---|---|---|
| 1 | **D5** ecosystem-median comparator | Arithmetic over data `check_skill_size()` already computes |
| 2 | **D6** sibling-confusability report | High value, and `adapters/core/` already has the embedding + BM25 machinery to do nearest-neighbour cosine over descriptions |
| — | Everything else | Waits for validation |

## Related

- `.claude/rules/skill-execution-structure.md` — D1, converged independently
- `.claude/rules/hook-block-vs-nudge.md` — D4, where we lead the literature
- `.claude/rules/context-engineering.md` — the cost model that justifies the D5 divergence
- `.claude/rules/skill-evaluation.md` — the Tier 2 machinery that would validate this
- `adapters/CUTOVER.md` — the retrieval gate RQ4 bears on
- `docs/benchmarks/2026-07-context-engineering/` — the frozen-rubric methodology copied here
