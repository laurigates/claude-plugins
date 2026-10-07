# ComfyUI conditionals — Recipes

Worked predicate → branch graphs. Entry point: [`../SKILL.md`](../SKILL.md) § Recipes.

## Recipes

### Skip face-detailer when no face detected

```
LoadImage ──► BBoxDetector ──► IMAGE/MASK output
                                    │
                                    ▼
                            easy isMaskEmpty ──► (BOOLEAN)
                                                    │
                                                    ▼ (invert: empty → skip)
                                              ImpactNeg
                                                    │
                                                    ▼
                            ┌───────► easy blocker ◄────── (the image+mask payload)
                            │           continue
                            ▼
                  (downstream FaceDetailer chain, silently skipped on empty)
```

`isMaskEmpty` → True when no face found → ImpactNeg flips it → False
→ blocker fires → FaceDetailer + SaveImage chain is skipped without
error.

### Multi-criteria gate

"Run the high-quality upscale path only if **the image is large AND
the reference exists AND we're not in SDXL mode**":

```
GetImageSize&Count(image) ──► width  ──► easy compare (> 1024) ──┐ (BOOL)
                                                                  │
easy isFileExist(ref_path) ──► (BOOL) ───────────────────────────┤
                                                                  │
easy isSDXL(pipe) ──► ImpactNeg (NOT SDXL) ──► (BOOL) ───────────┤
                                                                  ▼
                                              ImpactLogicalOperators (AND of 3)
                                                                  │
                                                                  ▼
                                                  ImpactConditionalBranch
                                                  tt = upscale chain
                                                  ff = passthrough
```

Three independent predicates combined with AND. The downstream branch
is fully lazy: when any predicate is False, none of the upscale chain
runs.

### Distinguish "first run" from "rerun" via file existence

Useful for caching: if an output file already exists, skip
regeneration.

```
easy isFileExist("output/cached_step1.png") ──► (BOOL)
                                                  │
                                                  ▼
                                  ImpactConditionalBranch
                                  tt = LoadImage from cache
                                  ff = run full pipeline + SaveImage
```
