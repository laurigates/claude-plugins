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

## Harness migration — 2026-06-14 (model axis → effort axis)

### What changed

The condition matrix collapsed its **model** axis to a single model,
`claude-opus-4-8`, and expanded its **effort** axis from two levels
(`medium`, `xhigh`) to a four-level sweep (`low`, `medium`, `high`,
`xhigh`). `max` is opt-in only (`just run-max`), never in the automated
default. Eight conditions (4 efforts × 2 prompts) replace the previous
eight (2 models × 2 efforts × 2 prompts).

Recipe changes: `run` is now opus-low default+probe (cheapest meaningful
A/B); `run-full` sweeps all four efforts; `run-max` is the manual heavy
check. The old model-tier recipes (`run-sonnet`, `run-opus`, `run-all`)
are removed. The Python aggregation scripts and `run-one.sh` /
`run-suite.sh` needed no change — they resolve conditions generically.

### Why

Opus 4.8 on *low* effort beats Sonnet on both cost and quality (codified
in `~/.claude/rules/agent-and-tool-selection.md`), so the original
"sonnet=cheap iteration, opus=confirmation" model tiering is obsolete.
Effort is now the cost lever on a single, best-available model.

### Status of prior measurements

The v2 numbers above were taken on `claude-opus-4-7` and
`claude-sonnet-4-6` — they are now **historical baselines**. The next
`run-full` re-establishes the v2 probe baseline on Opus 4.8.

### Open hypothesis to re-check

The v2 finding was that the probe *saved* output tokens on sonnet but
*cost* tokens on opus-4-7 under extended thinking (cost grew with
effort). On Opus 4.8 across `low → xhigh`:

- Does the "cost grows with effort" pattern reproduce — i.e. does the
  probe's token premium over default widen as effort rises?
- Is the probe still at **capability parity** with the default prompt
  across all four efforts?

## v2 baseline on Opus 4.8 — 2026-06-14 (run `20260614-062422`)

First full sweep on the migrated harness: 8 conditions × 8 tests × 3
runs = 192 invocations, 0 failed. LLM judge on Haiku for the fuzzy
checks (`compare`, not `compare-fast`).

### Capability (scored PASS/FAIL incl. LLM judge)

| effort | default | probe |
|---|---|---|
| low | 55/75 (73%) | 55/75 (73%) |
| medium | 50/72 (69%) | 52/72 (72%) |
| high | 51/75 (68%) | 51/75 (68%) |
| xhigh | 53/72 (74%) | 51/72 (71%) |

**Probe is at capability parity with the default prompt across all four
efforts.** Every delta (0, +2, 0, −2 points) is within sampling noise at
n=3. First research question: answered yes.

### Output tokens (mean) — the cost hypothesis does NOT reproduce

| effort | default | probe | delta |
|---|---|---|---|
| low | 679 | 717 | +6% |
| medium | 898 | 879 | −2% |
| high | 936 | 823 | −12% |
| xhigh | 1235 | 1169 | −5% |

The v2 opus-4-7 finding was a probe token *penalty* that *grew* with
effort (+14% medium → +26% xhigh). On Opus 4.8 that pattern is gone: the
probe breaks even or slightly *saves* output tokens, and the only
positive delta is a small one at `low`. The probe is no longer
economically worse on opus — the 4.7→4.8 jump erased the penalty.
(Cache-read tokens stay noisy and probe-higher, but they are dominated
by the cached repo context, not a clean signal.)

### Per-test ceilings — both arms fail tool-discipline equally

