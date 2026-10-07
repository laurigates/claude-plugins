# ComfyUI conditionals — Probes, Logicutils, Iterator Stop

Per-node detail behind the "Which compare node?" table: the null / empty / type probes with their use cases, the `comfyui-logicutils` string / bitwise / invert gates, and the Impact iterator stop. Entry point: [`../SKILL.md`](../SKILL.md).

## Null / empty / type probes

| Probe | Returns BOOLEAN when |
|---|---|
| `easy isNone` | Input is None / unwired / a placeholder |
| `ImpactIfNone` | Same, plus passes the non-None value through (combines probe + pass-through) |
| `easy isMaskEmpty` | All mask pixels are zero (no positive area) |
| `easy isFileExist` | Filesystem path resolves to a real file |
| `easy isSDXL` | The CLIP / pipe / model identifies as SDXL architecture |

Use cases:

- Detector pipelines: `isMaskEmpty(face_mask)` → blocker to skip
  detailer when no face is found.
- Optional reference image: `isFileExist(ref_path)` → switch between
  "use reference" and "no reference" branches.
- Multi-architecture workflows that need different sampler defaults:
  `isSDXL(pipe)` → switch sampler configuration.

## Logicutils — strings, bits, regex

`comfyui-logicutils` is the sole source for:

- **Regex / substring on strings** — `LogicGateCompareString` (also
  registered as `AContainsB`). Pass a regex pattern in `b`, a string
  in `a`, get BOOLEAN.
- **Bitwise integer ops** — for flags packed into a single INT.
  Niche; mostly useful when interfacing with external systems that
  send flag bitmasks.
- **`LogicGateInvertBasic`** — generic invert that handles any
  truthy/falsy input (more lenient than `ImpactNeg`, which expects
  strict BOOLEAN).

## Iterator stop

`ImpactConditionalStopIteration` — only useful inside an Impact
detector→detailer iterator loop. Takes a BOOLEAN; when True, halts
the iterator's next round. The iterator must support stop signals
(detector-pipeline variants do; non-iterating Impact paths ignore it).
