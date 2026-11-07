---
name: measurement-controls
description: "Trust a measurement before it gates work: A/B arms, oracle gates, pooled r and x/N. Use when setting up a control or a metric says improved."
allowed-tools: Read, Grep, Glob, TodoWrite
created: 2026-11-06
modified: 2026-11-06
reviewed: 2026-11-06
---

# Measurement Controls

A measurement fails most expensively when it returns a confident, well-formed
answer about something it never observed. Nothing in the run contradicts it,
so the finding ships. Each numbered section is one way a control, an oracle or a
metric produces that answer, and the check that exposes it.

## When to Use This Skill

| Use this skill when... | Use something else when... |
|---|---|
| Setting up an A/B, an A/A′, or a "did X change the output?" control | Timing a change against a baseline → `benchmark-controls` |
| An oracle or scorer is about to turn artifacts into verdicts | Auditing whether a green suite tests what it aims at → `test-strategy-review` |
| A metric says "improved" and a person still complains | Finding weak assertions by mutating code → `mutation-testing` |
| Correlating two variables, or reporting a rate as x/N | A tool's empty result is about to gate an action → `agent-patterns-plugin:tool-result-traps` |
| Locating a defect in a long artifact (video, audio, logs, rows) | |
| Claiming an operation is "lossless", "exact" or "byte-identical" | |

## 1. A control's two arms differ only in the variable

A comparison control answers "did X change the output?" only while X is the
**only** difference. If the arms also differ in a label, filename, extra step
or timestamp, and the compared artifact carries it, the control reports
"different" whatever X did. **A control that cannot fail has not tested
anything.** Canonical break: a container format that embeds the generating
parameters makes two files differ unconditionally; hash the decoded stream.

1. **Enumerate what differs between the arms** besides the variable: step
   counts, labels, output paths, seeds, timestamps, run order.
2. **Ask whether the compared artifact carries any of it.** Containers,
   embedded metadata, EXIF and log headers do. Compare decoded content.
3. **Prove it can report "same"**: run A/A′ with the variable removed and
   confirm an identical digest. If not, every past verdict from it is void.
4. **Keep the arms otherwise byte-identical**, output prefix included.

Two gates, not one:

| Gate | Asks |
|---|---|
| A == A′ | Can the comparison report "same"? (determinism) |
| B ≠ A **in what the system receives** | Was the variable applied at all? |

Diff the input the system actually receives (the converted request, the
resolved config), not the source file you edited: a value overridden
downstream is inert. Prove the gate refuses a deliberately broken variant.

The instrument, build-time checks and a few more ways a control lies (stale
bytecode, a result cache, a test that re-implements its subject, a control
that cannot pass) are in [REFERENCE.md](REFERENCE.md#the-instrument-is-an-arm-too).

## 2. Gate the oracle on a known-good case

An oracle can be wrong in the direction that produces a finding.
**Before an oracle scores a failure case, make it recover a case already known
to have succeeded. An instrument no better than chance on the known-good case
cannot certify a failure anywhere.** The known-good case is usually free: a
project chasing a defect has examples where the thing worked.

1. **Name a case known to have worked**, independently of the instrument, and
   name the channel it is known-good *for*. A case validated on one axis is
   not validated on another.
2. **Score it. Require a high hit rate and more than one distinct answer.**
   An oracle answering one label for everything scores 2/4 on an alternating
   two-class script by coincidence; without the degeneracy check, 50% reads as
   borderline-usable when it is a constant.
3. **Read the raw answer, not the gated verdict.** Scoring only the items the
   oracle was confident about lets it pass by declining everything it would
   get wrong.
4. **Take ground truth from the artifact's own record** (plan, manifest, the
   input that produced it), never the current tree.
5. **Refuse in the tool**, not in a comment someone has to remember, and keep
   a disqualified oracle as a selectable arm: a gate that has only ever passed
   something has not been shown to discriminate.
6. **When the oracle reports a surprising negative, re-run the gate** before
   believing it. A negative from an ungated instrument is a claim about the
   instrument.

## 3. A pooled correlation or rate can be a grouping artifact

Correlating over several groups stacked together can produce a large `r` that
reports only that the groups differ in both variables. **Before believing a
correlation, ask what else varies along with both axes.** Report the
within-group coefficient next to the pooled one.

1. **Name the groups before computing anything**: lines per render, renders
   per arm, files per repo, runs per machine, warm vs cold.
2. **Tabulate each group's mean on both axes.** If the groups differ on both,
   the pooled coefficient is contaminated before you compute it.
3. **Compute `r` within each group** and report both. A pooled figure alone is
   not a result.
4. **Read the intercept.** If the effect is at full strength when the proposed
   cause is absent, the cause is not the cause.
5. **Mind the independence.** A surviving within-group `r` at small n is
   suggestive, never established.
6. **Record the dead correlation** with its numbers. Omitting it invites its
   rediscovery. A pre-registered hypothesis protects against fishing, not
   against confounding.

