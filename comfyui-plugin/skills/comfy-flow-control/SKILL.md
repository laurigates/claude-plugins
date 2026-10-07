---
created: 2026-07-07
modified: 2026-07-31
reviewed: 2026-07-07
name: comfy-flow-control
description: >-
  ComfyUI routing nodes: typed switches, index switches, broadcast (Anything Everywhere), pipe/context bundles, for/while loops, ExecutionBlocker gates. Use when wiring where a signal routes in a workflow.
allowed-tools: Read, Grep, Glob
---

# ComfyUI flow control

Routing, switching, broadcast, bundling, looping, gating. *Where does
the signal go* once the decision is made.

Six packs on this install contribute flow-control primitives. Each has
overlapping options and pack-specific quirks — the goal of this skill
is to pick the right one in one decision, not browse a dropdown.

## When to Use This Skill

| Use this skill when... | Use instead when... |
|---|---|
| Wiring how a signal routes, switches, broadcasts, loops, or is gated | Forming the predicate that drives the route -> `comfy-conditionals` |
| Picking a switch / index-switch / broadcast node | Debugging or inspecting a routed value -> `comfy-debug-preview` |

## Sources of truth

- `custom_nodes/rgthree-comfy/__init__.py` — context bundles, Any Switch, Power Lora Loader, fast groups muter (frontend-only)
- `custom_nodes/cg-use-everywhere/__init__.py` — broadcast "Anything Everywhere" sentinels
- `custom_nodes/ComfyUI-Crystools/crystools/nodes_switch.py` — type-typed CSwitchBoolean* family
- `custom_nodes/comfyui-impact-pack/modules/impact/special_samplers.py` and `core.py` — ImpactSwitch (`GeneralSwitch`/`GeneralInversedSwitch`), ImpactConditionalBranch, ExecutionOrderController
- `custom_nodes/comfyui-easy-use/py/nodes/logic.py` and `flow.py` — easy switches, pipes, forLoop, whileLoop, blocker
- ComfyUI core — built-in `ComfySwitchNode` (boolean toggle between two same-type inputs)

## Pick-a-switch decision

| You have… | Selector | Best node | Why |
|---|---|---|---|
| 2 IMAGE inputs, BOOLEAN selector | bool | `easy imageSwitch` or Crystools `CSwitchBooleanImage` | Lazy: only the chosen branch runs |
| 2 ANY inputs, BOOLEAN selector | bool | Crystools `CSwitchBooleanAny` | Lazy; cleanest signature |
| 2 STRING inputs, BOOLEAN selector | bool | `easy textSwitch` or Crystools `CSwitchBooleanString` | Both lazy |
| 2 CONDITIONING inputs, BOOLEAN | bool | Crystools `CSwitchBooleanConditioning` | Lazy; native CONDITIONING type |
| 2 LATENT / MASK inputs, BOOLEAN | bool | Crystools `CSwitchBooleanLatent` / `CSwitchBooleanMask` | Lazy; typed |
| N ANY inputs, INT selector (3-20) | index | `easy anythingIndexSwitch` (up to 20) | Only easy-use scales past 2 inputs |
| N IMAGE / TEXT / CONDITIONING, INT | index | `easy imageIndexSwitch` / `easy textIndexSwitch` / `easy conditioningIndexSwitch` | Typed N-way |
| K ANY inputs, "first non-None wins" | any | rgthree `Any Switch` | Pick the first connected/non-empty input |
| 1 ANY input → 2 ANY outputs (demux) | bool | Crystools `CSwitchFromAny` | Unique: output-side mux. Bool routes the *one* input to one of two outputs |
| 2 BOOLEAN inputs that disagree | logic | `easy compare` or `ImpactCompare` then a switch above | Predicate formation lives in `comfy-conditionals` |
| Toggle entire LoRA stack on/off | bool | rgthree `Power Lora Loader` with toggles per row | Single node holds the stack + per-LoRA enable/strength |
| Mute/bypass a whole group of nodes | mouse | rgthree fast groups muter (frontend) | Right-click group → Mute / Bypass. No node needed |

### Input-side vs output-side mux

- **Input-side mux** (the standard pattern): N inputs → 1 output. The
  switch decides which input to forward. The bool/index selector reads
  *before* the upstream graph evaluates, so unselected branches can
  often be skipped (see lazy-vs-eager below).
- **Output-side mux** (Crystools `CSwitchFromAny` only): 1 input → 2
  outputs. The bool picks which output port receives the value; the
  other port emits None / a default. Use this when *one upstream*
  feeds two divergent downstream paths and you want to send it to only
  one at a time.

### Lazy vs eager evaluation

Lazy switches mark unselected branches as "do not evaluate", so the
upstream chain feeding the discarded branch is skipped entirely. Saves
GPU and time. Eager switches force every upstream branch to compute
even if its output gets thrown away.

