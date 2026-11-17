---
name: re-deterministic-examiner
description: Build a deterministic examiner for a binary format instead of guessing. Use when reverse-engineering a packed/proprietary format and inferring a field, record size, grid, or asset identity from indirect evidence. Covers slicing into labelled units, measuring, and refusing when underdetermined.
user-invocable: false
allowed-tools: Read, Write, Grep, Glob, TodoWrite
created: 2026-11-17
modified: 2026-11-17
reviewed: 2026-11-17
---

# Deterministic Examiner Before Binding

When reverse-engineering a packed or proprietary format, the moment you catch
yourself inferring a structural fact from indirect evidence — a record size "that
looks right", a sprite grid eyeballed from a full render, an asset identity
guessed from a filename, an offset "that's probably a count" — **stop and build a
deterministic examiner that looks at the bytes.** The inference reads as fact and
propagates; a wrong provisional mapping ships and is only caught much later at a
visual/behavioural gate. The examiner is cheap, reproducible, and turns a
multi-session guessing loop into a one-command answer.

This is the RE-specific face of `offload-to-deterministic-substrate`: the agent
decides *what the structure means*; the substrate *measures and remembers* what
the bytes are.

## What the examiner must do

1. **Slice the source into its constituent units** — records, grid cells, atlas
   regions, table rows — and emit **each unit individually**: a labelled
   contact sheet / index (unit number + a cheap metric) **and** a
   machine-readable manifest (`offset,size` or `x,y,w,h` + per-unit stats).
2. **Be deterministic** — pure decode, no network, no timestamps in the output,
   so the same input yields byte-identical artifacts. That is what makes it a
   *substrate* (diffable, committable, re-runnable) rather than a one-off
   eyeball.
3. **Measure the slicing — don't guess it — and refuse when you can't.** A
   per-unit fill/entropy metric is a *post-hoc* tell that a guessed layout was
   wrong: a correct record size yields cleanly aligned, full units; a wrong one
   smears one record across several partial ones. Prefer deriving the layout
   outright where the format allows (connected-component labelling for a sprite
   atlas; the finest pitch that tiles without cutting a unit; a delimiter/length
   prefix for records). **The discipline that makes it trustworthy is that it
   declines**: when the input is underdetermined (too few units to pin a pitch,
   no clean grid), fall back to "whole blob, low confidence" and label it so at
   every layer that prints it — never ship the least-bad guess. A confidently
   wrong `72×96 cells of 4×4 px` is worse than an honest "couldn't measure".
4. **Live in the shell** — expose it as `<tool> <subcmd> <src>` plus a task
   recipe (see `tools-plugin:cli-smoke-recipes`), so it's reachable without a
   one-off driver and usable in a smoke loop.

## Inspect before you bind; re-gate after

The examiner answers *what the asset/record is*; it does not decide *how the
consumer uses it*. Use its output to author the binding, then confirm the result
at the real gate (a render, a parse round-trip, observed behaviour). The examiner
removes the guess; the gate confirms the wiring.

## Verify the machine-read facts, not an agent's summary

When a subagent reports what the examiner found, the finding is only as good as
the artifact. Read the manifest/contact sheet yourself (or diff it) before
building on a reported identity — "class 11 is the tree" from a summary is an
inference until the sliced unit is looked at.

## Related

- `offload-to-deterministic-substrate` (user rule) — the parent principle.
- `tools-plugin:cli-smoke-recipes` — expose the examiner as a CLI + smoke recipe.
- `ghidra-headless-decompile` — for the code side; this skill is the data side.