The same law for a **rate**: x/N over observations that are not independent
inflates n by the group size, and lets a systematic failure score partial
credit (a constant answer earns 2/4 on an alternating truth).

1. **Print the per-group outcome vector before any ratio** (`A A A A`, not
   `2/4`). The vector shows the failure mode.
2. **Ask whether a partial score is reachable.** Classify groups into named
   states and count states, with a `mixed` bucket you look at. A taxonomy with
   no escape hatch confirms itself.
3. **Score a deliberately degenerate arm** (all one label). If it earns more
   than zero, the metric rewards collapse.
4. **Label a pooled figure not-for-quoting** where it must still be computed.
5. **Report n in units of the thing measured once.** Do not state a clean
   structural rule from a dozen groups; that is the same small-sample error.

## 4. Locate the event by content, not by formula

A probe that computes where to look from an index formula measures whatever
sits at that index, precisely. **Find the event by scanning for it, then
measure.** An index derived from arithmetic is a hypothesis about the
artifact's layout.

1. **Name the boundary the report means, in the artifact's own terms**, before
   measuring. "The seam" can have two referents.
2. **Scan; do not compute.** One pass of a per-step statistic, then `argmax`.
   It finds the true location and events nobody knew to look for.
3. **Choose the statistic that matches the phenomenon.** A small change over a
   large area is caught by area, not amplitude; the wrong one ranks arms in
   reverse.
4. **Localise with a picture before quantifying**: a difference map says what
   changed.
5. **Sanity-check the located index against the artifact's structure.**
6. **Sampling is the wrong instrument for a local defect.** A defect that
   occupies one adjacent pair cannot be found by sampling frames, rows or log
   lines; scan every pair. Approving from a sample is a claim about the sample,
   so name which sample. A stated limitation is not a mitigation.

Calibrating with an injected signal, control-testing the failing arm, and
diffing by identity: [REFERENCE.md](REFERENCE.md#locating-and-calibrating).

## 5. Measure the quantity that decides the user's verdict

An evaluator measures one quantity; the user experiences a phenomenon.
**Before a metric gates work, establish that it measures what decides the
user's verdict.** An accurate, well-controlled metric about the wrong half
manufactures progress.

1. **Write down the user's verdict procedure before choosing the metric**:
   what does the person judging this actually do?
2. **A column that declines most inputs is a coverage failure.** Count the
   declines and report them next to the headline.
3. **One human observation outranks any number of runs of an unvalidated
   instrument.** Where a validation set is unfilled, say so in the result.
4. **When human and instrument disagree, reconcile; do not pick.** The
   disagreement points at the quantity nobody measures yet.
5. **A metric earns authority per axis.** A validation transfers to the axis
   and the comparison it was taken on (between-arm is weaker than absolute),
   no further. Say which axis a number is about next to the number.
6. **After any human review, ask which quantity they just used**, not only
   whether they agreed with the number.

## 6. Verify each layer against its own stem

A placement check that correlates a source against a mixed result answers "is
this where I put it" only while the window holds that source alone. **Sum each
layer separately and verify each against its own stem.** "The layers do not
overlap" is a property of today's content, not of the checker.

1. **One stem per layer, keyed off each item's layer tag**, not off a
   hand-maintained exclusion list. The exclusion list is the author having
   noticed the problem for one case.
2. **When a check newly fails on something you did not change, suspect the
   check.**
3. **Two instruments disagreeing is how you find it**; neither number is
   trustworthy alone.

## 7. A per-stream guarantee is not a per-file guarantee

"Lossless", "byte-identical", "no re-encode" are claims about one code path,
and a file carries several streams. **A guarantee is scoped to the stream the
code actually copies.** Name which stream, and measure the others.

1. **Name the streams before believing the promise**: video, audio, subtitles,
   timecode, metadata; or rows, sequences, constraints; or contents, modes,
   mtimes.
2. **Measure the stream the promise was not about, by content.** Header
   durations and metadata are what the buggy path also produced.
3. **Probe across the range, not at the start.** An accumulating error is
   invisible at the origin, and the aggregate (total length, row count) passes
   while every part is wrong. Verify per join.
4. **Handle both signs** (pad and trim) when fixing a drift.
5. **Scope the claim in the docstring**: "video copied byte-for-byte, audio
   re-encoded once", never a bare "lossless".

## Related

- [REFERENCE.md](REFERENCE.md) — the instrument as an arm, checks that cannot
  fail, calibration, and where each law bites outside media
- `benchmark-controls` — timing-specific control hazards
- `mutation-testing` — the mutation table that proves a check can fail
- `agent-patterns-plugin:tool-result-traps` — empty or well-formed tool output
  that is not the answer it looks like
- `documentation-plugin:docs-claim-hygiene` — writing a measurement down with
  its scope
- `code-quality-plugin:code-derived-facts` — guards that must use a looser,
  independent pattern

Distilled from rules in the laurigates/comfyui-nodes repository, whose dated
instances (video, audio and attribution experiments) are the provenance for
each law.
