# ComfyUI flow control — Recipes

Worked routing graphs. Entry point: [`../SKILL.md`](../SKILL.md) § Recipes.

## Recipes

### Toggleable LoRA stack with bypass

You have 3–8 LoRAs stacked into a chain. You want each one individually
toggleable, with a master "all off" too.

```
UNETLoader ─┐
            │
            ▼
rgthree Power Lora Loader  ← per-row: enabled (bool), name, strength
            │
            ▼
ModelSamplingAuraFlow (or whatever)
```

- One node holds the stack. UI per-row toggle + strength.
- Group the loader + downstream sampler nodes; right-click → Mute
  Group to bypass the whole branch when prototyping.
- To make a *single* LoRA toggleable as a separate node, wrap with
  Crystools `CSwitchBooleanAny`: bool=on → goes through `LoraLoaderModelOnly`,
  bool=off → bypasses straight to the next stage.

### Optional upscale pass with lazy switch

User sometimes wants a 2× upscale, sometimes doesn't. Without lazy
evaluation, the upscale chain (model loader + KSampler + VAEDecode)
runs even when discarded.

```
                              ┌── on_true: UpscaleModelLoader → Sampler → VAEDecode ──┐
SaveImage upstream ────────── ┤                                                       ├── SaveImage
                              └── on_false: passthrough ─────────────────────────────┘
                                 ▲
                                 │
                              Crystools CSwitchBooleanImage (lazy)
```

- The Crystools switch is lazy → when bool=False, the entire upscale
  chain is skipped, not just discarded.
- Bool can come from a `PrimitiveBoolean`, a `RgthreeContext` field, or
  an `easy compare` predicate.

### Migrating a workflow off broadcast wires for review

When sharing a workflow that uses `Anything Everywhere`, the rest of
the graph has unconnected input sockets that "look" wrong but work
fine because of the broadcaster. For readability when sending the
workflow to someone:

1. Right-click `Anything Everywhere` → "Show connections" (frontend
   flag in the rgthree side panel) — renders dashed lines.
2. Manually wire what the broadcaster was implicitly doing.
3. Delete the broadcaster node.

Reverse the process when receiving a wired workflow you want to
clean up.
