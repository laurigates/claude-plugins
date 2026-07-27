# Context-Engineering Benchmark — 2026-07

*laurigates/claude-plugins measured against Anthropic's "The new rules of context
engineering for Claude 5 generation models" · 407 skills scanned · 10 units judged ×
2 independent judges · 150/150 evidence quotes verified*

## 1. Executive summary

**The corpus is not over-constrained — it is over-duplicated and over-resident.**
That is the opposite of what the post's headline shift (rules → judgment)
predicts for a marketplace written under the old rules, and it redirects the
whole remediation effort.

Channel J means across the judged sample:

| Dim | Shift | Mean median | Reading |
|---|---|---|---|
| **C1** Judgment over rules | rules → judgment | **3.9** | Healthy. Constraints are mostly load-bearing |
| **C2** Interface over examples | examples → interface | **3.86** | Healthy |
| **C6** Rich references | specs → references | **3.15** | Competent |
| **C3** Progressive disclosure | upfront → progressive | **2.9** | Weak |
| **C4** Single source of truth | repetition → SSOT | **2.65** | Weak |
| **C5** Always-loaded budget | (the >80% claim) | **1.67** | **The problem** |

Channel M agrees on the shape. Of 1,241 constraint markers across 407 skill
bodies, only **147 (11.8%)** sit next to a safety or irreversibility word — but
the judges scored C1 at 3.9 anyway, because the markers that remain are the ones
that matter. Nine skills are constraint-dense enough to flag; that is 2.2% of the
corpus, not a systemic problem.

The real cost is the surface paid on **every turn**: `CLAUDE.md` plus twelve
`.claude/rules/*.md` files with no `paths:` scope total **98,275 chars ≈ 24,600
tokens injected into every session**, and both judges scored that surface at 2 or
below on C5. Alongside it, one house mandate — the `## When to Use This Skill`
table required in every skill body — accounts for **280,610 chars (~70,000
tokens, 9.2% of all skill body mass)** for guidance the post locates in the
`description` field.

**What to do first**, in cost order rather than size order: scope or promote the
unscoped rules (every-turn cost), then dedupe (C4), then split large bodies (C3).
Cutting skill bodies is the *least* valuable of the three and the most tempting,
because it is where the big raw numbers are.

## 2. Method

Two channels, never blended.

**Channel M** — `evaluate-plugin/skills/evaluate-context-engineering/scripts/check-context-engineering.py`,
a deterministic proxy pass over the whole tree. Byte-identical across runs
(blake2b shingle hashing, no timestamps, no absolute paths); `--json | sha256sum`
is a valid regression check. Frozen output: `metrics.json`.

**Channel J** — anchored 1–5 judgments against `rubric.md`, frozen before any
judging, with every anchor traced to the post. Ten stratified units (see
`sample.md`), two independent judges each, median per dimension.

Anti-bias machinery, inherited from `docs/benchmarks/2026-07-marketplace-quality/`:

| Control | Result |
|---|---|
| Every score of 1/2/4/5 requires a verbatim quote, mechanically string-matched | **150/150 verified, 0 fabricated, 0 extreme scores without evidence** (`quote_check.py`) |
| Judges never see Channel M's numbers | Held — the scanner's thresholds are in the rubric's exclusion list |
| Judges never see the house standards under test | Partially held — see §6 |
| Two independent judges per unit | 10/10 units; **1 contested pair out of 55** (gap ≥ 2) |
| House criteria quarantined from the anchors | 10 items excluded (`rubric.md`) |

A/B blinding does not apply here — this is a single-repo audit, not a
head-to-head. `sample.md` records what replaces it.

## 3. Channel M — the whole tree

| Dim | Measure | Value |
|---|---|---|
| — | Skills scanned | 407 (406 marketplace + 1 repo-local) |
| — | Skill body mass | 3,035,131 chars ≈ **759K tokens** (median 6,766, on-demand) |
| **C1** | Constraint markers | 1,241 total, **147 safety-adjacent (11.8%)**, 9 dense skills |
| **C2** | Skills with `args` | 180; **only 46 (25.6%) enumerate their alternatives**; 7 fully opaque |
| **C2** | Fenced-block mass | 742,250 chars = **24.5% of all body mass** teaching by example |
| **C3** | Disclosure levels | **242 skills are a single flat file**; 145 have supporting files; 20 reach body→references→scripts |
| **C3** | `references/` directories | **0** — the corpus has 129 single `REFERENCE.md` sidecars, never the multi-file split the post asks for |
| **C3** | Large flat bodies (>10K chars, no supporting file) | 53 |
| **C4** | Cross-file overlap pairs | 11 above threshold; **top pair shares 824 eight-word shingles (0.482 containment)** |
| **C4** | `## When to Use This Skill` | 407/407 skills, 280,610 chars ≈ **70K tokens (9.2% of body mass)** |
| **C4** | `## Agentic Optimizations` | 257 skills, 131,943 chars ≈ 33K tokens (4.3%) |
| **C5** | **Always-loaded surface** | `CLAUDE.md` 17,759 + 12 unscoped rules 80,516 = **98,275 chars ≈ 24,600 tokens every turn** |
| **C5** | Unscoped rules that read procedural | 7 of 12 |
| **C6** | Skills bundling scripts | 54; **108 carry ≥3 multi-line shell blocks with no script** |

