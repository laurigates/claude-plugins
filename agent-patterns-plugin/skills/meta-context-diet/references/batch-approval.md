# meta-context-diet — Batch-Approval Mode for Large Surfaces

Moved verbatim from [SKILL.md](../SKILL.md) (Step 4). Open when the audit has
roughly 15 or more candidates, when building a candidate's question, or for why
the two disposition classes confirm differently.

#### The per-candidate question

Each candidate's `AskUserQuestion` has at most 4 options: the recommended
disposition first, then the 3 likeliest alternates from Keep / Lean /
Lean-to-pointer / Path-scope / Promote-to-skill / Consolidate / Drop / Skip. The
built-in "Other" answer reaches the rest.

#### Why the tiers confirm differently

The confirmation shape depends on **how lossy the disposition is**, not on convenience:

| Disposition class | Confirmation | Why |
|---|---|---|
| **Non-destructive** — Keep-invariant, Keep-but-lean that keeps the invariant in the rule, Path-scope | Batchable (see [Batch-approval mode](#batch-approval-mode-for-large-surfaces)) | The guidance survives in place — leaning trims explanation, path-scoping only narrows *when* it loads. Nothing is removed from the always-loaded surface's meaning. |
| **Destructive / ambiguous** — Drop, Consolidate-that-deletes, Promote-to-skill, Lean-to-pointer (a `docs/` move that leaves only a pointer) | **One candidate, one question** — up to 4 single-candidate questions may share one `AskUserQuestion` call | Each removes guidance from an always-loaded file: Drop deletes it, Consolidate-that-deletes and Lean-to-pointer replace it with a pointer, Promote-to-skill moves the body off the every-turn surface. A wrong call degrades every downstream turn, so the user confirms each individually. |

#### Batch-approval mode for large surfaces

For a **large audit** — roughly **~15+ candidates**, where the per-candidate loop is ~15+ round-trips — prompting individually for every non-destructive disposition is needless friction. In that case, group the non-destructive candidates by disposition tier and offer **one tier-grouped multi-select `AskUserQuestion`** per tier: the user checks the candidates to approve in a single round-trip (e.g. "Path-scope these 9 rules", "Keep-but-lean these 6"). Put each candidate's file, size, and one-sentence justification in its option so the user can deselect any to hold back.

**Fit each tier to the 4-option cap.** `AskUserQuestion` takes at most 4 options per question and at most 4 questions per call, so a tier with 5+ candidates cannot be one multi-select. Split it into questions of at most 4 options each and send them together in **one** `AskUserQuestion` call — a 9-candidate Path-scope tier becomes three questions (4 + 4 + 1) in one round-trip. A tier larger than 16 candidates takes a second call. Keep each question to one tier so an approval never mixes dispositions.

**Per-candidate confirmation stays mandatory for the destructive/ambiguous tier** — Drop, Consolidate-that-deletes, Promote-to-skill, and Lean-to-pointer (a `docs/` move that leaves only a pointer in the rule — see [consumer-sweep.md](consumer-sweep.md)) are never batched, regardless of audit size. A Keep-but-lean candidate belongs in the batchable tier only when the rule keeps its invariant. The invariant is unchanged: **no lossy or destructive edit to an always-loaded file lands without an explicit per-candidate confirmation.** Batch mode only fast-paths the dispositions that preserve the guidance in place. Several single-candidate questions sent together in one `AskUserQuestion` call still count as per-candidate confirmation — each candidate gets its own question and its own answer — so the destructive tier can share a round-trip without being batched into one multi-select (#2836).

For a **small audit** (fewer than ~15 candidates) the per-item loop is cheap — prompt each candidate individually and skip batch mode.
