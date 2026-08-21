# Appraisal — "Demystifying Agent Skills: Why They Work—Until They Don't"

**Primary paper:** [arXiv:2608.14036](https://arxiv.org/abs/2608.14036) — Jiang,
Huang, Xing, Wu, Gao, Cao, Wang, Liu, Li. Submitted **2026-08-14**.

**Appraised:** 2026-08-21. **Verdict: methodologically strong for its actual
claim, routinely over-read for the claim people want it to make.**

This document evaluates the study on its own terms and positions it against the
two adjacent papers. The rubric derived from it is
[`rubric.md`](rubric.md); read this file first, because the rubric's usable
strength is capped by what is established here.

---

## 1. What the paper actually claims

The paper is **not** a skill-quality study. It is a *mechanism* study asking
"when do skills help, and through what pathway" — deliberately, in its own
framing, rather than "measuring aggregate task success."

| RQ | Question | Headline result |
|---|---|---|
| RQ1 | Does *representation* matter, holding content fixed? | Skills beat workflow memory by **+6.06 pp**, 95% bootstrap CI **[+0.76, +11.36]** |
| RQ2 | Do success/failure annotations matter? | Removing them degrades quality **0.7462 → 0.4000** (Gemini, 3s2f mixture) |
| RQ3 | Do skills transfer across harnesses? | Codex-built skills retain utility when evaluated in Gemini CLI |
| RQ4 | Does retrieval scale? | Pool 5→100: actual-use precision **29.6% → 3.3%**; task success **36.4% → 39.3%** (flat) |

Mechanism decomposition: **procedural anchoring 65.7%** of skill effectiveness
vs **explicit knowledge injection 4.5%**.

Taxonomy: 12 modes in 3 categories — SC1 guided success, SC2 execution &
verification failures, SC3 invocation & budget failures.

---

## 2. The design virtue that makes this paper worth reading

**The control ladder isolates representation from content.** Three arms:

| Arm | Content | Form |
|---|---|---|
| Raw | none | — |
| Workflow memory | the trajectories | appended as procedural memory |
| Skill | *the same* trajectories | distilled into a standardized `SKILL.md` |

This is the thing almost every other skills evaluation gets wrong. Comparing
skill-vs-nothing conflates *having the knowledge* with *having it packaged as a
skill*. By holding the source trajectories fixed and varying only the wrapper,
RQ1 measures the packaging itself. That single design choice is why this paper
can say anything about skill *authoring* at all.

Three further credits:

- **Human validation of the LLM coding.** 714 trajectory–label checks, **95.8%
  exact agreement, Cohen's κ = 0.952**. Most LLM-as-annotator papers skip this.
- **Cross-harness transfer tested** (RQ3), not assumed.
- **Honest, specific self-reported limitations** — the ~3% sampling rate, the
  terminal/tool-use domain restriction, the limited model-configuration count,
  and the RQ4 model substitution are all disclosed by the authors, not
  discovered by this appraisal.

---

## 3. Where to discount it

Ranked by how much they should change your reading.

### 3.1 The 65.7% / 4.5% split is a coding artifact, not a causal measurement

This is the most-quoted number in the paper and the weakest-supported one.

It comes from an **LLM open-coding pass over 240 sampled trajectories (~3% of
8,135 records)**, with Claude Sonnet 4.6 assigning mechanism labels. The human
validation is real but measures the **wrong thing for this purpose**: the
annotator checked that labels were "grounded in the recorded agent behavior" and
independently re-mapped the 238 labels to canonical modes. κ = 0.952 is
therefore **taxonomy-mapping agreement**, not validation that the original
mechanism attribution was causally correct.

So "65.7% of effectiveness comes from procedural anchoring" is more accurately:
*65.7% of a 3% sample was labeled procedural-anchoring by an LLM, and a human
agreed that label was consistently mapped.* The direction is credible. The
precision of the ratio is not.

**Compounding factor:** trajectories were truncated for coding to a **6,000-char
head + 12,000-char tail**. Mid-trajectory behavior is invisible to the coder.
Procedural anchoring shows up early (the agent orients and commits to a plan);
knowledge injection can occur anywhere. The truncation window plausibly biases
the split in exactly the observed direction. The paper does not test for this.

### 3.2 The headline effect is weak and the CI nearly touches zero

**+6.06 pp, 95% CI [+0.76, +11.36].** The lower bound is +0.76 — statistically
distinguishable from zero, but only just, and the interval spans a 15× range in
effect size. The interval is consistent with skills-over-workflow-memory being a
rounding error *or* being substantial. Any claim resting on "skills beat
equivalent unstructured context" should be held loosely.

### 3.3 RQ4's retrieval finding is self-undercutting — and this matters most to us

The abstract frames retrieval as "a significant bottleneck." The data is more
interesting than that:

| Pool size | Actual-use precision | Task success |
|---|---|---|
| 5 | 29.6% | 36.4% |
| 100 | 3.3% | 39.3% |

Precision collapsed by ~9×. **Success did not move** (and drifted slightly
*up*). The paper's own reading is that exact skill matching is "neither
sufficient nor strictly necessary."

For a ~400-skill marketplace this is the single most decision-relevant result
in the paper, and it points **against** the panic reading. Growing the pool
20× did not degrade task outcomes. What degraded was the *tidiness* of the
match — the agent stopped picking the designated skill and still did fine.

Two caveats before anyone relaxes: this was measured on SkillsBench tasks with
native task–skill annotations (well-specified tasks, a clean ground-truth
mapping), and "actual-use precision" presupposes there is one correct skill per
task — a framing that fits a benchmark better than it fits real workflows where
several skills legitimately apply.

### 3.4 RQ4 sits on different substrate than RQ1–RQ3

GPT-5.3-Codex became unavailable mid-study; RQ4 used **GPT-5.4** instead. The
authors handle this correctly and say so explicitly — RQ4 "is therefore
interpreted only through within-pairing comparisons." But the practical
consequence is that **the mechanism findings and the retrieval findings do not
compose**. You cannot chain "anchoring is 65.7% of the benefit" with "precision
falls to 3.3%" into a single quantitative story; they are measured on different
model substrate.

### 3.5 The skills studied are LLM-distilled, not human-authored

Skills were **distilled by Claude from 5 prior trajectories** on a fixed-budget
composition grid (5s0f … 0s5f). They are synthetic artifacts generated from a
handful of runs.

Our skills are hand-written, iterated over months, carry issue provenance, and
are cross-linked into a rule system. Generalizing from "LLM-distilled 5-trajectory
skill" to "curated marketplace skill" is an **inference, not a finding**. It is
a reasonable inference — but it is the load-bearing assumption under every use
of this paper as authoring guidance, including our rubric.

### 3.6 Domain restriction

Terminal- and tool-using benchmarks (Terminal-Bench 2.0, Terminal-Bench Pro,
SkillsBench). Authors state it "does not cover... long-horizon web interaction
or open-ended collaboration."

Our catalog is partially in-domain (CLI wrappers, git operations, scripted
checks) and partially out (multi-agent orchestration, review workflows,
long-running loops, documentation curation). Weight the rubric accordingly per
skill.

### 3.7 The decisive limitation for our purpose: quality was never a variable

**The study varies representation, annotation, harness, and pool size. It never
varies skill quality.** There is no high-quality vs low-quality arm.

Therefore the paper **cannot directly support any claim of the form "skills with
property P outperform skills without P."** Every quality indicator in our rubric
is derived by *inference* from a mechanism finding — "anchoring drives the
benefit, therefore skills should be anchor-shaped" — not from a measured
quality→outcome relationship.

This is the honest ceiling on the whole exercise and is restated at the top of
the rubric.

---

## 4. The three-paper picture

The papers form a chain rather than competing with each other.

| Paper | Question | Design | What it gives us |
|---|---|---|---|
| **SkillsBench** [2602.12670](https://arxiv.org/abs/2602.12670) (Feb 2026, rev. Jun; Li + 76 co-authors) | *Do* skills work? | 87 tasks / 8 domains, paired no-skill vs curated-skill, 18 model–harness configs | Effect size (33.9% → 50.5%, +16.6 pp); the only **explicit quality rubric**; ecosystem audit |
| **Demystifying** [2608.14036](https://arxiv.org/abs/2608.14036) (Aug 2026) | *Why*, and when not? | 3-arm contrastive, 8,135 trials, coded taxonomy | Mechanism (anchoring ≫ knowledge); failure taxonomy; retrieval scaling |
| **Skill Coverage** [2606.20659](https://arxiv.org/abs/2606.20659) (Jun 2026; Tan, Huang, Sun) | Was the skill *followed*? | Constraint extraction from NL → per-constraint pass/fail over trajectory | A **test-adequacy metric**; coverage measured at only **38.66–45.51%** |

### SkillsBench's quality rubric (Appendix A.3)

The one piece of directly-quality-relevant prior art. Four dimensions, 0–3 each,
**max 12**:

- **Completeness** — presence of required components
- **Clarity** — readability and organization
- **Specificity** — actionable vs vague guidance
- **Examples** — presence and quality of examples

Ecosystem mean **6.2/12 (SD 2.8)** over **47,150 audited skills**; benchmark
skills scored **10.1/12** (top quartile selected).

**Its own limitation mirrors ours:** quality was used as a *selection filter* to
remove variance, not manipulated as an independent variable. So even the paper
that scores quality does not demonstrate that its rubric predicts outcomes.
Nobody has yet run the study we would actually want.

Two SkillsBench structural findings *are* directly usable:

- **Focused beats exhaustive** — "Focused Skills with at most three modules
  outperform larger or exhaustive bundles."
- **Ecosystem skills are small** — median `SKILL.md` **~1.5k tokens**, median
  total under **2.5k tokens**.

### Skill Coverage is the most convertible to a deterministic check

Its two-stage method — extract behavioral constraints from natural-language
instructions, then assert each against the trajectory — is close to something we
could build on `evals.json`. Its finding that agents covered only **38.66–45.51%**
of extracted constraints, and that *strengthening the failed instructions*
recovered **16.0%** of tasks, is the most actionable single result across all
three papers.

---

## 5. A provenance warning from doing this appraisal

Search-engine AI summaries of these papers were **materially wrong** and would
have corrupted the rubric had they not been checked against primary sources:

| Claim in search summary | Primary source |
|---|---|
| SkillsBench: "84 tasks spanning 11 domains" | **87 tasks across 8 domains** |
| SkillsBench: "+16.2 pp" | **+16.6 pp** |
| The 12-point rubric was initially attributed from a summary alone | Real, but only confirmed by fetching Appendix A.3 directly |

Every figure in this appraisal and the rubric was taken from the arXiv abstract
or HTML body. **When extending this rubric with further studies, fetch the
paper.** Two of three summary-derived figures checked were wrong.

---

## 6. Bottom line

| Question | Answer |
|---|---|
| Is the study sound? | **Yes, for a mechanism study.** The 3-arm control is genuinely good design and the human-validation step is above field norm. |
| Is the headline effect strong? | **No.** +6.06 pp with CI [+0.76, +11.36] is weak and wide. |
| Is the 65.7%/4.5% split trustworthy? | **Directionally yes, numerically no.** ~3% LLM-coded sample, truncated inputs, validation measured mapping consistency rather than attribution validity. |
| Does it justify a quality rubric? | **Only by inference.** Quality was never a variable in any of the three papers. |
| What should change our behaviour? | The **failure taxonomy** (SC3: skills cause 10.0% misapplication failures vs <1% raw) and the **flat-success-under-pool-growth** result. Both are direct measurements, not coded inferences. |
| Confidence in the derived rubric | **Signal, not grade.** Sufficient to generate hypotheses about our catalog; insufficient to rank or gate skills. |

## Related

- [`rubric.md`](rubric.md) — the derived rubric and its per-dimension evidence grades
- [`README.md`](README.md) — how our existing rules already line up
- `docs/benchmarks/2026-07-context-engineering/rubric.md` — the frozen-rubric methodology this exercise copies