Full issue list: 186 (`C1` 9, `C2` 9, `C3` 53, `C5` 7, `C6` 108).

## 4. Channel J — per-unit medians

| Unit | C1 | C2 | C3 | C4 | C5 | C6 | mean |
|---|---|---|---|---|---|---|---|
| `testing-plugin/test-tier-selection` | 2 | 3 | 3 | 2 | n/a | 2 | **2.4** |
| `.claude/rules/agent-coworker-detection.md` | 4.5 | n/a | 2 | 2 | 2 | 2.5 | **2.6** |
| `.claude/rules/terminology.md` | 4 | n/a | 2 | 4 | **1** | 3 | **2.8** |
| `CLAUDE.md` | 3 | n/a | 3.5 | 2 | 2 | 3.5 | **2.8** |
| `configure-plugin/configure-claude-plugins` | 4 | 4 | 2 | 2 | n/a | 2 | **2.8** |
| `agent-patterns-plugin/meta-context-diet` | 4.5 | 4 | 2 | 4* | n/a | 2 | **3.3** |
| `git-plugin/git-commit` | 3.5 | 4 | 4 | 2 | n/a | 3.5 | **3.4** |
| `configure-plugin/configure-security` | 3.5 | 4 | 4 | 3 | n/a | 4 | **3.7** |
| `comfyui-plugin/comfy-node` | 5 | 4 | 3.5 | 2 | n/a | 4.5 | **3.8** |
| `agent-patterns-plugin/parallel-agent-dispatch` | 5 | 4 | 3 | 3.5 | n/a | 4.5 | **4.0** |

`*` the one contested pair (judges split 3 vs 5 on `meta-context-diet` C4).

The control (`configure-security`, chosen because Channel M showed it clean)
scored 3.7 — the rubric can score a good artifact well, so the low scores
elsewhere are not a floor effect.

## 5. Ranked findings

Ranked by **always-loaded cost × frequency**, not by size. Each is labelled
**proven** (a judged, quoted finding) or **proxy-only** (Channel M alone) so the
ablation follow-up has a queue.

### F1 — The always-loaded surface carries four procedures and a glossary · proven · ~24,600 tok/session

Both judges scored `CLAUDE.md` C5 = 2 and `terminology.md` C5 = 1. The judged
verdicts:

- **`CLAUDE.md`**: promote *Creating New Skills*, *Creating User-Invocable Skills*,
  *Plugin Lifecycle*, and *Development Workflow* into an authoring skill, leaving
  one named reference line each. These are procedures with clear triggers; they
  do not need to be resident when the user is debugging a hook.
- **`terminology.md`** (8,502 chars every turn): a Claude 5 model already uses
  *happy path*, *dry-run*, *extract*, and *staging* correctly. Keep the entries
  carrying house-specific meaning and the ownership pointers; move the rest
  off the always-loaded surface.
- **`agent-coworker-detection.md`** (15,865 chars every turn, the largest): both
  judges scored C3 = 2 and C4 = 2 — it inlines six full signal implementations
  that `/git:coworker-check` and its `detect-coworkers.sh` already own and test.

### F2 — A house mandate costs ~70K tokens for what the description already carries · proven · 9.2% of body mass

`skill-quality.md` requires a `## When to Use This Skill` table in every skill
body; all 407 comply, at 280,610 chars. The post puts when-to-use in the
`description`. This is **not** a blanket delete: the judges repeatedly credited
the table where it disambiguates *sibling* skills that could both match. The
resolution is to demote it from mandatory to recommended-where-it-disambiguates.
`## Agentic Optimizations` (257 skills, ~33K tokens) has no published basis at
all and should become optional.

### F3 — Two skills in different plugins share half their content · proven · C4 = 2

`comfyui-plugin/comfy-node` and `foundryvtt-plugin/foundryvtt-module` share 824
eight-word shingles (0.482 containment) — a common gitops repo-adoption
procedure copied into both. The judge found **the copies have already drifted**.
Per `.claude/rules/skill-consolidation.md`, a cross-plugin fix is a
name-reference to one designated owner, never a shared `REFERENCE.md`.
`git-commit` scored C4 = 2 for the same reason at smaller scale: it restates the
conventional-commit type table and the Fixes/Closes/Refs keywords that
`.claude/rules/conventional-commits.md` already owns, *and links to*.

### F4 — Progressive disclosure is two-level, never multi-file · proven + proxy · C3 = 2.9

