---
created: 2026-07-07
modified: 2026-07-31
reviewed: 2026-07-07
name: comfy-conditionals
description: >-
  ComfyUI predicate/boolean nodes: compare, AND/OR/XOR/NOT, ternary, null/empty/type probes, ExecutionBlocker. Use when forming the boolean that drives a workflow switch or blocker.
allowed-tools: Read, Grep, Glob
---

# ComfyUI conditionals

Predicates → boolean → branch. *How the decision is formed*, not where
the signal goes after.

Four packs contribute predicate primitives. The split:

| Pack | Primary niche |
|---|---|
| `comfyui-easy-use` | `easy ifElse`, `easy compare`, `easy blocker`, and the `easy is*` probes — the broadest, most-used predicate kit |
| `comfyui-impact-pack` | `ImpactCompare` + `ImpactConditionalBranch` (lazy) + `ImpactIfNone` + `ImpactConditionalStopIteration` (Impact-iterator loop control) |
| `comfyui_essentials` | `SimpleCondition` (ternary), `SimpleComparison` (typed, epsilon-aware), `SimpleMathCondition` (boolean from math) |
| `comfyui-logicutils` | Bit-banging + regex-on-strings logic gates: `AContainsB`, bitwise And/Or/Xor/Not/Shift, generic Invert |

## When to Use This Skill

| Use this skill when... | Use instead when... |
|---|---|
| Forming the boolean/predicate that drives a switch or blocker in a workflow | Routing the signal after the decision is made -> `comfy-flow-control` |
| Comparing values, combining booleans, detecting null/empty | Computing a numeric (non-boolean) value -> `comfy-math-strings` |

## Sources of truth

- `custom_nodes/comfyui-easy-use/py/nodes/logic.py` — ifElse, compare, blocker, is* probes
- `custom_nodes/comfyui-impact-pack/modules/impact/special_samplers.py` — ImpactCompare, ImpactConditionalBranch
- `custom_nodes/comfyui_essentials/misc.py` — SimpleMath / SimpleCondition / SimpleComparison
- `custom_nodes/comfyui-logicutils/logic_gates.py` — logic gate nodes

## Which compare node?

| Need | Best node | Why |
|---|---|---|
| Compare two ANY values, any op (`==`, `!=`, `<`, `>`, `<=`, `>=`) | `easy compare` | Multi-op switcher widget, no type lock |
| Compare two INT/FLOAT, return BOOLEAN | `ImpactCompare` | Op picker (`a=b`, `a<>b`, `a>b`, `a<b`, `a>=b`, `a<=b`, `tt`/`ff` constants) |
| Compare two FLOAT with epsilon tolerance | `SimpleComparison` (essentials) | Floats are unsafe under `==` — epsilon-aware |
| Compare a string against a regex / substring | `LogicGateCompareString` / `AContainsB` (logicutils) | The only regex-on-string predicate available |
| Quick math → boolean (e.g. `(a+b) > c`) | `SimpleMathCondition` | Computes the expression and returns BOOLEAN in one node |
| Detect null / unwired input | `easy isNone` or `ImpactIfNone` | Returns BOOLEAN + passes value through |
| Detect empty mask (all zeros) | `easy isMaskEmpty` | Specifically tests MASK type |
| Detect SDXL vs SD1 model | `easy isSDXL` | Probes CLIP / pipe and identifies arch |
| Detect file path exists on disk | `easy isFileExist` | For input-validation gates |

### Type coercion footgun

`ImpactConditionalBranch.cond` is **BOOLEAN**. Don't feed it:

- `SimpleMathCondition` output → that's FLOAT (0.0 / 1.0) — convert via comparator first
- `easy compare` output → that IS BOOLEAN, fine
- `LogicGateCompare` output → BOOLEAN, fine
- A raw INT from a math node → not BOOLEAN; pass through `ImpactCompare` (`a > 0`) or convert

When in doubt, route through `easy compare` and pick the comparison operator that yields the boolean you want.

## Boolean algebra

For combining multiple predicates into one branch input:

| Operator | Node |
|---|---|
| AND / OR / XOR | `ImpactLogicalOperators` (op picker) |
| NOT | `ImpactNeg` |
| Bit-wise AND / OR / XOR / NOT / shift | logicutils `LogicGateBitwiseAnd` etc. (work on INT, not BOOLEAN) |
| Generic invert (works on any truthy/falsy) | `LogicGateInvertBasic` |

```
isMaskEmpty(face_mask) ──┐
                         ▼
                ImpactNeg (NOT)  ──┐
                                   ▼
            ImpactLogicalOperators (AND) ──→ ImpactConditionalBranch
                                   ▲
isFileExist(reference.png) ────────┘
```

This combination says: "face mask is non-empty AND reference image
exists on disk → run the detailer branch".

## Branching

