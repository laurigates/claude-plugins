---
name: benchmark-controls
description: "Benchmark control hazards: mutated controls, disagreeing harnesses, VM lock scaling, hyperfine 2.0 exports. Use when benchmarking, comparing timings, A/B runs, hyperfine."
allowed-tools: Read, Grep, Glob, Bash(hyperfine *)
created: 2026-10-29
modified: 2026-11-06
reviewed: 2026-10-29
---

# Benchmark Controls

A benchmark comparison discriminates only while its control stays the
condition it was chosen to represent. Four routes take that away without any
error: the fixture step edits the control, the timing harness is itself a
variable, the machine magnifies the effect being measured, or the parser reads
the wrong column.

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

## A Desktop-Hypervisor VM Can Turn a Lock Ceiling Into a Slowdown

Lock contention and thread-scaling results from a desktop-hypervisor VM
(OrbStack on the Apple Virtualization framework) are provisional.
There a contended spinlock can make throughput fall as threads are added, where
bare metal shows only a plateau, so the gain from removing the lock is
overstated.

- Confirm a lock or scaling result on bare metal, or on a cloud KVM guest,
  before reporting its size.
- Report the gain per machine, naming the hypervisor; never quote the VM figure
  alone.

> Observed 2026-11 (dust, `open` + `close` across threads). On an OrbStack VM
> with 13 vCPUs, throughput fell past 4 threads. The process-wide fd-table
> spinlock (`files->file_lock`) took the paravirtual qspinlock slow path on
> 99.9% of acquisitions at 13 threads, with 4–8 µs handoff peaks. On bare metal
> (Ryzen 9 3900X, 24 threads) and on a GCP `n2-standard-8` KVM guest, which
> also enables PV spinlocks, the same lock only capped throughput. Removing it
> measured 2.1–2.5× on OrbStack, 10–11% on bare metal and about 3.5% on GCP.
> The lock cost 45 of 75 ms on OrbStack, 10 of 73 ms on bare metal and 4 of
> 99 ms on GCP. PV spinlocks alone do not explain the difference, since the GCP
> guest has them too.

## hyperfine 2.0 Renamed Its Export Fields

A parser written against hyperfine 1.x reads 2.x output without an error and
gets wrong numbers. Both export formats changed in 2.0.0:

| Export | 1.x | 2.0 |
|---|---|---|
| `--export-csv` header | `command,mean,stddev,median,user,system,min,max` | `command,time_wall_clock_unit,time_wall_clock_mean,…_stddev,…_median,…_min,…_max`, then the same six columns for each further metric (`memory_peak_resident_*` by default) |
| User/system time in CSV | `user`, `system` columns | Absent unless selected: `--metrics time` adds `time_cpu_*`, `time_user_*`, `time_system_*` |
| `--export-json` mean | `results[i].mean` | `results[i].summary.time_wall_clock.mean` (`schema_version: 2`) |
| Per-run times in JSON | `results[i].times` | `results[i].measurements[j].time_wall_clock.value` |

- Read CSV by header name, never by column position: in 2.0 column 2 is the
  unit (`s`), so a positional parser reports `mean=0.0`.
- Check the version before parsing: `hyperfine --version`, or
  `schema_version` in the JSON. Switching to `--export-json` alone does not
  avoid the change.
- 2.0 also runs commands without a shell by default (`--shell=none`); pass
  `-S` where 1.x shell behaviour is needed, and use the same setting on every
  machine compared.

> Observed 2026-11 (dust benchmarks). A script parsing hyperfine CSV by the
> 1.x positions printed `mean=0.0` under 2.0.0 and raised no error. The header
> change is confirmed in hyperfine's `src/export/csv.rs` at v1.18.0, v1.21.0
> and v2.0.0, and the JSON change in the v2.0.0 changelog.

## Related

- `~/.claude/rules/validate-adversarial-constructions.md` § "A comparison
  harness pinned to a moving baseline stops discriminating" covers the case
  where the baseline itself moves between runs (a regenerated golden file, a
  drift check against `main`).
