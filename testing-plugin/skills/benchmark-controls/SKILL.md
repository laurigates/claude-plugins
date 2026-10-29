---
name: benchmark-controls
description: "Benchmark control hazards: fixtures that mutate the control, timing harnesses that disagree. Use when benchmarking, comparing timings, A/B performance runs, hyperfine."
allowed-tools: Read, Grep, Glob, Bash(hyperfine *)
created: 2026-10-29
modified: 2026-10-29
reviewed: 2026-10-29
---

# Benchmark Controls

A benchmark comparison discriminates only while its control stays the
condition it was chosen to represent. Two routes take that away without any
error: the fixture step edits the control, or the timing harness is itself a
variable.

## When to Use This Skill

| Use this skill when... | Use something else when... |
|---|---|
| Timing a code change against a baseline (A/B, before/after, branch vs `main`) | Baselining a Mac's hardware health → `macos-plugin:macos-performance-benchmark` |
| Building benchmark fixtures from an existing data set | Load-testing an HTTP service → `networking-plugin:http-load-testing` |
| Two timing tools (`hyperfine`, a shell loop, `/usr/bin/time`) report different numbers for one command | The comparison is a correctness harness pinned to a moving baseline → the sibling rule cited under Related |

## Deriving Test Data Can Mutate the Control

A step that builds a fixture *from* the control data set can change the
control's own state: reflinks, hard links, `chmod`, atime, warmed caches. The
control then measures the condition it was meant to exclude, and nothing in the
result says so.

- Time the control **before** deriving anything from it, or derive from a copy.
- Record in the results how each data set was produced, including every step
  that read or copied it.

> Observed 2026-10 (dust `--shared-blocks`, XFS). The "shared" set was built
> with `cp -a --reflink=always ~/.rustup/toolchains` before timing, which turned
> the "unshared" control `~/.rustup` (198,319 files) into reflinked inodes. It
> was reported as "nothing shared": `--shared-blocks` 769.4 ms vs master
> 96.6 ms (8.0x). A never-reflinked tree, `/usr/share` (128,365 files),
> measured 126.3 vs 66.0 ms (1.9x), and the PR's numbers were corrected.
> Unverified: whether XFS keeps an inode's reflink flag after the copies are
> deleted.

## Two Timing Harnesses That Disagree Are Both Suspect

Before trusting either number:

- Alternate the two harnesses back to back on the same command, then repeat on
  a non-blocking control.
- Use the same harness and flags on every machine being compared.
- Name the harness next to every number it produced.

> Observed 2026-10 (dust, Linux desktop, kernel 6.17, cpufreq governor
> `powersave`). `hyperfine -N` measured the lock-bound case at ~740 ms; a plain
> bash loop timing the same command measured ~520 ms, consistently when the two
> alternated. Single `/usr/bin/time` runs agreed with the loop (0.49–0.60 s).
> On the non-blocking baseline the methods were within ~6%, and on macOS within
> ~2% for every case. Cause not established; scheduling sensitivity of a lock
> convoy is an unproven hypothesis.

## Related

- `~/.claude/rules/validate-adversarial-constructions.md` § "A comparison
  harness pinned to a moving baseline stops discriminating" covers the case
  where the baseline itself moves between runs (a regenerated golden file, a
  drift check against `main`).
