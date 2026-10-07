# ComfyUI math & strings — Recipes

Worked compute / string-assembly graphs. Entry point: [`../SKILL.md`](../SKILL.md) § Recipes.

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
substitution plus `%NodeName.widget%`. A run-signature shape
(sampler/scheduler/seed) keeps runs distinguishable, but the exact
convention is per-install — see "Naming conventions are per-install" in
`comfy-workflow-json`. When the native substitution isn't enough (e.g. you
need to strip an extension from a source filename), assemble the prefix via:

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
                 in_1: "<bucket>/%date:yyyy-MM-dd%/%date:hhmmss%_%ksampler.sampler_name%_%ksampler.scheduler%_s%ksampler.seed%_"
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
