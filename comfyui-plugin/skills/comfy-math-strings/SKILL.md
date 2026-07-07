---
created: 2026-07-07
modified: 2026-07-07
reviewed: 2026-07-07
name: comfy-math-strings
description: >-
  ComfyUI compute/string nodes: constants, sliders, math expressions, string concat/split/replace/regex, type conversion, JSON/list utilities. Use when computing a value or assembling a string in a workflow.
allowed-tools: Bash, Read, Grep, Glob
---

# ComfyUI math & strings

Compute and assemble. Numbers in, numbers out; strings in, strings
out; primitives that hold a constant; sliders that expose a tunable.

The split:

| Pack | Niche |
|---|---|
| `comfyui-kjnodes` | Primitives (BOOL / INT / Float / String / Multiline), SimpleCalculatorKJ, JoinStrings / JoinStringMulti, AppendStringsToList, Something/WidgetToString |
| `comfyui_essentials` | Math hierarchy: SimpleMath / SimpleMathFloat / SimpleMathInt / SimpleMathDual (AST-based) |
| `comfyui-custom-scripts` (pysssss) | `MathExpression` (full numpy + math imports), `StringFunction` (regex), `StringNodes` (split/case/trim) |
| `comfyui-mxtoolkit` | `mxSeed`, `mxSlider`, `mxSlider2D` widget-driven values |
| `bjornulf_custom_nodes` | `AnythingToText` / `AnythingToInt` / `AnythingToFloat`, TextReplace, CombineTexts, RandomLineFromInput |
| `ComfyUI-Crystools` | `CBoolean` / `CInteger` / `CFloat` / `CText` / `CTextML` primitives, `CJsonFile` / `CJsonExtractor` / `CListAny` / `CListString` |
| `comfyui-easy-use` | `easy string` / `easy int` / `easy float` identity nodes, `easy rangeInt` |
| `comfyui-dream-project` | `DreamCalculation`, `DreamLinear`, sine/saw/triangle waves (animation-flavored, see "out of scope") |
| `comfyui_yvann-nodes` | `FloatToInt`, `InvertFloats`, `MaskToFloat`, `FloatsToWeightsStrategy` |

## When to Use This Skill

| Use this skill when... | Use instead when... |
|---|---|
| Computing a value or assembling a string in a workflow | Forming a boolean from that computation -> `comfy-conditionals` |
| Converting between types (anything -> int/float/string) | Displaying the result -> `comfy-debug-preview` |

## Sources of truth

- `custom_nodes/comfyui-kjnodes/nodes/nodes.py` — primitives, JoinStrings, Something/WidgetToString
- `custom_nodes/comfyui_essentials/misc.py` — SimpleMath family
- `custom_nodes/comfyui-custom-scripts/py/math_expression.py` — pysssss MathExpression
- `custom_nodes/comfyui-mxtoolkit/` — slider widgets
- `custom_nodes/ComfyUI-Crystools/crystools/nodes_*.py` — primitives, list helpers, JSON extractor
- `custom_nodes/bjornulf_custom_nodes/` — Anything-To-* converters

## Math — which node?

| Need | Best node | Why |
|---|---|---|
| Single FLOAT expression, simple ops | `SimpleMathFloat` (essentials) | Tight; one expression in, FLOAT out |
| Single INT expression | `SimpleMathInt` | Same, INT result |
| Multi-variable expression (a, b, c, d) — `(a+b)/c` etc. | `SimpleMath` | AST-based eval over named inputs; safe (no module imports) |
| Two values, binary op (add/sub/mul/div/pow) | `SimpleMathDual` | Op picker widget |
| Many variables (a–j) | `SimpleCalculatorKJ` (kjnodes) | Up to 10 named inputs |
| Need numpy / math import — `np.sqrt`, `math.pi`, `np.clip`, etc. | `MathExpression` (pysssss) | Full module access, expression as string |
| Animation curve over a frame index — linear ramp, sine wave | `DreamLinear`, `DreamSineWave` etc. | Built-in time/frame parameter |
| Float ↔ INT | yvann `FloatToInt` (round/ceil/floor), `AnythingToInt` (bjornulf) | yvann has the rounding mode; bjornulf is the lenient any-input version |
| Invert FLOAT (1−x or −x) | yvann `InvertFloats` | Mode picker |