| Lazy (skip unselected upstream) | Eager (run all branches always) |
|---|---|
| `easy ifElse`, `easy imageSwitch`, `easy textSwitch`, `easy anythingIndexSwitch` (and the typed `*IndexSwitch` siblings), `easy blocker` (downstream blocker) | `ImpactSwitch` / `GeneralSwitch` (data routing only) |
| All `CSwitchBoolean*` (Crystools) | `CSwitchFromAny` (must compute input before routing) |
| `ImpactConditionalBranch`, `ImpactConditionalBranchSelMode` | rgthree `Any Switch` (selects after upstream resolves) |

When the unselected branch is cheap (a constant or a small VAEDecode),
the difference is invisible. When it's a sampler chain, lazy switches
save tens of seconds per queue.

## Broadcast routing — `cg-use-everywhere`

The `Anything Everywhere` family doesn't have output ports. You wire a
value (model / clip / vae / seed / conditioning / anything) *into* the
node, and it acts as an invisible producer: any *unconnected* input
slot of the matching type elsewhere in the graph receives the value
automatically.

| Node | Use when |
|---|---|
| `Anything Everywhere` | One MODEL or VAE is reused by 6 nodes scattered across the graph — declare once, skip 6 reroute wires |
| `Anything Somewhere` | Regex-filtered: broadcasts only to inputs whose *socket name* matches the regex you set on the broadcaster |
| `Anything Everywhere Triplet` | Positive + negative + latent triplet bundle (the SDXL/Flux conditioning trio) |
| `Seed Everywhere` | Deprecated; the frontend auto-rewrites to a regular `Anything Everywhere` connected to INT |

**Silent-failure mode**: if two broadcasters carry compatible types
and both could match an empty socket, *one of them wins* (depends on
node id ordering) and the other is silently ignored. Color the broadcasters
in the UI so the routing is visible — they're invisible by design and
hard to debug otherwise. When debugging, replace with explicit reroutes
to see exactly where each value lands.

Use broadcast for **scalars and constants** (seed, model, vae, a
shared prompt). Avoid for transient intermediate values whose meaning
shifts as the graph runs — explicit wires there make the workflow
more legible.

## Context vs pipe bundles

rgthree `Context` and easy-use `PIPE_LINE` both carry a multi-typed bundle on one wire but are not interchangeable — pick one convention per workflow. Field-by-field comparison: [references/context-vs-pipe-bundles.md](references/context-vs-pipe-bundles.md).

## Loops

Before wiring `easy forLoopStart/End` or `easy whileLoopStart/End`, read [references/loops.md](references/loops.md): loops expand at queue time into copies of the body, and a `whileLoopEnd` without a terminating condition hangs the queue.

## Execution gating

| Primitive | What it does |
|---|---|
| `easy blocker` | Pass-through; if `continue=False` returns an `ExecutionBlocker` sentinel. Any downstream node touching the sentinel is silently skipped. |
| `ImpactConditionalStopIteration` | Inside an Impact iterator (detector → detailer loop), halts the loop when its BOOLEAN input is True. |
| `ImpactExecutionOrderController` | Pins a side-effect node (SaveImage, log, webhook) to run before / after a designated other node. Used when ComfyUI's free reordering picks the wrong sequence. |

`ExecutionBlocker` is the canonical "kill this path" primitive in
ComfyUI — see `comfy-conditionals` for predicate formation and
detailed semantics (Preview Bridge consumes the sentinel silently;
SaveImage downstream is the abort target).

## Recipes

Worked graphs — a toggleable LoRA stack with bypass, an optional upscale pass behind a lazy switch, and migrating a workflow off broadcast wires for review — are in [references/recipes.md](references/recipes.md).

## Gotchas

When a switch picks the wrong input, an eager branch runs anyway, or a routed value vanishes, check [references/gotchas.md](references/gotchas.md) (`ComfySwitchNode` input overrides its widget, `Any Switch` is eager, Preview Bridge swallows `ExecutionBlocker`, BOOLEAN-only `cond`, Context Big drops mismatched slots, loops expanding at queue time).

## Cross-refs

- `comfy-conditionals` — forming the boolean / index that feeds these
  switches. Predicates, comparisons, null checks, ExecutionBlocker
  patterns.
- `comfy-prompting` — `Power Lora Loader` plays nicely with LoRA
  trigger-word autoload nodes; see the cross-ref there for the full
  recipe.
- `comfy-debug-preview` — Preview Bridge details, FastPreview as the
  blocker-aware alternative.
- `comfy-math-strings` — primitive sources (PrimitiveBoolean, INT/FLOAT
  constants, sliders) that drive these switches.

## Things this skill does NOT cover

- **Predicate formation** — how to build the boolean that feeds a
  switch. → `comfy-conditionals`.
- **Reroute nodes for visual cleanup** — those are frontend-only and
  don't affect execution; covered by `comfy-workflow-layout` and
  rgthree's UI affordances.
- **Sampler / model routing** (KSampler vs DPMPP vs Euler, model
  loader switching) — that's model-family work; see `wan`, `z-image`,
  `hidream-o1` skills.
- **Subgraph composition** — packaging part of a workflow into a
  reusable subgraph. That's a project `CLAUDE.md` topic under
  "Editing workflow JSON".
