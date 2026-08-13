---
name: meta-local-notes
description: Audit a CLAUDE.local.md — verify each claim live, fix drifted environment facts, cut findings duplicating versioned docs. Use when local notes are stale, or before appending a finding.
allowed-tools: Read, Edit, Write, Grep, Glob, Bash(ssh *), Bash(gh api *), Bash(gh workflow *), Bash(git log *), Bash(git status *), Bash(git stash list *), Bash(ls *), Bash(wc *), TodoWrite
model: opus
created: 2026-08-13
modified: 2026-08-13
reviewed: 2026-08-13
---

# Machine-Local Notes: Verify, Then Trim

A `CLAUDE.local.md` is the only always-loaded context file with **no reviewer**.
It is git-ignored, so it never appears in a diff, never gets a PR comment, and
no CI check ever reads it. Every other doc in the repo is defended by review;
this one is defended by nothing but somebody happening to look.

So it rots in two directions at once, and both are invisible:

1. **Findings creep** — session conclusions get written where they are
   convenient rather than where they belong, duplicating `docs/adrs/`,
   `docs/roadmap.md`, or the issue tracker.
2. **Silent staleness** — environment facts that were true when written. Nothing
   re-checks them, and the file reads exactly as authoritative on the day it
   goes wrong as on the day it was right.

A stale claim here is worse than no claim: it is loaded on *every turn*, it is
specific, and it is trusted. The failure mode is a session confidently acting on
a fact that stopped being true weeks ago.

## When to Use This Skill

| Use this skill when... | Use a different skill when... |
|---|---|
| A machine-local notes file has gone stale, bloated, or contradicts the ADRs/roadmap | You want to move always-loaded content to an on-demand skill — use `meta-context-diet` (load cost, not truth) |
| You are about to append a session finding to a `CLAUDE.local.md` and need the keep test | You want to turn a session's learnings into new rules — use `session-distill` |
| You need environment claims verified against the live host before trusting them | You want to move rules/skills between scopes — use `meta-promote` |

## The keep test

One question per claim: **does this describe the machine, or the project?**

| Keep — environment facts that change how you develop or test *here* | Cut — project findings, however they got here |
|---|---|
| Host and access: ssh target, hardware, driver/toolkit versions | Measurements, benchmark numbers, VRAM/throughput tables |
| Where things live: checkout, caches, datasets, staged model files | Root-cause narratives and experiment logs |
| How to run this project's proofs on this box (CI dispatch vs. manual ssh) | Blocker and status claims ("X is blocked by Y") |
| Local gotchas that change how you invoke things: a shared GPU, a gated download, a cache that must live on the big disk, flaky ssh | Decisions and their rationale |

**Numbers are the tricky case, and the same test settles them.** Keep a number
that is a property of the machine — a 24 GB card, 24 cores, a disk layout. Cut a
number that is a property of the project's behavior — a run's peak VRAM, a
throughput figure, an error count. "The card has 24 GB" is environment. "The
int4 base reclaims to 10.1 GB" is a result, and belongs in the ADR.

**Cut obsolete-note archaeology too.** Lines like *"the earlier note claiming X
is obsolete"* or *"updating the previous 'never executed' note"*. Once a fact is
corrected, the correction *is* the note. A file arguing with its own history has
stopped being a reference and become a changelog nobody asked for.

## The audit

### 1. Inventory the claims

Read the file end to end and split it into atomic claims — roughly one per
bullet or table row. A paragraph mixing a path with a conclusion is two claims
with different verdicts.

### 2. Probe every claim live

Never verify from memory or from earlier in the session. Batch the probes; it is
usually a handful of calls.

| Claim shape | Probe |
|---|---|
| Host reachable, hardware, toolkit versions | one `ssh <host> '<checks>'` |
| CI runner registered, workflow inputs | `gh api repos/O/R/actions/runners`, read the workflow header |
| Paths, datasets, staged assets exist | `ls -d` them, in the same ssh |
| Remote checkout state | `git log -1` / `status -sb` / `stash list` on the box |
| "Auto-fetches", "no auth needed", "ungated" | hit the actual API — gating changes without notice |
| Perf characterizations ("slow", "single-threaded") | `git log --grep` for a perf commit that moved it |

That last row catches the class you would otherwise miss: a claim that is still
*plausible* and still *about the machine*, but that the project fixed. A `perf(...)`
commit in the repo silently invalidates a "this is pathologically slow" note.

### 3. Cross-check before deleting

A finding is only safe to delete once you have confirmed the versioned doc
carries it. Open the ADR or roadmap section and check.

While you are there, check whether that doc has since **withdrawn or superseded**
the claim. That is the strongest possible signal: it means the local copy is not
merely redundant, it is *actively misleading*, and a session reading it would be
steered wrong. Say so in the report.

### 4. Assign a verdict

| Verdict | Action |
|---|---|
| **Holds** | keep, unchanged |
| **Drifted** | keep, **with the current value** |
| **Superseded** | delete, leave a pointer to the canonical doc |
| **Gone** | delete (the path, host, or artifact no longer exists) |

**Correct, do not merely delete.** A drifted environment fact still belongs in
the file — with the right value. Deleting it forces the next session to
re-derive it; leaving it forces them to act on something false. Only the
correction serves anyone.

### 5. Rewrite, do not patch

Patching around stale text preserves its structure and its framing. Rewrite the
file from the surviving claims, and give it:

- a one-line header stating the keep test, so the next session knows what may be
  appended;
- a pointer to where findings actually live (`docs/adrs/`, `docs/roadmap.md`);
- a **"verified &lt;date&gt;"** line, so the next reader knows the age of what they
  are trusting.

### 6. Report the verdict table

Show the user every claim with its verdict and the evidence. This is what makes
the trim reviewable after the fact — it is the review the file never gets — and
it distinguishes a verified sweep from a vibes-based deletion.

## Writing discipline (this is what prevents the next audit)

The sweep is remediation. The fix is at write time: when a session produces a
durable finding while working on a machine, it lands in the ADR, the roadmap, or
the issue — and the local file gets **at most a pointer**.

Before appending anything to a machine-local notes file, ask the keep test: *is
this about the machine, or about the project?* Only the first kind belongs.

## Evidence

loractl, 2026-08-12 — a 9.6 KB `CLAUDE.local.md` audited down to 4.9 KB:

- **Ten of ~14 claim clusters were superseded**: a long cubecl-fork narrative,
  a memory table, and two experiment logs, all carried by ADR-0005's addenda.
- **Four environment facts had drifted**: the encode phase had become ~8.5×
  faster in a perf PR (the note still called it "pathologically slow,
  single-threaded"); a model repo had become gated, making an "auto-fetches"
  note actively wrong; two staged directories had been deleted; the remote
  checkout was no longer where the note said.
- **The worst finding was the framing.** The file still described the real
  training run as blocked — three weeks after the ADR recorded the measured fit
  and the run landed. A session trusting it would have re-attacked a solved
  problem.

Every one of those was caught by a probe, and none by reading.

## Related

- `meta-context-diet` — a different axis: moving always-loaded content to
  on-demand skills. That is about a file's **load cost**; this is about its
  **truth**.
- `verify-machine-facts-before-publishing` (user rules) — the inverse direction:
  keep host-specific readings *out* of org docs. Here: keep org-doc findings out
  of host-specific notes.
- `documentation-authoring` (user rules) — link, don't duplicate. The local file
  should point at the ADR, never restate it.
- `diagnose-at-the-failure-point` (user rules) — probe the thing; don't reason
  about whether it is still true.
