# Derived Rubric — Agent-Skill Quality Indicators (2026-08 research synthesis)

**Status: PROVISIONAL — signal only, not a grade.**
Derived 2026-08-21 from three papers; see [`appraisal.md`](appraisal.md) for the
critical evaluation that caps how hard this may be leaned on.

## Read this before scoring anything

**No study in the source set varied skill quality as an independent variable.**
SkillsBench used quality as a *selection filter* (top quartile, to remove
variance); Demystifying varied representation, annotation, harness and pool
size; Skill Coverage measured instruction adherence, not quality. So every
dimension below is an **inference** from a mechanism or failure finding — "X
drives the benefit, therefore skills shaped like X should be better" — and none
is a measured quality→outcome relationship.

Consequences, which are binding:

1. **Do not gate, rank, or block on these scores.** Not in CI, not in review.
2. **Do not aggregate to a single number.** A total invites exactly the
   ranking use case that the evidence cannot support. Score per dimension,
   report as a profile.
3. **A low score is a hypothesis, not a defect.** It means "this skill is
   shaped unlike what the mechanism findings predict works" — which may be
   correct for its domain.

### Anti-circularity constraint

**Every anchor below traces to a published finding, never to a house rule.**
This rubric exists partly to test whether our conventions independently
converged with the literature. If our conventions were also the yardstick, the
comparison would be worthless. Where a house rule happens to agree, that
agreement is a *result*, recorded in [`README.md`](README.md) — it is not an
input here.

### Scoring mechanics (inherited from the 2026-07 frozen-rubric precedent)

- Each dimension scores **1–5**; anchors defined at **1, 3, 5**; 2 and 4 interpolate.
- **3 = consistent with the findings.** **5 = exemplary.** **1 = shaped against the findings.**
- **Any score other than 3 requires a verbatim quote** from the skill, reproduced
  exactly so it can be string-matched. A score you cannot quote for is a 3.
- Score against anchors **first**, before comparing skills to each other.
- Record `n/a` where a dimension does not apply. Do not invent a score.

### Evidence grade, per dimension

| Grade | Meaning |
|---|---|
| **A** | Direct measurement in a controlled arm; not sample-coded |
| **B** | Measured, but with a disclosed confound, wide CI, or benchmark-specific framing |
| **C** | Inferred from LLM-coded sample or from a structural observation, not a controlled result |

---

## D1 — Procedural anchoring

**Does the body read as an executable procedure, or as declarative knowledge?**

*Provenance:* Demystifying — procedural anchoring **65.7%** of skill
effectiveness vs explicit knowledge injection **4.5%**; "skills work when noisy
trajectories become procedural anchors that stabilize execution."
**Evidence grade: C** (3% LLM-coded sample; truncated coding window plausibly
biases toward early-visible anchoring — see appraisal §3.1).

| Score | Anchor |
|---|---|
| 1 | Body is predominantly facts, background, or option catalogues. A reader finishes knowing *about* the topic with no committed sequence of actions. |
| 3 | Contains an identifiable ordered procedure, though mixed with substantial declarative material that does not feed a step. |
| 5 | The spine is an ordered sequence of imperative steps with concrete decision points. Declarative material is present only where a step consumes it, or is deferred to a sidecar. |

---

## D2 — Outcome-annotated guidance

**Does guidance record what failed, why, and what the failure cost?**

*Provenance:* Demystifying RQ2 — stripping success/failure identities while
preserving the same trajectories degraded skill quality **0.7462 → 0.4000**
(Gemini, 3s2f). Effect concentrates where source evidence mixes successes and
failures.
**Evidence grade: B** (controlled ablation, but a single reported
model×mixture cell).

| Score | Anchor |
|---|---|
| 1 | Instructions are unlabelled assertions. Nothing indicates which paths were tried, which failed, or what the failure looked like. |
| 3 | Some outcome signal — a warnings or gotchas section — but disconnected from specific steps, or asserted without observed consequence. |
| 5 | Failure modes are attached to the steps they threaten, each naming the observed symptom and its cost, so the reader can recognise the failure in progress. |

