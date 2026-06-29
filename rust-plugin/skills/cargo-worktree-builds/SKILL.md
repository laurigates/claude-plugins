---
created: 2026-06-29
modified: 2026-06-29
reviewed: 2026-06-29
name: cargo-worktree-builds
description: "Share one CARGO_TARGET_DIR across parallel git-worktree agents so Rust deps compile once. Use when running cargo/clippy/test in several worktrees concurrently, when parallel agent builds rebuild dependencies N times, or when N worktrees blow up disk with N copies of target/."
user-invocable: false
allowed-tools: Bash, Read
---

# cargo-worktree-builds - Shared Target Dir for Parallel Worktree Agents

When you fan out parallel agents into separate `git worktree`s of a Rust repo
(one per issue/feature), each worktree builds into its **own** `target/` by
default. For a project with hundreds of dependency crates that means every
worktree pays the full cold dependency build (minutes each) and writes its own
multi-GB `target/` — so N worktrees cost ≈ N× time and N× disk for dependency
artifacts that are byte-identical across them.

Point every worktree at **one shared, pre-warmed `CARGO_TARGET_DIR`** instead.
Dependencies compile **once** and are reused; cargo's build lock serializes the
concurrent builds (which also caps CPU/I/O thrash); disk stays ≈ 1× not N×.

## When to Use This Skill

| Use this skill when... | Use X instead when... |
|------------------------|-----------------------|
| Dispatching parallel agents into multiple git worktrees of one Rust repo | A single working tree — the default `target/` is already optimal |
| `cargo`/`clippy`/`test` is rebuilding the same deps in each worktree | Caching deps in **CI** — use `Swatinem/rust-cache@v2` (see cargo-llvm-cov) |
| N worktrees are filling the disk with N copies of `target/` | Speeding up a single build — use a faster linker / `cargo check` |
| Coordinating a multi-worktree wave (see agent-patterns-plugin) | Cross-machine sharing — use `sccache`, not a shared dir |

## Context

- Cargo.toml present: !`find . -maxdepth 1 -name 'Cargo.toml'`
- CARGO_TARGET_DIR currently set: !`echo "${CARGO_TARGET_DIR:-<unset — each worktree uses its own ./target>}"`
- Active git worktrees: !`git worktree list`

## The Pattern

### Step 1: Choose one persistent shared target dir

Pick a path **outside** any worktree (so removing a worktree never deletes the
cache) and on the **same disk** as the checkouts (so cargo can hardlink):

```bash
export SHARED_TARGET="$HOME/.cache/<repo>-target"
mkdir -p "$SHARED_TARGET"
```

### Step 2: Pre-warm it ONCE before dispatching agents

A cold shared dir means the **first** agent to build compiles every dependency
crate while the others block on cargo's build lock. Pre-warming from the
orchestrator removes that serialized stall from the critical path:

```bash
CARGO_TARGET_DIR="$SHARED_TARGET" cargo fetch
CARGO_TARGET_DIR="$SHARED_TARGET" cargo build   # compiles all deps once
```

### Step 3: Every worktree command exports the same dir

Prefix every `cargo`/`just` invocation in every worktree agent with it:

```bash
CARGO_TARGET_DIR="$SHARED_TARGET" just check     # fmt + clippy + test
CARGO_TARGET_DIR="$SHARED_TARGET" cargo test
```

Brief each agent to use this exact prefix. Dependency artifacts are now shared;
only each worktree's own crate is recompiled per build.

## Why It Works (and the one gotcha)

- **Deps compile once.** The dependency graph is identical across worktrees, so
  the shared dir reuses it; only the leaf crate differs per worktree.
- **Cargo's build lock serializes concurrent builds.** Two agents building at
  once won't corrupt the dir — cargo holds an exclusive lock on the target dir
  during a build, so the second waits. This also throttles total CPU/I/O, which
  is usually desirable when many agents run at once.
- **Disk stays ≈ 1×.** One `target/` for all worktrees instead of N.

### Gotcha: transient "method not found" / stale-rlib under contention

Because builds serialize on the shared lock, an agent can occasionally read a
**stale rlib** that a concurrent agent is mid-rebuild on, surfacing as a
spurious compile error like `no method named X found` or a file-lock message —
even though the code is correct. It is **not** a real error.

**Fix:** force a rebuild and re-run.

```bash
touch src/lib.rs                                 # or any source file in scope
CARGO_TARGET_DIR="$SHARED_TARGET" just check
```

Tell agents up front that an isolated, non-reproducing "method not found" right
after a green peer build is the shared-target lock — `touch` + re-run, don't
chase it as a code bug.

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Define the shared dir | `export SHARED_TARGET="$HOME/.cache/<repo>-target"; mkdir -p "$SHARED_TARGET"` |
| Pre-warm before fan-out | `CARGO_TARGET_DIR="$SHARED_TARGET" cargo build` |
| Per-worktree gate | `CARGO_TARGET_DIR="$SHARED_TARGET" just check` |
| Recover from a stale-rlib error | `touch src/<file>.rs && CARGO_TARGET_DIR="$SHARED_TARGET" cargo test` |
| Inspect cache size | `du -sh "$SHARED_TARGET"` |

## Quick Reference

| Knob | Effect |
|------|--------|
| `CARGO_TARGET_DIR` (env) | Redirects **all** build output to a shared path; the lever this skill uses |
| `build.target-dir` in `.cargo/config.toml` | Per-repo equivalent — but commits the path; prefer the env var for ephemeral worktrees |
| cargo build lock | Serializes concurrent builds against the shared dir (the safety + throttle) |
| Same-disk placement | Lets cargo hardlink instead of copy; cross-disk forces copies |

## Relationship to Parallel-Agent Dispatch

This is the Rust-specific build-isolation companion to the worktree fan-out
patterns in `agent-patterns-plugin` (`parallel-agent-dispatch`,
`wave-based-dispatch`): those cover git/branch isolation and orchestrator-owned
shared files; this covers the **build cache** so N worktrees don't each pay the
full dependency compile. Pre-warm in the orchestrator, then hand every agent the
`CARGO_TARGET_DIR=…` prefix.

> Evidence: a 5-agent worktree wave on a ~320-crate `ratatui`/`tokio` TUI
> (gh-board) pre-warmed one `$HOME/.cache/gh-board-target` and ran every agent's
> `just check` against it — deps compiled once, the lock serialized the
> concurrent builds, and the only friction was the transient stale-rlib above,
> resolved by `touch` + re-run.
