---
name: kernel-repro-harness
description: "Standalone kernel reproducer maintainers can rerun: syscall loop, controls, loop images, OrbStack then GCP. Use when reducing an app's kernel bug."
allowed-tools: Bash, Read, Write, Edit, Grep, Glob
created: 2026-11-02
modified: 2026-11-02
reviewed: 2026-11-02
---

# Kernel Reproducer Harness

A kernel report lands when a maintainer can rerun it in a minute without your
application. Reduce the workload to the syscalls that trigger the behaviour,
on a filesystem image built from scratch, with a control that shows the
behaviour switch off.

## When to Use This Skill

| Use this skill when... | Use something else when... |
|---|---|
| An application exposes kernel slowness or a bug and you need a dust-free (app-free) repro | Finding where threads block in the first place: `code-quality-plugin:debugging-methodology` |
| Choosing where to run kernel tests from a Mac | Renting and tearing down the cloud VM: `cloud-plugin:gcp-throwaway-vm` |
| Turning measurements into a report table | Writing and sending the report: `/kernel:list-report` |

## 1. Shape of the Tool

A small C program with two modes keeps the timed section honest:

| Rule | Why |
|---|---|
| **Build the input list before timing** (walk the tree first) | The timed section then holds only the syscalls under test (`open` + `ioctl` + `close`), not `readdir` |
| **Hand out work from one atomic index** to N `pthread`s | Threads stay busy until the list is empty; no static partition skew |
| **Report `getrusage(RUSAGE_SELF)` deltas**: voluntary and involuntary context switches, system time | Voluntary switches are the lock-queueing signal; wall time alone cannot tell waiting from working |
| **Populate deterministically** (`populate DIR N`, fixed-seed content and sizes) | Every run and every machine gets the same tree |
| **Count what the syscall returned** (extents, shared extents, errors) | Proves the path under test actually ran; `errors=0` belongs in every line |

Compile with `gcc -O2 -pthread -Wall -Wextra` and keep it warning-free; lint the
driver script with `shellcheck`.

## 2. Controls and Sweeps

- **A control tree on the same image** that takes the fast path (files that were
  never reflinked, where the kernel returns early). It must show the cost
  disappear, or the harness is measuring something else.
- **Sweep the parameter the mechanism predicts matters** (`mkfs.xfs -d
  agcount=4` vs `32`), one fresh image per value.
- **Sweep threads** (1, 4, 8, nproc), de-duplicated:
  `printf '%s\n' 1 4 8 "$(nproc)" | sort -nu`; an 8-vCPU VM otherwise runs the
  8-thread case twice.
- **Warm the caches once, then take the median of 5 runs**, and print the whole
  median line so its counters travel with its time.

## 3. Match the Contention Domain of the Real Workload

The access order decides which lock instances concurrent threads share. A
repro that hands threads neighbouring files in directory order puts them all in
the same allocation group, so they queue on one AGF buffer at any AG count. The
real workload, a parallel tree walker, spread threads across AGs.

> Observed 2026-11: with directory order, 32 AGs did not help at all and the
> repro seemed to contradict the GCP measurement. Adding a fixed-seed
> `shuffle` order reproduced it (4 threads: 184.6 ms on 4 AGs, 69.7 ms on 32),
> and `seq` order became its own finding: 4 threads 7.8× slower than 1.

Offer both orders and report both. The general method is in
`code-quality-plugin:debugging-methodology` (blocking diagnosis).

## 4. Prove the Repro Hits the Same Wait

Capture D-state stacks during the repro with the same bpftrace one-liner used
on the original workload and compare frame by frame:

```bash
bpftrace -q -e 'tracepoint:sched:sched_switch /comm == "fiemap-mt" && args.prev_state == 2/ { @[kstack(20)] = count(); }'
```

`kstack(20)` keeps 20 frames; say where it stops when you compare against a
deeper trace. On Ubuntu, bpftrace may print `tar (child): xz: Cannot exec`
while trying to unpack kernel headers; it does not affect kprobes or
tracepoints.

## 5. Where to Run: OrbStack First, GCP at Checkpoints

| Tier | Use for | Notes |
|---|---|---|
| **OrbStack machine** on the Mac | Every iteration of the harness | `orb create ubuntu:noble <name>`; run with `orb -m <name> sudo bash <script>`. Mac paths are mounted at the same path inside. Shared kernel `7.2.12-orbstack-…` (patched), aarch64, passwordless sudo; XFS, btrfs and loop devices work, and bpftrace kprobes and `sched:sched_switch` attach |
| **GCP VM, stock distro kernel** | Headline numbers before a report goes out | `cloud-plugin:gcp-throwaway-vm` for project, budget, zone fallback and teardown; delete the VM after the run |
| Bare-metal box | When the bug needs real hardware | Sudo with a password needs the user at the keyboard |

OrbStack numbers are good evidence of mechanism, not headline numbers: its
kernel carries OrbStack patches and runs on Apple Silicon. Label the arch and
kernel on every table.

## 6. Loop-Device Images

```bash
truncate -s 8G "$WORK/xfs.img"
mkfs.xfs -q -f -d agcount="$ag" -m reflink=1 "$WORK/xfs.img"
mount -o loop "$WORK/xfs.img" "$WORK/mnt"
```

Unmount and remove the image in an `EXIT` trap. A loop image is fine for
lock-contention work on warm caches; say so when I/O could matter.

## 7. Report Honestly

- Commit the raw logs (`results/<env>-<kernel>-<arch>.log`) beside the summary
  tables; every table names the log it came from.
- Keep non-monotonic results in the table and say they are unexplained, rather
  than dropping the awkward column.

For the complete harness used in 2026-11 (`fiemap-mt.c`, `run.sh`,
`wait-stacks.sh`, the GCP wrapper), see [REFERENCE.md](REFERENCE.md).

## Agentic Optimizations

| Context | Command |
|---|---|
| Create the OrbStack machine | `orb create ubuntu:noble <name>` |
| Run the harness there | `orb -m <name> sudo NFILES=20000 RUNS=3 bash repro/run.sh` |
| Probe kernel features first | `docker run --rm --privileged alpine sh -c 'uname -r; nproc; grep -w -e xfs -e btrfs /proc/filesystems'` |
| Compile check | `gcc -O2 -pthread -Wall -Wextra -o /tmp/t tool.c` |
| Lint the driver | `shellcheck run.sh` |
