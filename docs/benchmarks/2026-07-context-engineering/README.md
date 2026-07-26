# Context-Engineering Benchmark — 2026-07

How this marketplace measures against Anthropic's
[**The new rules of context engineering for Claude 5 generation models**](https://claude.com/blog/the-new-rules-of-context-engineering-for-claude-5-generation-models)
(retrieved 2026-07-26).

Start with **[context-engineering-report.md](context-engineering-report.md)** —
executive summary, both channels, ranked findings, and the bias section.

## Method in one paragraph

Two channels, never blended. **Channel M**: a deterministic proxy pass over all
407 skills plus the always-loaded surface (`metrics.json`), byte-identical across
runs. **Channel J**: anchored 1–5 judgments on six dimensions (C1–C6) derived
from the post and frozen in `rubric.md` *before* any judging, over 10 stratified
units with 2 independent judges each. Every score of 1/2/4/5 required a verbatim
quote, mechanically string-matched against the file — **150/150 verified, 0
fabricated**. The house conventions this benchmark exists to test (the mandatory
`When to Use` / `Agentic Optimizations` tables, the char ceilings, the
`REFERENCE.md` filename) are quarantined in an exclusion list so they cannot also
be the yardstick.

**Headline:** the corpus is *not* over-constrained (C1 = 3.9). It is
over-duplicated (C4 = 2.65) and over-resident (C5 = 1.67) — ~24,600 tokens of
`CLAUDE.md` + unscoped rules are injected into every session.

## Files

| File | What it is |
|---|---|
| `context-engineering-report.md` | The report — findings, counter-findings, bias section |
| `rubric.md` | Frozen C1–C6 anchors, provenance, house-criteria exclusion list |
| `sample.md` | Which 10 units were judged, why, and what the sample does not cover |
| `metrics.json` | Channel M output (byte-deterministic) |
| `synthesis.json` | Unblinded medians, contested pairs, leakage self-reports |
| `judgments/*.json` | All 20 raw judge outputs with evidence quotes |
| `quote_check.py` | The evidence gate — verifies every quote against the file on disk |
| `synthesize.py` | Judgments → `synthesis.json` |

## Re-running

The scanner is wired for continuous use, not just this snapshot:

```bash
just lint-context-engineering          # Channel M card
/evaluate:context-engineering --judge  # both channels, scoped
```

The C5 ratchet (`--strict`) is the one part that gates CI: it errors when the
always-loaded surface exceeds its declared budget, so the every-session cost
cannot grow silently. Everything else is report-only.
