# ComfyUI debug & preview — Recipes

Worked inspection graphs. Entry point: [`../SKILL.md`](../SKILL.md) § Recipes.

## Recipes

### "Why is my prompt different from what I typed?"

After all wildcard expansion, LoRA trigger autoload, and string
manipulation, you want to see the literal STRING that hits the text
encoder:

```
(your full prompt-assembly chain)
                │
                ▼
       (output STRING)
                │
       ┌────────┴────────┐
       │                 │
       ▼                 ▼
  CLIPTextEncode    ShowText (pysssss)
```

The `ShowText` widget will display the resolved prompt — visible in
the editor after queue. Useful for catching wildcards that didn't
resolve (`__styles__` remained literal because the file was
missing), or LoRA tags that came back empty.

### Per-step time budget

You want to know how long each sampler in a 3-sampler chain takes:

```
LoadImage ─► TimerNodeKJ(start, id=t1) ─► Sampler#1 ─► TimerNodeKJ(end, id=t1) ─► dt1
                                              │              │
                                              │              ▼ DreamFloatToLog
                                              │
                                              └► TimerNodeKJ(start, id=t2) ─► Sampler#2 ─► …
```

Three Timer pairs, three durations logged. After the run, check
the server log or the `DreamLogFile` output for a per-sampler
breakdown.

### VRAM watch during a long batch

```
LoadImage ──► CUtilsStatSystem ──► (continues to KSampler)
                    │
                    ▼ (writes a line per-poll to log)
              DreamStringToLog
```

`CUtilsStatSystem` polls VRAM on each evaluation. Wire its output
through a logger so each queue tick records GPU state — easy to
correlate OOMs with workflow position.

### Surface batch counts before sampling

```
LoadImageBatchFromDir ──► IMAGE ───────► (downstream sampler)
                            │
                            ▼
                  GetImageSizeAndCount ──► width / height / batch_count
                                                          │
                                                          ▼
                                                   ShowInt
```

Before queuing a big batch, glance at the count to confirm you
didn't accidentally load a directory of 500 images when you meant 5.
