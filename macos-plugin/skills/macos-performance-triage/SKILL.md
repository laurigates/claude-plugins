---
name: macos-performance-triage
description: Live macOS/Apple-Silicon performance triage — find what's heating the Mac (hot WindowServer, GPU compositing, a CPU-heavy browser/Electron app) and attribute it to the driving process. Use when fans spin up, the Mac is hot/slow, or WindowServer/an app shows high CPU/GPU.
user-invocable: false
allowed-tools: Bash(uname *), Bash(ps *), Bash(top *), Bash(pgrep *), Bash(uptime *), Bash(vm_stat*), Bash(sysctl *), Bash(macmon *), Bash(btm *), Bash(sample *), Bash(spindump *), Bash(sudo powermetrics *), Bash(samply *), Bash(hyperfine *), Bash(brew install *), Bash(brew list *), Read, Grep, Glob
created: 2026-06-30
modified: 2026-06-30
reviewed: 2026-06-30
---

# macOS Performance Triage (Apple Silicon)

## When to Use This Skill

| Use this skill when... | Use something else when... |
|------------------------|----------------------------|
| The Mac is hot/loud/slow and you need to find what's driving it | The machine actually hung or panicked — use `macos-incident-postmortem` |
| `WindowServer` shows high CPU/GPU and you need to attribute it to a client app | A *security* extension (Kandji ESF, XProtect, an EDR) is the hot process — use `endpoint-security-cpu` |
| One ordinary app (Chrome/Electron, a renderer, a game) is pegging CPU or GPU | `launchservicesd` is the hot process — use `launchservices-health` |
| You want a flame graph / deep profile of a specific process | A disk reads near-full or you're reclaiming space — use `macos-disk-usage` |
| You want a repeatable "what's hot right now" snapshot | `syspolicyd`/`trustd`/`tccd`/`auditd` are *all* elevated together (exec storm) — use `endpoint-security-cpu` |

## Platform Guard

**macOS-only.** `powermetrics`, `sample`, `spindump`, Instruments, and the
Apple-Silicon power counters `macmon` reads are Darwin-specific.

```bash
test "$(uname -s)" = "Darwin" || { echo "macos-plugin: not Darwin, refusing"; exit 1; }
```

## Core Insight: triage with the USE method; WindowServer is always downstream

Two ideas drive the whole flow:

1. **USE method** (Brendan Gregg) — for each resource ask **U**tilization,
   **S**aturation, **E**rrors. A bare `ps`-by-CPU only answers *Utilization*.
   Saturation (run-queue depth, thermal throttle) and Errors (`log stream`)
   complete the picture. The method is OS-agnostic; only the tools change.
2. **`WindowServer` never starts its own work.** Every cycle it burns was
   *requested* by a client app's draw / animation / compositing. Apps build their
   UI as `CALayer` hierarchies, hand them to WindowServer via IOSurface, and
   WindowServer composites (positioning, clipping, masks, shadows, effects) synced
   to the display refresh. So a hot WindowServer is a **symptom** — the job is to
   find the app feeding it (continuous video, GIF/Lottie animation, a software /
   non-GPU-accelerated render path, layout thrashing).

The deepest tier of Gregg's Linux approach does **not** transfer: **there is no
eBPF / bpftrace on macOS.** DTrace is the analogue but **SIP blocks it from
tracing Apple-signed/system processes** (including WindowServer) unless SIP is
disabled — not worth it for desktop triage. The flow below stays within a
normally-secured Mac.

## Step 1 — Quick triage: what's hot

Start with a process snapshot, sorted by CPU. `-c` shows the short command name:

```bash
ps -Aceo pid,pcpu,pmem,comm -r | head -16
```

Then get the Apple-Silicon power/thermal picture. **`macmon` (Rust) is the
preferred tool** — it reads the same data as `powermetrics` (per-cluster P/E-core
load + frequency, GPU, ANE, package power, temps) but **without sudo**, via a
private IOReport API. One-shot, scriptable snapshot:

```bash
macmon pipe -s 1 | jq -c '{cpu_W:.cpu_power, gpu_W:.gpu_power, ane_W:.ane_power, ecpu_usage, pcpu_usage, gpu_usage, temp}'
```

Live TUI: `macmon`. Process/thread breakdown TUI: `btm` (bottom, Rust).

If the tools are missing, offer to install (all Rust, all sudo-free):

```bash
brew install macmon bottom samply hyperfine
```

**Read the snapshot:**
- A high non-system process at the top → go to Step 3 (profile it) or just
  identify/close it.
- `WindowServer` high → Step 2 (attribute it).
- `kernel_task` high → thermal management throttling a real load; find that load.
- The whole security stack hot together → this is an **exec storm**, hand off to
  `endpoint-security-cpu`.

### Common phantom offenders

- **`OrbStack Helper`** — quitting the OrbStack *app* does **not** stop the VM; the
  helper reparents to launchd (`PPID 1`) and keeps eating ~40–50% CPU / ~20% RAM
  with no visible app. Confirm with `ps -Ao pid,ppid,comm | grep -i '[o]rb'` (a
  `PPID` of `1` is the tell) and stop it with `orb stop`, not `kill`. (Disk side of
  the same tool: `macos-disk-usage`.)