### Math hierarchy in one line

`SimpleMathFloat` < `SimpleMath` < `SimpleCalculatorKJ` < `MathExpression`

Pick the simplest one that compiles. `MathExpression` (pysssss) is the
"escape hatch" — full numpy + math imports, but a typo crashes the
node with an opaque traceback. Use it only when AST-safe `SimpleMath`
can't express what you need.

### `SimpleMath` syntax

Variables: `a`, `b`, `c`, `d` (wire them as inputs).
Operators: `+ - * / // % **`, parentheses, unary `-`.
Functions: `min`, `max`, `abs`, `round`, `int`, `float`.

```
SimpleMath:
   expression: int(sqrt(a * 1000000 * b) / 8) * 8
   a = megapixels
   b = aspect_ratio
   → width snapped to multiple of 8
```

`SimpleMath` does NOT support `sqrt` natively — drop to
`MathExpression` for that. Actual AST-safe set is limited; check the
node source for the allowed call list.

### `MathExpression` syntax

```
import numpy as np
import math

# Expression — single line:
int(math.sqrt(a * 1e6 * b) / 8) * 8

# Or use numpy:
int(np.sqrt(a * 1e6 * b) / 8) * 8
```

You write an expression string referencing input variable names that
the node has registered. The node has `math` and `numpy` (as `np`)
already imported. Errors surface as red node + traceback in the
server log; nothing in the workflow UI.

## Strings — concat, replace, regex, split

| Need | Best node |
|---|---|
| Concat a few strings with a delimiter | `JoinStrings` (kjnodes, 5-arg) |
| Concat many | `JoinStringMulti` (kjnodes, dynamic N inputs) |
| Concat 2 with no delimiter | `CombineTexts` (bjornulf) |
| Find/replace literal | `TextReplace` (bjornulf) |
| Find/replace regex | `StringFunction` (pysssss; regex_mode toggle) |
| Pick random line from multiline | `RandomLineFromInput` (bjornulf) |
| Split on delimiter | `StringNodes` (pysssss, operation picker) or `TextSplitByDelimiter` (mixlab) |
| Add line numbers | `AddLineNumbers` (bjornulf) |
| Tokenize | `DreamStringTokenizer` (dream-project, word-splitter) |
| Build STRING from a list | `AppendStringsToList` (kjnodes) |

### Single-line vs multiline

- `StringConstant` (kjnodes) — single line, no embedded newlines
- `StringConstantMultiline` (kjnodes) — multiline, ideal for prompt
  bodies, JSON snippets, multi-clause text
- `CText` (Crystools) — single line
- `CTextML` (Crystools) — multiline

Pick multiline for any string longer than ~80 chars or any string
with embedded newlines. Single-line variants are for short labels and
filenames.

### Regex via `StringFunction`

```
StringFunction (pysssss):
   action: replace
   regex_mode: ON
   text:    "michael.jpg"
   find:    "\.(png|jpg|jpeg|webp)$"
   replace: ""
   → "michael"
```

Useful for stripping extensions from a filename (the exact pattern
we hit in the `comfy-image-utils` recipe set). Action picker also
supports `append`, `replace`, `tidy tags` (the last one normalizes
commas/spaces in tag lists for booru-style prompts).

## Type conversion

`bjornulf`'s `AnythingTo*` family is the most lenient — it accepts
literally any input type and produces the named scalar:

| Node | Output | Notes |
|---|---|---|
| `AnythingToText` | STRING | `str(x)`-equivalent on any input |
| `AnythingToInt` | INT | Coerces float / string / bool; raises if string isn't parseable |
| `AnythingToFloat` | FLOAT | Same, FLOAT target |
| `SomethingToString` (kjnodes) | STRING | Similar to bjornulf's AnythingToText |
| `WidgetToString` (kjnodes) | STRING | Reads a specific widget by name from a target node — useful for surfacing arbitrary widget values into the data flow |

`easy string` / `easy int` / `easy float` (easy-use) are **identity
nodes** — they don't convert, just pass through. Their purpose is to
expose a widget UI for a value that downstream nodes will consume; a
debug-friendly handle.

## Primitives & sliders

