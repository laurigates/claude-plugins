# Marketplace Quality Benchmark — 2026-07

Head-to-head quality benchmark of **laurigates/claude-plugins** vs
**anthropics/claude-plugins-official** (pinned @ `4cd126ba`, 2026-07-02).

Start with **[marketplace-quality-comparison.md](marketplace-quality-comparison.md)** —
executive summary, two-channel scoreboard, pair capsules, bias audit, and ranked
adopt/consider/skip takeaways.

## Method in one paragraph

Two channels, never blended: **Channel M** — a deterministic Python pass over both
full trees (`metrics.json`); **Channel J** — anchored 1–5 judgments, median of two
independent judges per unit. Nine overlap pairs were staged into anonymous
`side-A`/`side-B` directories and judged **blind** on six authoring-quality
dimensions (B1–B6); marketplace infrastructure was judged **open-book** on six
dimensions (A1–A6). All scored anchors were frozen before judging from published
Anthropic guidance plus the official repo's own skill-creator references
(`rubric.md`, including a 12-item house-criteria exclusion list). Every extreme
score required a verbatim quote, mechanically string-matched against staged files
(231/231 verified, 0 fabricated); the highest-stakes findings were re-judged by
adversarial refuters with a symmetric-standard check. Identity leakage and A/B
position bias were measured and are published in the report's §6 — read it before
quoting any single number.

## Files

| File | What it is |
|---|---|
| `marketplace-quality-comparison.md` | The report (all numeric tables generated from `synthesis.json`) |
| `rubric.md` | Frozen scoring anchors + provenance + house-criteria exclusion list |
| `synthesis.json` | Unblinded medians, verdicts, refuter corrections, bias audit |
| `metrics.json` | Channel M mechanical metrics over both trees (byte-deterministic) |
| `refutations.json` | Adversarial refuter verdicts for the 10 selected findings |
| `tier_c.json` | Descriptive (unscored) catalog asymmetries |
| `judgments/*.json` | All 20 raw judge outputs (18 blind pair + 2 Tier-A), with evidence quotes |

Reproduction scripts (`stage_pairs.py`, `compute_metrics.py`, `quote_check.py`,
`synthesize.py`, `build_report.py`) ran from a session scratchpad and are not
committed; the judgments + synthesis here are the complete audit trail for every
number in the report.
