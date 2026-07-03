---
name: macos-performance-benchmark
description: Repeatable macOS/Apple-Silicon benchmark + diagnostics scored PASS/WARN/FAIL with saved reports. Use when baselining a Mac, verifying it performs to spec, or tracking CPU/memory/disk/thermal health.
args: "[mode]"
argument-hint: mode — diagnose | bench | full | report (default full)
allowed-tools: Bash(bash *), Bash(uname *), Bash(sudo bash *), Read, Grep, Glob
created: 2026-07-03
modified: 2026-07-03
reviewed: 2026-07-03
---

# macOS Performance Benchmark (Apple Silicon)

A repeatable, threshold-scored performance suite. Runs diagnostics and
benchmarks for CPU/thermals, memory/swap, disk/storage, and startup/background
load, writes a timestamped run under `~/.cache/macos-perf/`, and generates a
markdown report with PASS/WARN/FAIL verdicts against tunable baselines.

## When to Use This Skill

| Use this skill when... | Use something else when... |
|------------------------|----------------------------|
| You want a **repeatable baseline** — "is this Mac performing to spec?" scored PASS/WARN/FAIL | The Mac is **hot/slow right now** and you need live attribution — use `macos-performance-triage` |
| Tracking CPU/memory/disk/thermal health across runs, comparing before/after a change | The machine actually **hung or panicked** — use `macos-incident-postmortem` |
| Producing a saved report to keep or share | A **security extension** (Kandji ESF, XProtect, EDR) is the hot process — use `endpoint-security-cpu` |
| Benchmarking NVMe/AES/SHA/memory throughput against thresholds | You're **reclaiming disk space** — use `macos-disk-usage` |

This skill is the **proactive baseline** companion to the reactive
`macos-performance-triage` playbook: run this to know the machine's normal;
run triage when something is wrong *now*.

## Platform Guard

**macOS-only.** `sysctl`, `pmset`, `powermetrics`, `macmon`, `diskutil`, and the
Apple-Silicon counters are Darwin-specific. `run.sh` refuses on non-Darwin.

```bash
test "$(uname -s)" = "Darwin" || { echo "macos-plugin: not Darwin, refusing"; exit 1; }
```

## Parameters

Parse `$ARGUMENTS` for the run **mode** (default `full`):

| Mode | What runs | Time | sudo |
|------|-----------|------|------|
| `diagnose` | 4 diagnostics + report | ~25s | no |
| `bench` | 3 benchmarks + report | ~3 min | no |
| `full` | diagnose + bench (default) | ~5 min | no |
| `diag-cpu` / `diag-memory` / `diag-disk` / `diag-startup` | one diagnostic | <10s | no |
| `bench-cpu` / `bench-memory` / `bench-disk` | one benchmark | ~1 min | no |
| `report` | regenerate the latest run's report | instant | no |
| `report-list` | list saved runs with PASS/WARN/FAIL counts | instant | no |

Add `sudo` in front for thermal-pressure data (`powermetrics`); everything else,
including CPU power via `macmon`, runs **without** sudo.

## Execution

Run the bundled suite and surface the verdict. The scripts self-detect tools and
skip gracefully when one is absent.

### Step 1: Run the selected mode

```bash
bash "${CLAUDE_SKILL_DIR}/scripts/run.sh" $ARGUMENTS
```

For thermal-pressure data (optional), prefix with `sudo`:

```bash
sudo bash "${CLAUDE_SKILL_DIR}/scripts/run.sh" diag-cpu
```

### Step 2: Read the report

`run.sh` prints the generated report and its path
(`~/.cache/macos-perf/<timestamp>/report.md`). Summarize the **Overall Status**
and every WARN/FAIL, mapping each to the process or subsystem responsible. For a
hot process or hung machine, hand off to the reactive skills named in the
"When to Use" table.

### Step 3: Compare against prior runs (optional)

```bash
bash "${CLAUDE_SKILL_DIR}/scripts/run.sh" report-list
```

Each saved run keeps its `summary.tsv` (one status row per check) and per-script
logs, so before/after comparisons and regressions over time are trivial.

## Thresholds & calibration

Defaults are calibrated for an **M4 Pro** but the suite is **not machine-locked**.
Every threshold is env-overridable — see
[`scripts/config.sh`](scripts/config.sh) for the full `MACOS_PERF_*` list. To
retune for a different Mac, export the relevant variables before running, or drop
a `thresholds.local.sh` beside `config.sh`:

```bash
MACOS_PERF_AES_WARN_MBS=1800 MACOS_PERF_RAM_MIN_GB=16 \
  bash "${CLAUDE_SKILL_DIR}/scripts/run.sh" bench
```

Results default to `~/.cache/macos-perf/`; override with `MACOS_PERF_RESULTS_DIR`.

## Tooling

`macmon` (Rust, sudo-free) is preferred for CPU power/thermals, matching the
`macos-performance-triage` toolkit; `powermetrics` (sudo) is the fallback and the
only source of thermal *pressure*. Install the sudo-free path with:

```bash
brew install macmon jq
```

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Fast health check, no sudo | `bash "${CLAUDE_SKILL_DIR}/scripts/run.sh" diagnose` |
| Full benchmark baseline | `bash "${CLAUDE_SKILL_DIR}/scripts/run.sh" bench` |
| Machine-readable verdicts | `awk -F'\t' '$1~/^(PASS|WARN|FAIL)$/' ~/.cache/macos-perf/*/summary.tsv` |
| List runs + counts | `bash "${CLAUDE_SKILL_DIR}/scripts/run.sh" report-list` |
| Retune a threshold | `MACOS_PERF_<KEY>=<value> bash "${CLAUDE_SKILL_DIR}/scripts/run.sh" <mode>` |

## Related

- `macos-performance-triage` — reactive live triage (this skill's companion)
- `macos-incident-postmortem` — after a hang/panic
- `macos-disk-usage` — disk-space forensics and reclamation