242 of 407 skills are a single flat file; the corpus has **129 `REFERENCE.md`
sidecars and zero `references/` directories**. The post asks to "divide it into
many files and split them out". The judges converged on the same fix
independently for three different units: split the single sidecar by the path
that needs it, so a `--type secrets` run loads only secret-detection templates.
`agent-patterns-plugin/parallel-agent-dispatch` is the sharpest case — at 26,024
chars it is **already failing the house 26,000-char ceiling** (a pre-existing
lint ERROR, not introduced here) and its rare worktree-hazard case studies belong
in separately-loadable files.

### F5 — 108 skills describe mechanical work in prose with no script · proxy-only · C6

Channel M's largest issue class. C6's judged mean is 3.15, so this is a real but
non-urgent gap — and the counter-finding below shows the proxy overcounts.

### F6 — Counter-findings: what earns its tokens · proven

A report with no counter-findings has an agreement bias. Every judged unit
produced one; the pattern is consistent — **the text that earns its tokens is the
text that names a non-obvious, expensive failure and says why**:

- `agent-coworker-detection.md`: the asymmetry that committed work survives in
  the reflog while untracked work does not. Judged a true every-turn invariant —
  *"no skill trigger would reliably fire on it before the damage is done"*. Keep
  it always-loaded even while cutting the six inline implementations around it.
- `CLAUDE.md`: the Blueprint constrained-dogfooding section — the disabled-task
  reasons, the consumer-only autonomy-level-3 caveat, and the deliberately
  non-matching `blueprint` commit scope are traps a model would re-derive wrongly.
- `configure-claude-plugins`: the two visually-similar marketplace suffix forms,
  one of which fails silently.
- `git-commit`: the quoted-heredoc escaping warning.
- `parallel-agent-dispatch`: the loud-failure contract.

Note the tension with F5: `configure-security` earned its C6 = 4 precisely
*because* its bundled script "runs without ever entering context" — the same
property that makes 108 script-less skills a finding makes the scripted ones
cheap. Verify before cutting: a prose block that is *documentation of a
procedure a human runs* is not the same as one the model re-derives.

## 6. Bias, limits, and what this run does not establish

Read this before quoting any number.

- **Leakage is real and only partly controlled.** This repo injects `CLAUDE.md`
  and the twelve unscoped rules into *every* agent's context, and
  `skill-quality.md` is path-scoped to `**/SKILL.md` so it can attach when a
  judge opens a skill. All 20 judgments self-reported; **0 of 20 reported that
  house standards influenced a score**. That is a self-report, not a measurement.
- **n=2 judges.** A median of two cannot separate agreement from correlation.
  Only 1 of 55 pairs was contested, which is *either* strong convergence *or*
  correlated judges — this design cannot tell you which.
- **397 of 407 skills were never judged.** Every long-tail claim here is a
  Channel M claim, and Channel M's thresholds are proxies, not verdicts.
- **F3 is one-sided by construction.** `foundryvtt-module` was not judged, so the
  finding establishes that duplication exists, not which copy should survive.
- **Nothing is ablated.** No finding has been tested by cutting the content and
  re-measuring. The post's own claim is an ablation result; ours are judgments.
  Only 1 of 407 skills currently has an `evals.json`, which is what blocks the
  follow-up.
- **Two rubric anchors rest on paraphrase**, not verbatim quotation — the post was
  retrieved through a summarising fetch. `rubric.md` § Source & provenance marks
  which.
- **The post's fifth shift (automatic memory) is unscored.** It is a claim about
  harness behaviour, not an artifact property, and needs verification against the
  installed Claude Code version before it changes how `session-distill` writes.

## 7. What happens next

This run measures and recommends. It applies nothing — each cut lands as its own
reviewable PR.

| Step | Owner |
|---|---|
| Reconcile the house mandates (F2) | `.claude/rules/context-engineering.md` |
| Migrate always-loaded candidates (F1) | `agent-patterns-plugin:meta-context-diet` — it carries the per-candidate confirmation gate |
| Designate an owner for the duplicated procedure (F3) | `.claude/rules/skill-consolidation.md` — cross-plugin means name-reference |
| Re-run on the next model release | `/evaluate:context-engineering` |
| Turn judgments into measurements | Author `evals.json` for the top-ranked units, then ablate (`.claude/rules/skill-evaluation.md` Tier 2) |

## 8. Reproducing

```bash
python3 scripts/check-context-engineering.py --json > metrics.json   # Channel M
python3 docs/benchmarks/2026-07-context-engineering/quote_check.py   # evidence gate
python3 docs/benchmarks/2026-07-context-engineering/synthesize.py    # medians
```

Unlike the prior benchmark — whose reproduction scripts ran from a scratchpad and
were never committed — `quote_check.py` and `synthesize.py` are in this
directory. `judgments/*.json` is the complete audit trail for every number above.
