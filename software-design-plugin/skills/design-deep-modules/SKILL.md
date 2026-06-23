---
name: design-deep-modules
description: Judge interface depth — deep modules hide complexity behind small interfaces. Use when designing a module/API, reviewing a class boundary, or reducing complexity.
args: "[target]"
argument-hint: "file|module|dir|diff to assess for interface depth; omit for current change"
allowed-tools: Read, Grep, Glob, Bash(git diff *), Bash(git log *), TodoWrite
created: 2026-06-23
modified: 2026-06-23
reviewed: 2026-06-23
---

# Design: Deep Modules

From *A Philosophy of Software Design* (Ousterhout): the best modules are
**deep** — a small, simple interface hiding a large, complex implementation. A
**shallow** module is the opposite: an interface nearly as complicated as the
implementation it wraps, so it adds cognitive cost without removing much. This
skill assesses a module or interface for depth and points at the cheapest way to
deepen it.

The unit of design is *complexity at the boundary*: every method, parameter, and
exception a caller must understand is interface cost; everything the module
handles for them is the benefit. Depth is the ratio.

## When to Use This Skill

| Use this skill when... | Use something else instead when... |
|---|---|
| Designing a new module/class/API surface and choosing what to expose | Hunting correctness bugs → `code-quality-plugin:code-review` |
| A class boundary "feels" thin — pass-through methods, leaky config | Cyclomatic/cognitive metrics on a function → `code-quality-plugin:code-complexity` |
| Deciding whether to split or merge two modules | Removing duplication specifically → `code-quality-plugin:dry-consolidation` |
| Reviewing whether an abstraction earns its keep | Restructuring toward pure functions → `code-quality-plugin:code-refactor` |

## Core Principle

| Signal of a **deep** module | Signal of a **shallow** module |
|---|---|
| Few public methods, many private | Public surface ≈ implementation size |
| Caller passes intent, not mechanism | Caller must orchestrate internal steps |
| Defaults handle the common case | Every caller re-specifies the same config |
| Errors handled or masked internally | Exceptions leak the implementation's internals |
| Name describes *what*, not *how* | Name encodes the mechanism (`HashMapUserCache`) |

Two recurring deepening moves: **pull complexity downward** (the module, not its
callers, absorbs the hard case — a class with N callers pays once, they pay N
times) and **design it twice** (sketch two genuinely different interfaces before
committing; the second exposes the first's accidental complexity).

## Parameters

Parse `$ARGUMENTS`:

- **Target** (optional, first positional) — a file, module, directory, or diff
  to assess. If absent, default to the current change (`git diff HEAD` + staged)
  and say so.

## Execution

Execute this depth assessment:

### Step 1: Map the interface vs the implementation

For the target, list the **public surface** (methods, params, required config,
thrown exceptions, ordering constraints a caller must obey) and estimate the
**implementation weight** behind it. State the depth verdict in one line: *deep*,
*shallow*, or *mixed*.

### Step 2: Locate the shallowness

For each shallow point, name the specific cost the caller pays and why it leaks:

- **Pass-through methods** that only forward to another layer (collapse the layer)
- **Config a caller must always set** the same way (push a default downward)
- **Internal exceptions** surfacing as the public contract (mask or translate)
- **Ordering / temporal coupling** ("call `init()` before `run()`") (encapsulate)
- **Information leakage** — the same design decision known in two modules

### Step 3: Recommend the cheapest deepening

Per finding, give the move (pull complexity down / merge the shallow layer /
add a default / design-it-twice the interface) and the resulting smaller
interface. Prefer one deeper module over two shallow ones **only** when they
share a secret; do not merge modules that are genuinely independent (that is
the opposite failure — a god module).

### Step 4: Report

Emit: target, depth verdict, the shallow points (ordered by caller cost), and
the recommended interface change for each. Keep recommendations behaviour-
preserving — this is an interface-shape review, not a rewrite.

## Anti-patterns

| Mistake | Correct approach |
|---|---|
| Treating "more, smaller classes" as always better | Classitis makes shallow modules; depth, not count, is the goal |
| Merging two modules that share no secret | That builds a god module — merge only on shared information |
| Adding a config knob "for flexibility" | Each knob is interface cost paid by every caller; default it |
| Exposing an exception because it was easy | Define away or mask errors the caller cannot act on |

## Quick Reference

| Symptom | Deepening move |
|---|---|
| Pass-through / wrapper method | Collapse the layer |
| Repeated caller config | Push a default downward |
| Leaky exceptions | Mask or translate at the boundary |
| "Call A before B" | Encapsulate the sequence |
| Two interfaces both plausible | Design it twice, pick the smaller surface |

## Related

- `code-quality-plugin:code-complexity` — function-level cyclomatic/cognitive
  metrics (this skill works at the *interface* level above that)
- `code-quality-plugin:code-refactor` — the mechanical moves that execute a
  deepening once it's chosen
- `code-quality-plugin:dry-consolidation` — information leakage is often
  duplication; dedupe is one deepening move
- `software-design-plugin:design-by-contract` — what the deepened interface
  should promise its callers