### Lazy if-then-else (skips the discarded branch)

| Node | Behavior |
|---|---|
| `easy ifElse` | BOOLEAN selector, `on_true` / `on_false` inputs; only the chosen one is evaluated upstream |
| `ImpactConditionalBranch` | BOOLEAN `cond`; lazy `tt_value` / `ff_value` inputs |
| `ImpactConditionalBranchSelMode` | Same, but selection happens at execution time rather than prompt-queue time — needed when `cond` depends on something computed earlier in the same queue |

These are **predicate-side** nodes that ALSO act as switches — they
form the boolean *and* route in one step. If your predicate is simple
(one comparison) and the branches are large (samplers, models),
`ImpactConditionalBranch` is the cleanest single-node solution.

If the predicate is complex (multi-criteria), form it explicitly in
this skill's primitives, then pass the resulting BOOLEAN to a switch
from `comfy-flow-control`.

### Ternary (compute, don't route)

`SimpleCondition` (essentials) — given `condition`, returns `value_if_true`
or `value_if_false`. Both inputs are computed (eager), so it's a *value
picker*, not an execution gate. Use it for selecting between two
constants or already-computed scalars; never for selecting between
sampler chains.

## ExecutionBlocker — the kill-path primitive

`easy blocker` is the canonical "kill this path" node. Behavior:

- Input: any value + `continue` BOOLEAN.
- If `continue=True`: pass the value through unchanged.
- If `continue=False`: returns an `ExecutionBlocker` *sentinel*.

The sentinel propagates downstream: any node that receives an
`ExecutionBlocker` on any input is **silently skipped** (its
`execute()` is never called). The skip cascades through the rest of
the graph downstream of the blocker.

```
LoadImage ── easy compare (size > 1024) ─┐
                                         ▼
LoadImage ──────────────► easy blocker ───► ResizeImage ─► KSampler ─► SaveImage
                            ▲ continue
```

When the loaded image is smaller than 1024px, the blocker fires;
ResizeImage / KSampler / SaveImage are all skipped without errors.

### ExecutionBlocker gotchas

- **Preview Bridge swallows the sentinel** — see `comfy-flow-control`
  gotchas. The blocker fires, but a Preview Bridge tee downstream
  reports nothing visibly, *and* fails to propagate the abort. Use
  `FastPreview` (kjnodes) downstream of a blocker if you need
  visual confirmation.
- **Cannot be visualized** — there's no "is this currently blocked?"
  light. Add an `easy showAnything` on the BOOLEAN that drives the
  blocker to confirm at queue time.
- **No partial recovery** — once a path is blocked, every downstream
  node in that chain is skipped, period. To preserve a parallel path
  through the same upstream value, tee BEFORE the blocker, not after.

## Null / empty / type probes

For what each probe (`easy isNone`, `ImpactIfNone`, `easy isMaskEmpty`, `easy isFileExist`, `easy isSDXL`) returns and typical gating uses, see [references/probes-and-logicutils.md](references/probes-and-logicutils.md).

## Logicutils — strings, bits, regex

Regex-on-string predicates, bitwise INT gates, and the lenient `LogicGateInvertBasic` are detailed in [references/probes-and-logicutils.md](references/probes-and-logicutils.md).

## Iterator stop

`ImpactConditionalStopIteration` (Impact detector→detailer loops only): see [references/probes-and-logicutils.md](references/probes-and-logicutils.md).

## Recipes

Worked graphs — skip a face-detailer when no face is detected, a multi-criteria AND gate, and first-run vs rerun via file existence — are in [references/recipes.md](references/recipes.md).

## Gotchas

Before trusting a predicate, check [references/gotchas.md](references/gotchas.md): float `==`, blockers passing through lazy branches, `SimpleMathCondition` returning FLOAT, `easy isNone` on a pipe, and `AContainsB` being regex.

## Cross-refs

- `comfy-flow-control` — once the boolean is formed, this skill points
  at the switches that consume it (typed switches, ExecutionBlocker
  propagation, broadcast routing).
- `comfy-math-strings` — math primitives that feed comparisons
  (constants, sliders, SimpleMath expressions, `GetImageSize&Count`
  outputs).
- `comfy-debug-preview` — `ShowAnything` / `ShowText` for inspecting
  the BOOLEAN being passed to a branch at queue time.

## Things this skill does NOT cover

- **Switching / routing AFTER the decision** — that's `comfy-flow-control`.
- **Numerical computation that doesn't yield a BOOLEAN** —
  arithmetic, math expressions, string formatting → `comfy-math-strings`.
- **Image / mask manipulation upstream of the probe** — getting a
  mask in the first place via segmentation, detection, etc. is
  model-inference work, not utility.
- **Sampler-time conditionals** — model_sampling, CFG scheduling,
  step gating *within* the diffusion loop is sampler/model territory,
  not workflow logic.
