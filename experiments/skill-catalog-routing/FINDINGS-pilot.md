# Pilot findings

Run `pilot` — haiku C1 (names only) vs C4 (full descriptions), 20-task subset
(r01–r10, n01–n06, z01–z04), 3 runs each; plus a 20-call opus-C4 gold-check.
140 transcripts, **0 parse failures, 0 false triggers**.

## Results

| arm | top-1 | near-miss | false-trigger | abstain | catalog tokens |
|-----|-------|-----------|---------------|---------|----------------|
| haiku-C1 (names only) | 0.98 | 0.94 | 0.00 | 1.00 | 27.3k |
| haiku-C4 (full desc)  | 1.00 | 1.00 | 0.00 | 1.00 | 43.9k |
| **opus-C4 (gold-check)** | **1.00** | **1.00** | 0.00 | 1.00 | 43.9k |

Measured token ladder (real input tokens, over the 23.2k base): names +4.2k,
short +7.2k, medium +11.0k, full +20.7k.

## What the pilot establishes

1. **The instrument is valid.** opus-C4 routed all 16 pilot route tasks to their
   gold (100%) — an independent strong-model confirmation that the gold labels
   are correct. The task set has 0 lexical leakage (`name_overlap = 0.0`), the
   JSON contract held on every call (0 parse fails), and abstention was perfect
   (0 false triggers on the `NONE` tasks). Isolation is clean: the built-in
   ~22k skill listing is absent (base 23.2k, full catalog 43.9k).

2. **Skill NAMES carry almost all of the routing signal.** Names-only (C1)
   already routes at 0.98 top-1 / 0.94 near-miss on haiku. Adding the entire
   description corpus (+16.5k tokens, C1→C4) buys **+0.02 top-1 and +0.06
   near-miss**. The one place a description actually changed the answer was the
   deliberately-ambiguous pair `git-commit` vs `git-commit-workflow` (n01): with
   names alone haiku picked the wrong sibling 1/3 of the time; with descriptions
   it was always right. That is the shape of where descriptions earn their keep —
   near-miss discrimination between same-family skills — and nowhere else in the
   pilot.

## What this means for the pre-registered gate

The gate was: *"the instrument MUST separate C1 from C4; if it doesn't, the task
set is leaky — fix before spending more."* The separation is minimal (+0.02
top-1), but the cause is **not** a leaky/miscalibrated task set (leakage 0, golds
verified). The cause is a genuine property of the corpus: the routing ids are
`<plugin>/<skill-slug>` and the slugs are semantically rich
(`macos-performance-triage`, `helm-release-recovery`, `cargo-machete`…), so a
model maps symptom→name by meaning without needing the description. **"Names are
near-sufficient for routing" is itself the headline finding**, and it directly
supports the "could shorter be better?" hypothesis: most of the 20.7k-token
catalog is redundant for discovery given the names.

## Caveats

- **Small subset, two extremes only.** 20 tasks (near-miss = 6 tasks × 3 runs =
  18 rows); C2/C3 and C0 were not run, and only haiku. The description effect is
  near the ceiling, so the current task set has little dynamic range to resolve a
  *length* curve — C1–C4 would likely all cluster near 1.00.
- **C0 (no catalog) is the untested, most decision-relevant arm.** The smoke test
  showed haiku-C0 could not emit a valid id without a catalog (answered NONE), so
  C4−C0 is expected to be large. That would complete the story: the catalog's
  value is real and lives **in the names**, while the descriptions add a thin
  near-miss margin on top.

## Recommended next step

The value of a full 5-arm × 3-model sweep on the *current* tasks is limited: the
accuracy curve would be nearly flat near the ceiling. Two better options:

- **(A) Cheap, high-information:** run **C0 + C1 + C4 across all three models**
  (haiku/sonnet/opus). This quantifies the *true* catalog value (C4−C0), confirms
  names-carry-most-signal across the capability range, and measures whether weak
  models lean on descriptions more than strong ones — without paying for a flat
  C2/C3 middle.
- **(B) Restore dynamic range first:** harden the near-miss set with genuinely
  **name-opaque** discriminators (pairs whose slugs don't reveal the difference),
  then run the full ladder so C2/C3 can actually separate. This is the only way
  to draw a real "how short is too short" curve.

Both are sound; (A) is the fast path to the headline numbers, (B) is needed for a
precise length threshold.
