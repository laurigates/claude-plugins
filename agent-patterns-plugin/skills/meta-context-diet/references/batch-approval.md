# meta-context-diet — Batch-Approval Mode for Large Surfaces

Moved verbatim from [SKILL.md](../SKILL.md) (Step 4). Open when the audit has
roughly 15 or more candidates.

#### Batch-approval mode for large surfaces

For a **large audit** — roughly **~15+ candidates**, where the per-candidate loop is ~15+ round-trips — prompting individually for every non-destructive disposition is needless friction. In that case, group the non-destructive candidates by disposition tier and offer **one tier-grouped multi-select `AskUserQuestion`** per tier: the user checks the candidates to approve in a single round-trip (e.g. "Path-scope these 9 rules", "Keep-but-lean these 6"). Put each candidate's file, size, and one-sentence justification in its option so the user can deselect any to hold back.

**Per-candidate confirmation stays mandatory for the destructive/ambiguous tier** — Drop, Consolidate-that-deletes, and Promote-to-skill are never batched, regardless of audit size. The invariant is unchanged: **no lossy or destructive edit to an always-loaded file lands without an explicit per-candidate confirmation.** Batch mode only fast-paths the dispositions that preserve the guidance in place.

For a **small audit** (fewer than ~15 candidates) the per-item loop is cheap — prompt each candidate individually and skip batch mode.
