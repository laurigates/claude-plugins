# story-audit — Step 6 Artifact Sections

What each section of the [audit template](../REFERENCE.md#audit-template) holds.

1. **Summary** — counts and the headline number (e.g. "8 PRD requirements drift; 3 critical capability areas have zero tests")
2. **Capability map** — Agent 1's output, grouped by area
3. **Story inventory** — explicit (PRD) + candidate (code-only) lists
4. **Drift report** — table with the four-status enum from Step 2
5. **Coverage matrix** — story × tests with confidence column
6. **Tiered gap analysis** — Tier 1 → 5 with one-line "why this matters" per tier
7. **Bugs surfaced by audit** (only if Step 5 found any)
