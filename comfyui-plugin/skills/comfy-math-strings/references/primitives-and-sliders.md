# ComfyUI math & strings — Primitives and Sliders

Constant, slider, seed and range source nodes, plus the seed strategy. Entry point: [`../SKILL.md`](../SKILL.md).

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