> **Known tension with the positive-framing convention.** This dimension
> rewards explicit failure content; `skill-quality.md` § Writing Style directs
> authors toward positive guidance. These conflict less than they appear —
> RQ2 concerns *outcome labelling of evidence*, not prose polarity, and a
> failure can be documented in positive voice ("re-run once to confirm; a
> second failure is real"). Flagged rather than resolved: resolving it needs
> an ablation we have not run.

---

## D3 — Execution-layer specificity

**Does it address environment, format, and lifecycle concretely enough to
prevent mechanical failure?**

*Provenance:* Demystifying SC2 reductions, raw → skill: environment
infrastructure **5.3% → 0.2%**, output format/schema mismatch **7.4% → 3.2%**,
background service lifecycle **2.7% → 0.8%**. This is where skills delivered
their largest measured wins.
**Evidence grade: A** (direct arm-to-arm measurement).

| Score | Anchor |
|---|---|
| 1 | Operates at description level. Commands are paraphrased, formats implied, environment assumptions unstated. |
| 3 | Gives concrete commands or formats for the main path; edge conditions, exact output shapes, and setup preconditions left to the reader. |
| 5 | Exact invocations, exact expected output shape, and explicit environment/lifecycle preconditions — including how to tell the precondition is unmet. |

---

## D4 — Adaptation latitude

**Does it say when *not* to apply, and provide an escape from itself?**

*Provenance:* Demystifying SC3 — skills introduce failure modes absent from raw
execution: `skill_guidance_misapplied_or_ignored` and `timeout_budget_exhaustion`
at **10.0% of skill trials vs <1% raw**; skills "fail under brittle assumptions
and incompatible contexts"; over-rigid formatting produces "mechanical
application without contextual judgment."
**Evidence grade: A** (direct rate comparison between arms).

The counterweight to D1 and D3 — this is the dimension a rubric optimised for
prescriptiveness would drive to zero.

| Score | Anchor |
|---|---|
| 1 | Unconditional. Presents its procedure as always-correct, with no stated scope limit and no exit. |
| 3 | States a scope or applicability boundary, but gives no guidance for the case that falls outside it. |
| 5 | Names the conditions under which the procedure does not apply, and says what to do instead — including the case where the guidance itself is wrong for the situation. |

---

## D5 — Budget discipline

**Is it small enough not to consume the budget it is meant to save?**

*Provenance:* Demystifying — timeout/budget exhaustion **10.6%** under workflow
memory vs **4.4%** under skills; distillation is part of the mechanism, not
incidental. SkillsBench ecosystem structure — median `SKILL.md` **~1.5k tokens**,
median total **<2.5k tokens**; "Focused Skills with at most three modules
outperform larger or exhaustive bundles."
**Evidence grade: B** (timeout rates measured directly; the token medians are
descriptive ecosystem statistics, not an outcome-linked threshold).

| Score | Anchor |
|---|---|
| 1 | Body is many multiples of ecosystem median with no deferral, so every invocation pays for material most runs never use. |
| 3 | Body is larger than ecosystem median but material is coherent to one procedure, or partially deferred. |
| 5 | Body is at or near ecosystem median for the always-loaded portion, with detail deferred to on-demand files. |

> **Calibration note.** The ~1.5k-token median describes what the ecosystem
> *is*, not what performs best — SkillsBench never tested size against outcome.
> Treat "above median" as a prompt to check deferral, never as a defect.

---

## D6 — Retrieval distinctness

**Is this skill discriminable from its siblings in a large pool?**

*Provenance:* Demystifying RQ4 — pool 5→100 drops actual-use precision **29.6%
→ 3.3%**; failure includes "semantic confusion when retrieval pools contain
similar-sounding but distinct skills."
**Evidence grade: B, with an important sign caveat** — in the same experiment
**task success stayed flat (36.4% → 39.3%)** as precision collapsed, and the
authors conclude exact matching is "neither sufficient nor strictly necessary."
So precision loss is demonstrated; that it *costs task outcomes* is not.

| Score | Anchor |
|---|---|
| 1 | Trigger surface is generic or overlaps a sibling's almost entirely; nothing distinguishes the two on a description read. |
| 3 | Trigger surface is topically clear but shares substantial vocabulary with a sibling; disambiguation needs the body. |
| 5 | Trigger surface names the distinguishing condition, so the correct choice between it and its nearest sibling is decidable without opening either body. |

---

## D7 — Scope focus

**One coherent procedure, or an exhaustive bundle?**

*Provenance:* SkillsBench — "Focused Skills with at most three modules
outperform larger or exhaustive bundles"; **2–3 skills optimal** per task with
diminishing returns past four.
**Evidence grade: B** (measured in SkillsBench, but "module" is not defined in
terms that map cleanly onto our layout).

| Score | Anchor |
|---|---|
| 1 | Bundles several independent procedures that share only a topic; most invocations use one and pay for all. |
| 3 | One dominant procedure with adjacent secondary material that could plausibly stand alone. |
| 5 | One procedure with one entry condition. Everything present serves that procedure. |

---

## D8 — Constraint checkability

**Can its instructions be extracted as discrete constraints and observed in a
trajectory?**

*Provenance:* Skill Coverage — constraint extraction + per-constraint pass/fail;
agent trajectories covered only **38.66–45.51%** of extracted constraints;
strengthening failed instructions recovered **16.0%** of tasks across five
configurations.
**Evidence grade: B** (measured on SkillsBench; the metric is newly proposed and
not independently replicated).

| Score | Anchor |
|---|---|
| 1 | Guidance is stated so that no observer could determine from a transcript whether it was followed. |
| 3 | Some instructions are checkable; others are dispositional ("be careful", "consider") with no observable correlate. |
| 5 | Instructions decompose into discrete conditions each of which would be visibly satisfied or violated in a transcript. |

---

## Deterministic-check convertibility

The user-facing point of the exercise: which dimensions could eventually harden
into a script. **None of these should be built until the rubric is validated
against more studies** — this is a roadmap, not a backlog.

| Dim | Convertible? | Mechanism | Cost |
|---|---|---|---|
| **D6** | **Best candidate** | Nearest-neighbour cosine over skill descriptions; flag pairs above a similarity threshold as confusable. `adapters/core/` **already has the embedding and BM25 machinery**, and `adapters/eval/` already reports hit@1 / hit@k / MRR over the full corpus — a sibling-confusability report is largely a new query over existing infrastructure. | Low |
| **D5** | **Already partly built** | `check_skill_size()` gates characters. Adding an ecosystem-median comparator (~1.5k tokens) is arithmetic on data we already compute. | Very low |
| **D2** | Partial | Presence of provenance markers — issue refs, dated observations, symptom/cost pairs — is greppable. Detects *presence*, never *quality*. | Low |
| **D1** | Heuristic only | Imperative-verb ratio and numbered-step density are computable; both are gameable and would misfire on legitimately reference-shaped skills. | Medium |
| **D4** | Heuristic only | Detect exemption/boundary language ("does not apply when", "instead"). Presence-only, same limitation as D2. | Low |
| **D7** | Weak | Count top-level procedures / distinct entry conditions. Structure is too varied for a reliable parse. | Medium |
| **D8** | Indirect | Constraint extraction needs a model, but extracted constraints could ride the existing `evals.json` typed-check schema as assertions. Closest thing to a genuinely new capability. | High |
| **D3** | Not convertible | Semantic. Requires judging whether a command is *correct*, not whether one is present. | — |

**Recommended sequencing if this is ever pursued:** D5 comparator (trivial,
uses existing data) → D6 confusability report (high value, existing embedding
infrastructure) → everything else waits for validation.

## Validation this rubric still needs

To move from *signal* to *grade*, in priority order:

1. **A quality-as-variable study.** The gap all three papers share. Until
   something manipulates skill quality and measures outcomes, every dimension
   here is inference.
2. **Internal ablation.** We have the machinery — `skill-evaluation.md` Tier 2
   with-skill − baseline deltas across a golden set. Scoring canaries on this
   rubric and correlating D-scores against measured deltas would be the first
   *local* evidence, and would cost only a matrix run.
3. **Replication of the retrieval result at our scale**, since the flat-success
   finding is the one that most affects a ~400-skill catalog and it currently
   rests on one benchmark with a substituted model.
4. **Resolution of the D2 / positive-framing tension**, which needs its own
   ablation.

## Related

- [`appraisal.md`](appraisal.md) — critical evaluation; the cap on this rubric's strength
- [`README.md`](README.md) — where our conventions independently converged, and where they diverge
- `.claude/rules/skill-evaluation.md` — the Tier 2 machinery item 2 above would use
- `docs/benchmarks/2026-07-context-engineering/rubric.md` — the frozen-rubric methodology copied here