| Source | What it gives you |
|---|---|
| kjnodes `INTConstant` / `FloatConstant` / `StringConstant` / `BOOLConstant` / `StringConstantMultiline` | Plain widget-input constants |
| Crystools `CInteger` / `CFloat` / `CText` / `CTextML` / `CBoolean` | Same, plus some have widget toggle for live update |
| mxtoolkit `mxSlider` | Single tunable INT or FLOAT slider with live drag |
| mxtoolkit `mxSlider2D` | 2D drag-pad emitting two independent values |
| mxtoolkit `mxSeed` | INT pass-through with a seed-control widget (random / fixed / increment) |
| `easy rangeInt` | Emit a range of INTs — `start`, `end`, plus `step` mode or `num_steps` mode |
| `RepeatImageToCount` is image-specific (covered in `comfy-image-utils`); for value-list repetition use Python via JoinString | |

### Seed strategy

ComfyUI core's `Seed` node and the `seed` widget on `KSampler` both
support fixed/random/increment. `mxSeed` adds a slider-style UI and a
pass-through value (useful when one seed feeds multiple samplers and
you want it visible). `Seed Everywhere` (cg-use-everywhere) is
deprecated in favor of `Anything Everywhere` connected to an INT.

## JSON & lists (Crystools)

| Node | Use |
|---|---|
| `CJsonFile` | Load a JSON file from disk; emits the parsed structure as a JSON object |
| `CJsonExtractor` | Extract values from a JSON object via dot-path / JSONPath syntax |
| `CListAny` | Build / pass a list of any type |
| `CListString` | Build a list of strings (sometimes more convenient than concatenation) |

Typical use: load a config JSON, extract one value, feed into a
downstream node. The Crystools JSON nodes don't do JSON-write; for
that, save text via bjornulf `SaveText` or use the `MathExpression`
escape hatch.

## Recipes

### Resolution math from megapixels + aspect ratio

You want a target image size of "≈1 MP, 16:9 aspect, both dimensions
divisible by 8".

```
PrimitiveFloat (mp = 1.0) ──┐
                            ▼
PrimitiveFloat (ar = 16/9) ─►  MathExpression (pysssss)
                            ▲     expression: int(math.sqrt(a * 1e6 * b) / 8) * 8
                            │     a = mp, b = ar
                            ▼
                          width = 1336 (for ar=1.78)
                          (compute height by 1e6/width or as another expression)
```

Two `MathExpression` nodes: one for width, one for height = `int((a * 1e6) / b / 8) * 8`
with the same `mp` input and width as `b`. The 8-snapping handles
SD/Flux/Wan latent alignment automatically.

### Filename templating

`SaveImage.filename_prefix` accepts `%date:yyyy-MM-dd%` / `%date:hhmmss%`
substitution plus `%NodeName.widget%`. The **required shape** (mandatory
sampler/scheduler/seed run-signature) is the "Output filename_prefix
convention" in `.claude/rules/editing-workflow-json.md`; its "SaveImage
filename substitution" section covers the native syntax. When the native
substitution isn't enough (e.g. you need to strip an extension from a
source filename), assemble the prefix via:

```
LoadAndResizeImage ──► image_path (STRING, kjnodes)
                            │
                            ▼
                StringFunction (pysssss)
                   action: replace, regex: ON
                   find:    "\.(png|jpg|jpeg|webp)$"
                   replace: ""
                            │
                            ▼ (basename without ext, STRING)
              JoinStringMulti (kjnodes)
                 in_1: "nsfw/%date:yyyy-MM-dd%/%date:hhmmss%_%ksampler.sampler_name%_%ksampler.scheduler%_s%ksampler.seed%_"
                 in_2: <stripped basename>   # the <descriptor> segment
                            │
                            ▼
              easy imageSave (filename_prefix STRING input)
```

The `%date:...%` tokens are passed through verbatim; SaveImage's
internal substitution resolves them at save time. The
`%LoadImage.image%` widget-substitution is bypassed entirely — we
build the final string in the graph.

### Build a comma-separated tag list from individual triggers

Three LoRA trigger words plus a manual prompt, combined:

```
LoraLoaderVanilla (lora_1) ──► civitai_tags_list (STRING)  ──┐
LoraLoaderVanilla (lora_2) ──► civitai_tags_list (STRING)  ──┤
LoraLoaderVanilla (lora_3) ──► civitai_tags_list (STRING)  ──┤
PrimitiveStringMultiline ("a portrait of a woman") ───────────┤
                                                              ▼
                                              JoinStringMulti (delimiter = ", ")
                                                              │
                                                              ▼
                                                       CLIPTextEncode
```