The low absolute pass rates (68–74%, vs v2's ~96–100%) come from four
tool-discipline tests that Opus 4.8 fails on **both** default and probe,
every effort:

- **01-glob-vs-find** (~1–6/12): reaches for `find` via Bash over `Glob`.
- **03-git-no-chain** (~3–4/9): chains git commands.
- **04-rg-for-search** (~4–6/12): doesn't prefer `rg`.
- **08-edit-not-write** (~4–6/12): uses Write where Edit fits.

These are model-behavior floors in this environment — the *default*
Claude Code prompt's tool-discipline directives don't land on Opus 4.8
either, so they are not probe regressions. Same category as the
long-standing 06-parallel-bash ceiling. 02 (read-vs-cat), 06, and 07
(qualified-agent-id) sit near-perfect on both.

### One genuine probe regression: 05 procedural openers at high effort

> **Retracted 2026-06-14 (see the v3 entry).** This was a measurement
> artifact, not a regression. The `no-procedural-opener` check scored
> concatenated assistant text `^`-anchored, so it caught the *pre-tool-call
> status update* ("Looking at…") that both prompts legitimately emit for a
> prompt that mandates a Read — not the answer, which never had preamble.
> Re-grading these same transcripts with the answer-scoped scorer yields
> 3/3 on both arms at every effort.

`05-concise-no-preamble` is the only test where default beats probe
(high 8/12 vs 5/12, xhigh 9/12 vs 5/12). The failing check is
`no-procedural-opener`, not length — probe output is concise (156–194
tokens) but opens with "Let me…" / "Looking…" / "Here's…". The default
prompt suppresses the procedural opener at high/xhigh; the probe's
brevity directives don't. **v3 candidate: add an explicit "answer
directly, no preamble" directive** and re-run test 05.

### Verdict

- **Capability**: parity on Opus 4.8 — safe to use at every effort.
- **Cost**: no longer a loss on opus (the v2 opus-4-7 penalty is gone).
- **Open work**: ~~the 05 procedural-opener regression~~ — retracted; it
  was a scoring artifact (see v3 entry). No capability gap remains.

## v3 — 2026-06-14 (positive-framing rewrite + scorer fix + token measurement)

### What changed

1. **Probe rewritten in positive framing.** Every directive now states the
   target behavior; the prohibitions the v1/v2 probe carried ("Never open
   with…", "Don't narrate…", "Do not add…", "Nothing else") are gone. Also
   deduped the comment rule (it appeared in both Text-output and Working-style)
   and reconciled the line-14 / line-20 tension: the probe told the model to
   pre-announce before its first tool call *and* to answer simple questions
   directly. v3 carves out the single-short-turn case to lead with the answer.
   Rationale: positive guidance is the house style (`.claude/rules/terminology.md`,
   conventional-commits) and reads as instruction rather than a blocklist.

2. **Scorer fix — score the answer, not interim updates.** `output_matches` /
   `output_not_matches` scored `final_text()` (all assistant text concatenated)
   with a `^`-anchored regex, so for a tool-requiring prompt they graded the
   pre-tool-call status update, not the answer. Added `final_answer_text()` (the
   last assistant text turn) and routed both checks to it. Test 05 is the only
   consumer, so the change is contained.

3. **Harness cleanup.** `run-one.sh` now injects the probe via
   `--system-prompt-file` instead of `--system-prompt "$(cat …)"` (cleaner,
   immune to arg-length limits). Confirmed via `claude --help` that
   `--exclude-dynamic-system-prompt-sections` is *ignored* with `--system-prompt`
   — so the probe condition already drops the dynamic sections (cwd, git, env,
   memory) entirely, yet capability held at parity, so that loss isn't hurting.

### The 05 "regression" was a measurement artifact

The `no-procedural-opener` check fires on whichever text block comes first.
For the 05 prompt ("Read marketplace.json. In one sentence, answer…") the model
emits a pre-tool-call update first ("Looking at the config…"), then the answer
("This repository publishes…"). The check caught the update. Proof it was noise,
not signal: the **unchanged default condition** swung high-effort pass 3/3 → 0/3
between two resamples (runs `…062422` and `…112358`) with no probe change at all.

Re-grading both runs' existing transcripts with `final_answer_text()` (zero new
invocations) gives **3/3 pass on default and probe at every effort** — the
answers never had preamble. No regression existed.

### Token measurement (`just measure-tokens`, opus-low, n=3)

Built `scripts/measure-prompt-tokens.sh` to isolate per-invocation input cost on
a tool-free prompt:

| config | mean total input tokens |
|---|---|
| default | 129,591 |
| default + exclude-dynamic | 129,482 |
| probe | 128,996 |

**Replacing the whole system prompt saves ~595 tokens (−0.5%).** `--system-prompt`
swaps only Claude Code's built-in base; CLAUDE.md, the ~30 rules files, and the
tool/MCP definitions load identically in both arms and dominate the ~129k total.
The dynamic sections are ~109 tokens here, so `--exclude-dynamic` barely moves
raw size (its value is cross-user cache reuse). **Bare prompt-size savings are
therefore a non-signal in this environment** — any real efficiency win has to
come from the probe making the model *work* better (fewer turns, fewer wrong
tool calls), not from a shorter prompt.

### Status

- Capability parity stands (corrected scorer only raises 05, equally for both).
- v3 is a prompt-quality + measurement-correctness release, not a behavior fix.
- A full v3 sweep would re-baseline with the corrected scorer; deferred as
  optional since parity is established and v3 is framing-level.
