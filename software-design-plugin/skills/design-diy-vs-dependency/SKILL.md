---
name: design-diy-vs-dependency
description: Evaluate a transparent DIY reimplementation before depending on a heavy single-purpose tool — GUI wrapper, bundled runtime, unaudited or non-cross-platform binary. Use when a task is about to install such a tool, or when auditing an existing dependency for removal.
args: "[tool-or-dependency]"
argument-hint: "the tool about to be depended on; omit to evaluate the current change's new dependencies"
allowed-tools: Read, Grep, Glob, WebFetch, WebSearch, Bash(gh api *), Bash(git log *), Bash(git diff *), TodoWrite
created: 2026-08-11
modified: 2026-08-11
reviewed: 2026-08-11
---

# Design: DIY vs. a Heavy Dependency

Before reaching for an existing single-purpose tool — especially one with a
GUI, a bundled runtime, an unaudited binary, or that only runs on one platform
— **evaluate whether the underlying operation is simple and well-documented
enough to reimplement directly**, in code that can be read start to finish.

This is **not** a mandate to always DIY. Most of the time the existing tool is
still the right call. But the *evaluation* should always happen before
defaulting to "just install the tool that does this."

## When to Use This Skill

| Use this skill when… | Skip when… |
|---|---|
| A task is about to install a single-purpose tool to perform one operation | The dependency is a general-purpose runtime/library reused across the project |
| The "app" is a GUI wrapping a well-defined mechanical operation | A single well-known CLI installable via mise/uv/brew covers it — don't reimplement `curl` |
| The tool is non-cross-platform, unmaintained, or an opaque bundled binary | The tool encapsulates hard-to-verify complexity (crypto, hardware timing, safety-critical) |
| Auditing an existing dependency for removal | No authoritative reference exists to verify a reimplementation against |

## The Trigger

Run the evaluation whenever the tool about to be depended on is:

- **Single-purpose** — does exactly one narrow thing for this project, not a
  general-purpose runtime/library reused elsewhere too.
- **A GUI wrapping something mechanical** — the "app" is a UI on top of a
  well-defined operation ("point this at a file and click a button").
- **Not cross-platform**, or otherwise poorly maintained, one-off, or
  distributed as an opaque bundled binary that can't easily be audited.
- **Heavier than the job warrants** — bundles a runtime (Electron, Qt,
  PyInstaller) or drags in a chain of transient dependencies just to perform
  one well-scoped operation.

## The Decision

### DIY is likely right when

- The underlying protocol/algorithm/format is **documented, or has an
  authoritative open-source reference implementation** to verify against — not
  something to be guessed at from scratch.
- The reimplementation is **bounded** — tens to a few hundred lines, not a
  multi-week undertaking re-deriving something genuinely hard.
- What results is **auditable**: one file, or a small readable set, that a
  future session (or the same person in six months) can read top to bottom and
  trust, instead of a black-box binary.
- It removes a **disproportionate dependency chain** relative to the value (a
  GUI app + its bundled runtime + a mount step, vs. one script + one well-known
  library).

### DIY is wrong when

- The tool encapsulates **real, hard-to-verify complexity** — cryptographic
  correctness, hardware timing, safety-critical logic — where a subtle bug in a
  reimplementation is a worse outcome than keeping the dependency.
- **No authoritative reference exists** to verify against; the result would be
  unverified guesswork shipped with confidence it hasn't earned.
- The dependency is already **cheap and well-audited** — a single well-known
  CLI installable per the Tool Installation Priority (mise → uv → bun →
  cargo/go → brew).
- The existing tool is actively maintained and the switching cost (in time, or
  in correctness risk) clearly exceeds the dependency it removes.

## If DIYing: Verify Against an Authoritative Source

A reimplementation is only as good as its verification. Never trust a
from-scratch port of a protocol or algorithm on memory alone.

1. **Find an authoritative reference** — the original implementation, a spec,
   an RFC, or (for reverse-engineered protocols) two or more independent,
   converging open-source implementations.
2. **Cross-check constants and structure directly from source**, not from
   memory or a summarized web result.
3. **Write a diff test.** Run the new implementation and the reference
   implementation's core logic side by side on the same inputs — including edge
   cases and boundary conditions — and assert byte-for-byte equality. Don't
   eyeball two implementations and declare them equivalent; make a script prove
   it.
4. **Attribute and license correctly.** Vendoring or closely porting someone
   else's documented algorithm still carries their attribution and license
   terms — a reimplementation that quietly drops credit isn't actually more
   transparent than the binary it replaced.

Step 3 is the one most often skipped and the one that pays. In the worked
example below it caught a real behavioral divergence before it shipped.

## Worked Example (2026-07, nintendo-switch-cfw)

A Switch CFW project depended on `CrystalRCM.app` — a mounted, unaudited macOS
GUI binary — to perform one operation: inject a fusée-gelée payload over USB
into a console in RCM mode. The exploit's memory layout and USB protocol are
fixed and well-documented (CVE-2018-6242), with byte-identical reference
implementations across multiple independent open-source forks going back to
2018. A textbook DIY candidate.

Replaced with a ~215-line, single-file, `uv run`-executable script (PEP 723
inline deps: just `pyusb`). Before trusting it:

- Cross-checked every constant and the full algorithm against two independent
  forks' actual source (not a summary), plus the assembly source for the one
  binary blob that had to stay vendored (a 124-byte relocator stub, verified
  byte-identical across forks).
- Wrote a diff test against a verbatim port of the reference algorithm across
  six cases (empty, tiny, a real downloaded payload, and the exact overflow
  boundary) — **caught one subtle behavioral divergence at the boundary case**.
- Smoke-tested the live CLI path (arg parsing, error paths, USB device
  enumeration) as far as possible without physical hardware.

Net: a mounted GUI app of unknown provenance replaced by one auditable script
plus `pyusb`/`libusb` — both well-known, independently useful libraries, not
another single-purpose black box.

## Rationale

Single-purpose GUI tools accumulate silently. Each is individually "just one
dependency," but across a portfolio they add up to a pile of differently-built,
non-cross-platform, unaudited binaries with no shared conventions — the
opposite of the consistency such a portfolio otherwise optimizes for.

The fix isn't "never use existing tools." It's making the evaluation a habit:
before installing the app, ask whether the operation is simple and documented
enough to own directly, verify it properly if so, and fall back to the heavy
dependency when the evaluation says it's genuinely warranted.

## Related

- `code-quality-plugin:code-dep-audit` — auditing dependencies you already have
  for vulnerabilities and staleness; this skill governs the prior question of
  whether to take the dependency at all
- `agent-patterns-plugin:verify-before-plan` — the same "check reality before
  committing to an approach" instinct
- YAGNI (`~/.claude/rules/code-quality.md`) — DIY only when the win is real;
  don't reimplement speculatively, or for a tool that isn't actually being
  removed
- `~/.claude/rules/verify-upstream-before-patching.md` — go to the
  authoritative source rather than working from memory
- `~/.claude/rules/offload-to-deterministic-substrate.md` — the diff-test step
  is that principle applied to correctness verification itself
