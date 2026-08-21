# Results — Golden-Set Canaries Scored Against the 2026-08 Rubric

**Run date:** 2026-08-21. **Units:** the 16 Tier-2 canaries in
`evaluate-plugin/golden-set.json`. **Rubric:** [`rubric.md`](rubric.md), 8
dimensions. **Appraisal that caps interpretation:** [`appraisal.md`](appraisal.md).

**These are profiles, not grades.** No per-skill total is computed anywhere —
`summarize.py` has no code path that sums a skill's dimensions, because the
source studies never varied skill quality as an independent variable.

---

## Method

| Element | Value |
|---|---|
| Judges | 2 independent per canary (`j1`, `j2`), 32 total |
| Judge isolation | Cold read. Each judge was forbidden to consult `.claude/rules/`, `CLAUDE.md`, or any repo convention doc, and forbidden to compare skills to one another |
| Anti-circularity | Anchors trace only to published findings. House conventions are the thing under test, so they could not also be the yardstick |
| Adjudication | A third judge fired only where the pair differed by ≥2 on a dimension |
| Evidence rule | Any score ≠ 3 required a verbatim quote, mechanically string-matched against the source |
| Agents | 32 completed, 0 errors, 0 empty results |

### Integrity check

```
QUOTES_CHECKED=398   QUOTES_VERIFIED=398   QUOTES_FAILED=0
EXTREME_SCORES_WITHOUT_EVIDENCE=0   STATUS=OK
```

Every one of 398 evidence quotes resolves character-for-character against the
SKILL.md it was drawn from. No fabricated or paraphrased evidence, and no
extreme score asserted without support. `quote_check.py` is the falsifier and it
found nothing to falsify.

---

## Finding 1 — the rubric is reliably applicable

| Metric | Value |
|---|---|
| Dimension-pairs compared | 128 |
| Exact agreement | **110 (85.9%)** |
| Within one point | **128 (100.0%)** |
| Disagreements ≥ 2 points | **0** |
| Applicability (`n/a`) disagreements | 0 |
| Adjudications triggered | **0** |

Two independent cold readers, scoring 16 skills on 8 dimensions with no
communication, never differed by more than a single point. The adjudication
stage was built and never fired.

**What this licenses:** the rubric has good *inter-rater reliability* — it means
the same thing to different readers. That is a real and non-trivial property; a
rubric that fails it produces noise regardless of how good its anchors are.

**What this does not license:** reliability is not validity. Two readers
agreeing precisely does not make the thing they agree on predictive of skill
effectiveness. The rubric could be reliably measuring something that does not
matter. Establishing validity still requires the ablation in
[`rubric.md`](rubric.md) § Validation.

---

## Finding 2 — D4 has zero variance and is a weak instrument

| | D4 (adaptation latitude) |
|---|---|
| Range across 16 canaries | **4 to 5** — no skill scored below 4 |
| Mean inter-judge gap | **0.00** — both judges agreed exactly, on every skill |

Every canary scored 4 or 5, and the two judges never disagreed by even one
point. Two readings:

