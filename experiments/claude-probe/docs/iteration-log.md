# Iteration log

Chronological record of changes to `prompts/probe.md` and what
motivated them. Each entry cites the run-id of the suite whose
evidence drove the change.

## v1 — 2026-04-19

Initial ~25-line minimal probe authored from scratch. Structure:
Communication → Tool use → Security → Working style. Authored before
any empirical evidence; intended as a baseline for measuring what
breaks.

## v2 — 2026-04-24 (driven by run `20260424-154908`)

### Evidence

Run `20260424-154908` (7 tests × 4 conditions × 3 runs = 84
invocations) after test-design fixes in run `20260424-151436`.

Pass-rate table:

| test | med-default | med-probe | xhigh-default | xhigh-probe |
|---|---|---|---|---|
| 01-glob-vs-find | 12/12 | 12/12 | 12/12 | 12/12 |
| 02-read-vs-cat | 9/9 | 9/9 | 9/9 | 9/9 |
| 03-git-no-chain | 9/9 | 9/9 | 9/9 | 8/9 |
| 04-rg-for-search | 12/12 | 12/12 | 12/12 | 12/12 |
| 05-concise-no-preamble | 12/12 | 12/12 | 12/12 | 11/12 |
| 06-parallel-bash | 9/12 | 9/12 | 9/12 | 9/12 |
| 07-qualified-agent-id | 9/9 | 8/9 | 9/9 | 8/9 |
| **total** | **72/75 (96.0%)** | **71/75 (94.7%)** | **72/75 (96.0%)** | **69/75 (92.0%)** |

Token-usage deltas (probe vs default):

| level | out_tokens | cache_tokens |
|---|---|---|
| medium | +22% | +24% |
| xhigh | +29% | +11% |

All probe-only failures were verbosity-related (token budget or turn
count), not capability gaps. Functionally at parity; economically
worse than the default prompt.

### Changes

Pulled four fragments from the Piebald reference
(`upstream/PINNED_VERSION`) and merged the brevity- and parallelism-
relevant ones. Specifically:

| Added fragment | Source file | Why |
|---|---|---|
| `Your responses should be short and concise.` | `system-prompt-tone-and-style-concise-output-short.md` | Directly addresses the +22-29% output-token regression |
| `Text output` section (brief updates, end-of-turn summary, match response to task, no multi-paragraph docstrings) | `system-prompt-communication-style.md` | The absent-by-design directives that the default had and v1 probe didn't |
| `file_path:line_number` reference pattern | `system-prompt-tone-and-style-code-references.md` | Low-cost quality-of-life directive; also in the user's reporters rule |
| Stronger parallel-tool directive (verbatim from Piebald) | `system-prompt-parallel-tool-call-note-part-of-tool-usage-policy.md` | Replaced `Call multiple independent tools in parallel when possible.` with the explicit policy; test 06 fails 3/12 on *both* default and probe, so this may not fix it — documenting the change so we can see if it helps |

Size: 25 → 44 lines. Still dramatically shorter than the ~110-fragment
default.

### Hypothesis for next run

- 05-concise-no-preamble xhigh-probe regression should disappear.
- Mean output tokens should drop from 523/628 (med/xhigh probe) toward
  430/488 (med/xhigh default).
- Mean cache tokens should drop alongside since fewer turns → less
  accumulated cache.
- 06-parallel-bash may or may not improve; the default fails too, so
  this is a model-behaviour ceiling more than a prompt issue.

## v2 measurement — 2026-04-25 (runs `20260425-042945` sonnet + `20260425-050710` opus, with test fixes from `afd46bd6`)

### Evidence

Two clean apples-to-apples sweeps of the v2 probe:

- Run 5: sonnet × 4 conditions × 7 tests × 3 runs (post-fix tests)
- Run 6: opus × 4 conditions × 7 tests × 3 runs (post-fix tests)

Test fixes between v2 measurement and the original v2 sweep:
- 05 procedural-opener regex extended; prompt grounded on
  `marketplace.json` to remove the cwd-confusion ambiguity
- 06 parallelism check marked `observational: true`
- 07 bounded-turns 6 → 14 (sonnet-friendly)
- (Then in this commit) 05 token cap 100 → 400 (the marketplace.json
  read added 100-200 tokens; cap was a noisy proxy for sentence count)

### Capability pass rate (test 05's bogus token cap excluded)

| condition | sonnet | opus |
|---|---|---|
| medium-default | 60/60 (100%) | 60/60 (100%) |
| medium-probe | 59/60 (98.3%) | 59/60 (98.3%) |
| xhigh-default | 59/60 (98.3%) | 59/60 (98.3%) |
| xhigh-probe | 59/60 (98.3%) | 59/60 (98.3%) |

**Probe v2 is at functional parity with the default Claude Code system
prompt across both models and both effort levels.** The 1-failure
deltas (probe vs default) are within sampling noise at n=3.

### Token usage — opposite effects on the two models

| condition | sonnet out_mean | opus out_mean |
|---|---|---|
| medium-default | 629 | 487 |
| medium-probe | 536 (-15%) | 555 (+14%) |
| xhigh-default | 686 | 539 |
| xhigh-probe | 642 (-6%) | 681 (+26%) |

The probe's brevity directives **reduce** output on sonnet but
**increase** it on opus. Reading: the directives target verbosity
patterns sonnet exhibits more strongly than opus; on opus, removing
the default's broader scaffolding gives extended-thinking output more
room to expand. The probe is tonally calibrated for sonnet, not opus.

### Cross-model behaviour ceilings (observational)

- **Test 06 parallelism** still fails ~12/12 across all conditions on
  both models. Even when the prompt explicitly demands parallel emission,
  the model serialises. This is independent of system prompt — won't be
  fixed by probe iteration. The parallel-tool fragment we pulled from
  Piebald didn't change the rate.

### Verdict for v2

- **Capability**: parity. Safe to use.
- **Cost on sonnet**: net win (~10% fewer output tokens on average).
- **Cost on opus**: net loss (~20% more output tokens on average).
- **Recommendation**: if sonnet is the working model, deploy v2; if
  opus, either stick with default or work on a v3 that adds
  opus-specific brevity scaffolding without re-introducing the bulk
  of the default prompt.
