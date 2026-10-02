# macOS Performance Triage - Reference

Linux-to-macOS tool mapping and the full triage toolkit comparison.

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