- A backgrounded Electron app (Slack, Discord, VS Code) animating off-screen.
- A browser tab running video/WebRTC/canvas — see Step 2.

## Step 2 — Attribute WindowServer / GPU load to the driving app

There is **no single first-party "blame" button**; attribute in layers, cheapest
first:

1. **Per-process GPU cost (the real lever):**
   ```bash
   sudo powermetrics --samplers tasks --show-process-gpu -n 1 -i 1000
   ```
   The app with high GPU here is what's loading WindowServer's compositor.
2. **Activity Monitor → add the GPU column**, sort descending; the **Window Spy**
   picker maps a visible window back to its owning process.
3. **Instruments → Core Animation template** — layer counts, dropped frames,
   compositing time (developer-side, if you own the app).
4. **Instruments → Metal System Trace** — catches software-fallback (non-GPU)
   render paths and frame-pacing anomalies.
5. **Quartz Debug** (Xcode Additional Tools) — live "flash dirty regions /
   overdraw"; *visually* shows which surfaces re-composite every frame.

**Pattern to expect:** N live video/WebRTC streams (e.g. a multi-cam call inside a
browser/VTT) = N continuously-invalidating Core Animation layers → per-frame
recomposition. That is a genuine workload floor, not a fault — confirmed when
WindowServer stays hot after you close *other* GPU consumers.

> `sample WindowServer 5` and `spindump` can sample WindowServer itself, but they
> show its *internal compositing* stacks, not which client drove the work — use
> `powermetrics --show-process-gpu` for attribution, not `sample`.

## Step 3 — Deep profiling: flame graph a specific process

For a CPU-heavy process you own, **`samply` (Rust)** is the modern path — samples
via Apple's Mach interface (on- and off-CPU), opens in the Firefox Profiler UI
(flame graph + timeline + call tree), **no sudo, no SIP changes** for your own
binaries:

```bash
samply record ./my-program        # launch + record
samply record --pid 12345         # attach to a running PID
```

- **Instruments** is more capable (adds GPU, ANE, Metal, PMC counters) but the UI
  and `xctrace` CLI are sluggish, and attaching to *other* apps needs entitlements.
- **`cargo flamegraph` / FlameGraph + dtrace** works for your own code, but SIP
  makes dtrace-based graphs low-fidelity for anything system-touching, and can't
  graph WindowServer at all without disabling SIP.
- A **Chrome/Electron renderer** is sandboxed — `samply` can't see in usefully;
  use the app's own `chrome://tracing` / DevTools Performance tab instead.

For A/B comparing two builds or commands (Gregg-style workload characterization),
**`hyperfine`** (Rust) gives warmup + statistics:

```bash
hyperfine --warmup 3 './old-build args' './new-build args'
```

## Linux → macOS tool map (for transferring Gregg's playbook)

| Linux (Gregg) | macOS-native | Modern add-on |
|---|---|---|
| `top`/`htop`, `vmstat` | `top -o cpu`, `vm_stat`, `sysctl` | **macmon**, **bottom** (Rust) |
| `perf` | `sample`, `spindump`, Instruments | **samply** (Rust) |
| `bcc` / `bpftrace` / eBPF | `dtrace` (SIP-limited) | — (no eBPF on macOS) |
| `ftrace` | `ktrace` / `os_signpost` + Instruments | — |
| `turbostat`/power | `sudo powermetrics` | **macmon** (sudo-free) |
| `hyperfine` | `hyperfine` | **hyperfine** (Rust, cross-platform) |

## The toolkit (Rust-forward, all sudo-free unless noted)

| Tool | Lang | Measures | sudo/SIP | Tier |
|---|---|---|---|---|
| **macmon** | 🦀 Rust | P/E-core, GPU, ANE, power(W), temp, fans, RAM; JSON + Prometheus | none | triage |
| **bottom** (`btm`) | 🦀 Rust | procs, CPU, mem, net, disk, temp | none | triage |
| `powermetrics` | C (Apple) | per-process GPU/CPU/ANE, power | **sudo** | attribution |
| **samply** | 🦀 Rust | sampling profiler → Firefox Profiler | none (own procs) | profiling |
| **hyperfine** | 🦀 Rust | CLI benchmark, A/B, stats | none | benchmarking |
| Instruments | Apple | GPU/Metal/ANE/Core Animation/PMC | entitlements | deep |
| `sample`/`spindump` | Apple | user-stack call-graph | sudo for system procs | profiling |

`macmon`, `bottom`, `samply`, `hyperfine` install with one line:
`brew install macmon bottom samply hyperfine`. `asitop`/`mactop` are older
equivalents that require sudo; `macmon` supersedes them.

## Output

Report: the hot process(es) with CPU/GPU/power figures; for a hot WindowServer,
the attributed client app and *why* (animation/video/software-render); the
recommended action (close/stop the driver, lower its settings, or profile it); and
which tier of tool produced the verdict. Distinguish a genuine workload floor (a
live video call) from a fixable runaway (an orphaned VM, a stuck animation).