Empty trigger strings produce an extra `, ` — pipe through
`StringFunction` (action: tidy tags) to collapse redundant separators.

### Range-driven batch

Generate 10 images at incrementing CFG values:

```
easy rangeInt
   start: 3,  end: 12,  num_steps: 10
        │
        ▼ (emits 10 INTs at execution)
   (route into a forLoopStart, each iteration sets KSampler.cfg)
```

Pair with `easy forLoopStart` / `forLoopEnd` (see `comfy-flow-control`)
for actual iteration.

## Gotchas

- **`SimpleMath` ≠ `MathExpression`.** Essentials' SimpleMath is
  AST-safe (no imports, limited function set — no `sqrt`, no `numpy`).
  Pysssss MathExpression has full `math` + `numpy` access. Don't mix
  them up.
- **kjnodes Constants vs Crystools Constants** — they look
  interchangeable. They mostly are, but Crystools' `CFloat` /
  `CInteger` widgets default to wider ranges and Crystools' multiline
  `CTextML` has different newline handling on Windows. Pick one pack
  per workflow for consistency.
- **`MathExpression` errors are server-side**. The node turns red but
  the error message ("Error executing MathExpression: NameError")
  lives in the ComfyUI server log (`journalctl -u comfyui.service`
  on this install). Add a `ShowAnything` on the output to confirm
  it's emitting what you expect.
- **`StringFunction` regex syntax is Python `re`**. Forward slashes
  are NOT escapes; backslashes are. `\.(png|jpg|jpeg|webp)$` works.
  `/\\.(png|jpg|jpeg|webp)$/` does not — that's JavaScript syntax.
- **`AnythingToInt` on a non-numeric string crashes**. `"3.14"` →
  fails; `"3"` → works; `3.14` (float) → 3. To coerce a possibly
  non-numeric STRING, route through `MathExpression` with
  `int(float(a) if a else 0)` and a defensive try wrapper.
- **`JoinStringMulti` shrinks dynamic inputs**. The first time you
  add a downstream consumer, the node grows its slot count. If you
  later disconnect, the empty slots stay around. Drop and re-add the
  node to compact.
- **`easy rangeInt` `num_steps` is INCLUSIVE on both ends**, so
  `start=0, end=10, num_steps=11` gives `[0, 1, 2, ..., 10]`. With
  `num_steps=10`, you get `[0, 1.11, ..., 10]` — not integer.
  Prefer the `step` mode when you want integer-only spacing.

## Cross-refs

- `comfy-conditionals` — feeding math output through a comparator
  to form a boolean predicate.
- `comfy-debug-preview` — `ShowAnything` / `DisplayAny` / `ShowFloat`
  for inspecting intermediate math results.
- `comfy-flow-control` — `easy rangeInt` feeding `forLoopStart`;
  primitives as switch selectors.
- `comfy-prompting` — string assembly for prompts (this skill is the
  primitive layer; `comfy-prompting` is the application).
- Project CLAUDE.md "SaveImage filename substitution" — native
  `%date:%`/`%NodeName.widget%` syntax that complements the
  string-graph approach.

## Things this skill does NOT cover

- **Animation schedulers** — `DreamSineWave`, `DreamSawWave`,
  `DreamTriangleWave`, `FloatsToWeightsStrategy`, frame-counter ops.
  These are math primitives but their application (AnimateDiff /
  IPAdapter transitions / weight schedules over frames) is its own
  domain. Future `comfy-animation-schedules` skill will cover this.
  For now: the nodes exist, they emit FLOATs / FLOAT lists driven by
  a frame index; consult the `comfyui-dream-project` and
  `comfyui_yvann-nodes` repos for application examples.
- **Display-only nodes** — `ShowText`, `DisplayAny`, `ShowFloat`,
  Crystools `CConsoleAny*`. Those are inspection, not computation;
  see `comfy-debug-preview`.
- **Image / mask arithmetic** — `ImageBlend`, `MaskComposite`. Those
  are pixel ops, not scalar math; see `comfy-image-utils`.
- **Sampler internals** — `cfg`, `denoise`, step counts. Math-driven
  scheduling of those values is fine, but the values themselves
  live in the model-family skills.