1. **Genuine corpus strength.** Plausible — this repo's culture pushes hard on
   "when to use something else", and the judges' quotes bear that out
   (`fd-file-finding` carries two sibling-routing tables plus a "use `find`
   instead" section).
2. **The anchor is too easy to satisfy.** A dimension that never discriminates
   is not measuring anything, however good the underlying finding is.

**These are not separable from this run.** A dimension with no variance and no
disagreement cannot tell you which it is. Before D4 is trusted, it needs
anchors re-cut against skills known to be rigid — and the honest reading today
is that **D4 currently carries no information**, despite resting on one of the
paper's strongest measurements (grade A: skill-caused failures 10.0% vs <1%).

---

## Per-dimension profile

| Dim | Name | Mean | Min | Max | Reading |
|---|---|---|---|---|---|
| D1 | procedural-anchoring | **3.28** | 1 | 5 | **Widest spread in the set.** Bimodal by archetype — see Finding 3 |
| D2 | outcome-annotation | **3.09** | 1 | 5 | **Lowest mean.** See Finding 4, which corrects an earlier claim |
| D3 | execution-specificity | 3.94 | 2 | 5 | Strong, consistent with the repo's exact-command discipline |
| D4 | adaptation-latitude | 4.06 | 4 | 5 | No variance — see Finding 2 |
| D5 | budget-discipline | 3.75 | 2 | 5 | Spread; the low end is large bodies with no sidecar |
| D6 | retrieval-distinctness | 3.84 | 2.5 | 5 | Solid; weakest where siblings share vocabulary |
| D7 | scope-focus | 3.69 | 2 | 5 | Low end is multi-path bundles |
| D8 | constraint-checkability | 4.03 | 3 | 5 | Strongest floor — nothing scored below 3 |

## Per-archetype profile

| Pattern | D1 | D2 | D3 | D4 | D5 | D6 | D7 | D8 |
|---|---|---|---|---|---|---|---|---|
| weak-model-gate | 4.5 | 4.0 | 4.8 | 4.5 | **5.0** | 4.5 | 4.8 | **5.0** |
| ask-user-question | 4.5 | **5.0** | **5.0** | 4.0 | 2.8 | 3.8 | 4.0 | 4.5 |
| multi-step-orchestrator | 4.2 | 3.2 | 4.3 | 4.0 | 3.8 | 4.3 | 4.2 | 4.3 |
| convention-enforcer | 3.3 | 3.7 | 3.7 | 4.0 | 4.7 | 3.2 | 4.2 | 4.3 |
| file-generator | 3.5 | **1.5** | 2.8 | 4.0 | 4.0 | 4.0 | 3.0 | 3.2 |
| cli-wrapper | **1.2** | 2.0 | 3.5 | 4.0 | 2.8 | 3.6 | 2.6 | 3.2 |

---

## Finding 3 — CLI wrappers are shaped as the mode the paper says contributes least

`cli-wrapper` scores **D1 = 1.2**, against a corpus mean of 3.28. All four —
`rg-code-search`, `jq-json-processing`, `fd-file-finding`, `git-cli-agentic` —
are flag catalogues with no ordered procedure. Judge language, independently
arrived at:

> "A well-scoped flag catalogue with unusually strong 'use something else
> instead' boundaries, but no procedure and no failure knowledge whatsoever."

> "An exemplary set of exact, runnable commands … wrapped around zero
> procedure: the body is a flat ten-section option catalogue."

Mapped onto the paper's mechanism split, these skills are almost pure
**knowledge injection** — the pathway credited with **4.5%** of skill
effectiveness — and carry almost none of the **procedural anchoring** credited
with **65.7%**.

**This is a hypothesis, not a defect.** Three reasons to hold it loosely:

- A CLI wrapper's job may legitimately *be* reference. The rubric cannot tell
  "wrong shape" from "different job", and D1's anchor does not exempt reference-
  shaped skills.
- The mechanism split is the paper's **weakest-supported number** (evidence
  grade C — ~3% LLM-coded sample, truncated inputs). Finding 3 inherits that.
- These same skills score **D4 = 4.0** — they are unusually good at routing to
  the right sibling, which is real value the D1 score does not capture.

The testable version: if D1 predicts effectiveness, the four CLI wrappers should
show smaller with-skill − baseline deltas than the orchestrators. We have the
machinery to check that and have not run it.

## Finding 4 — a correction to the D2 convergence claim

[`README.md`](README.md) originally recorded D2 as **"Converged in practice"**,
asserting our provenance discipline was *richer* than the paper's synthetic
skills, citing `loop-integrity.md`, `agent-coworker-detection.md`, and
`gh-json-fields.md`.

**The canary data does not support that claim for skills.** D2 is the corpus's
**lowest-scoring dimension (mean 3.09)**, with `file-generator` at **1.5** and
`cli-wrapper` at **2.0**. `docs-generate` scored **1** — "records no failure
mode anywhere". `configure-readme` scored **2** — "no failure mode, symptom, or
cost is attached to any step."

The error was one of artifact class: every example cited was a
`.claude/rules/*.md` file, not a `SKILL.md`. **The failure provenance lives in
the rules; the skills mostly do not carry it.** Since the rules are always-
loaded-when-scoped and the skills are what fires at invocation time, guidance
sits in the layer that is *not* present when the procedure runs.

That is a more interesting finding than the original claim, and it is the one
dimension where the corpus looks genuinely weak against a **grade-B, directly-
ablated** result (0.7462 → 0.4000). `README.md` has been corrected.

---

## What this run does and does not establish

| Question | Answer |
|---|---|
| Is the rubric reliably applicable? | **Yes** — 85.9% exact, 100% within one point, 0 adjudications |
| Is evidence trustworthy? | **Yes** — 398/398 quotes verified mechanically |
| Does it predict effectiveness? | **Unknown.** No study varied quality; no local ablation has been run |
| Can it rank or gate skills? | **No.** Reliability without validity, and D4 carries no information |
| What is the sharpest signal? | D1 on CLI wrappers (Finding 3) and D2 corpus-wide (Finding 4) |
| Cheapest next step | Correlate these D-scores against Tier-2 with-skill − baseline deltas |

**The correlation half remains blocked.** Only `git-commit` has an `evals.json`,
and no Tier-2 matrix results are committed, so D-scores cannot yet be regressed
against measured deltas. That gap — not more papers — is what stands between
this rubric and being trustworthy.

## Reproduce

```bash
python3 docs/benchmarks/2026-08-agent-skills-research/quote_check.py   # falsify evidence
python3 docs/benchmarks/2026-08-agent-skills-research/summarize.py     # regenerate profiles
```

Raw judgments: [`judgments/`](judgments/) — 32 files, `<slug>_j1.json` /
`<slug>_j2.json`, each carrying per-dimension scores, rationales, and verbatim
evidence.
