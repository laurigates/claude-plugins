---
name: docs-claim-hygiene
description: "Keep figures in docs true: cite the command, not a count that moves; scope measurements; fix a corrected claim in every summary. Use when writing a number into docs or correcting a finding."
allowed-tools: Read, Grep, Glob, Edit, TodoWrite
created: 2026-11-06
modified: 2026-11-07
reviewed: 2026-11-06
---

# Docs Claim Hygiene

Two failures make a document assert something false while looking
authoritative: a number that moves was written down as if it were fixed, and a
claim was corrected where it is argued but not where it is summarised.

## When to Use This Skill

| Use this skill when... | Use something else when... |
|---|---|
| Writing a count, capacity, status or roster into prose | Restating a list or table that lives in code → `docs-single-source` |
| Recording an experiment's result in a doc | Publishing a value read off your own machine as an org fact → `docs-verify-machine-facts` |
| A doc line says something is blocked, unavailable or already handled | Deciding whether a measurement itself is trustworthy → `testing-plugin:measurement-controls` |
| Correcting or retracting a published claim | |

## A document may record a measurement; it may not hold a reading

**A measurement is a record of an experiment.** "At setting 0 the model began
speaking at the first sample in four of five clips (run of 2026-08-15)." It
stays true, because it is a statement about a run that happened. Date it, scope
it, keep it.

**A reading is the current value of something that moves**: free disk space, a
queue depth, "the 8 packages we maintain". Writing it down does not make it
stable; it makes it authoritative-looking while it rots.

> **Never write a reading into prose. Write the command that takes it.**

A reading in a document also **displaces the check**: a reader who sees the
number does not run the query, which is why the number was written. The worst
cases are false in the direction that prevents work. "This graph runs out of
memory" sends the next person to a workaround they do not need. "Asserted by
check 10", when no check 10 exists, reads as coverage and stops anyone writing
the check.

| Instead of | Write |
|---|---|
| A free-space or capacity figure | The `df` invocation, plus the **threshold** that matters |
| A queue depth or item count | The query that returns it |
| A roster of packages, repos or files | A pointer at the file that already lists them |
| "installed" / "blocked" / "not available" | The one-line check that decides it, and the date last checked |
| "this is asserted by check N" | Nothing, or add the check |

Keep the durable half and drop the reading. "Keep 12 GB free for staging"
survives; "free space: tight" does not. The requirement is the fact; the
verdict is the reading. A good model to copy quotes a figure, dates it, notes
that earlier values went stale within a day, and says "never quote this cell".

### When a reading may stay

- **It is dated and framed as history**, and the surrounding text does not
  depend on it still being true.
- **It is fixed hardware** (24 GB of VRAM). Even then, cite it where it is an
  argument's premise rather than as decoration, because hardware gets upgraded
  and every copy has to be found.
- **It is a threshold or a budget you chose**, not an observation.

## A measurement's scope is part of the measurement

A number can stay accurate and still be written down as a fact about the wrong
thing. Nothing goes stale; the claim was always broader than the evidence.

- **Record what a measurement is a measurement of**: the metric, the version,
  the input variant, the sample size. "12 of 12 spans, *voice timbre only,
  v0.5.18, four seeds*", not "binds correctly".
- **When a summary and the source it cites disagree, the summary is wrong.** It
  is the one with a person's compression in it. Check the cited table before
  quoting the summary.
- **Where a reading comes from a local measurement rather than a document,
  doubt the local reading first**: it has an environment attached (a vendored
  library is not the system library).
- **Name the statistic's blind spots.** A gated statistic that discards its
  tails cannot say anything about the tails. Write "LRA 2.6 (gated; see the
  short-term range for the tails)".

An unscoped number ages into a false rule, and unlike a stale reading nothing
about it ever looks out of date.

## Before trusting a claim that stops you working

A doc line that says something is blocked, impossible, unavailable or already
handled is the line most worth re-testing, because nobody re-tests the ones
that let them proceed.

1. **When was this established, and has anything under it moved since?** A
   dependency upgrade can silently invalidate a month-old finding.
2. **What is the cheapest test that would falsify it?** If it costs under a
   minute, run it before designing around the claim.

Record the reversal rather than deleting the old finding: "this was true; here
is what changed" is more useful than text that quietly disagrees with a
reader's memory.

## A correction reaches the argument and not the summary

When a published claim is found wrong, the instinct is to fix the section that
argues it. The same claim is almost always **restated somewhere shorter**, and
that is where a hurried reader takes the verdict from.

> **Correcting a claim means grepping for the CLAIM, not editing the section.
> A retraction in the body does not reach the abstract.**

1. **Grep for the claim's distinctive tokens**: the number, the phrase, the
   comparison, not the section heading. Classify every hit: the corrected
   argument, a correction box legitimately quoting the old claim, or an
   uncorrected restatement. Two token classes a plain sweep misses:
   - **Multipliers and ratios that restate a magnitude** (`4×`, "twice", "an
     order of magnitude"). Where a restatement only points back at the
     argument, word it without the number so the next correction has nothing
     to re-sync.
   - **A sentence split across source lines.** Adjacent string literals
     (Python, C, shell continuations) join at runtime, so a grep for the whole
     phrase finds nothing. Grep fragments that fit on one line, or read the
     rendered text.
2. **Check the summary surfaces by name**: abstract or TL;DR, "what is
   established" boxes, findings tables, method notes, the README, commit
   messages still unmerged, docstrings of functions the claim describes, and
   **CLI `--help` text**. Pin a corrected help string with a test that renders
   the help, normalises whitespace, and asserts the qualifier present **and**
   the retracted wording absent.
3. **Test scaffolding is a summary surface**, and each part is read
   differently: a test **name** shows in failure headers and `-v` output; a
   mutation row's **label** may be printed on every verdict line, asserting the
   stale claim next to the evidence for its replacement; a row's **expected-
   behaviour prose** is never machine-read, which is why it rots unnoticed.
   Renaming a test means moving every field that refers to it in the same edit.
   A claim about what a tool prints is checked by reading the tool.
4. **A correction box is not enough.** A reader who lands on the summary never
   sees it. If a claim is retracted, the summary must not state it.
5. **Check the summary is complete, too.** A summary that over-claimed one
   result often under-reports another; summaries drift toward whatever was true
   when they were written.
6. **When a file is superseded, say so at the head of the old file**: name the
   replacement and what the old file is still kept for. A note only in the
   replacement does not reach anyone who opens the old file through an import,
   a help example or another tool's error message.

The same miss happens with a deprecated API fixed in the reference page and
still recommended in the quickstart, a revised default changed in code and
still listed in the README and `--help`, a retracted benchmark still quoted in
release notes, and a commit message describing behaviour a later commit in the
same PR changed (unfixable after merge).

## Related

- `docs-single-source` — link to the source instead of copying a roster
- `docs-verify-machine-facts` — values read off your own machine before they
  reach shared docs
- `testing-plugin:measurement-controls` — whether the measurement deserves
  recording at all
- `code-quality-plugin:code-derived-facts` — a fact derived with a pattern and
  written to a table is a reading, too

Distilled from rules in the laurigates/comfyui-nodes repository, whose dated
instances are the provenance for each law.
