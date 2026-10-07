# ComfyUI debug & preview — Telemetry and Profiling

VRAM / CPU / RAM telemetry nodes, per-section timing with `TimerNodeKJ`, and which layer to profile a slow workflow at. Entry point: [`../SKILL.md`](../SKILL.md).

## System telemetry

For figuring out what's eating VRAM / CPU / RAM mid-graph:

| Node | What it reports | When called |
|---|---|---|
| Crystools `CUtilsStatSystem` | CPU %, RAM used/total, GPU VRAM used/total (per-card) | Re-polls every time its output is consumed |
| kjnodes `VRAM_Debug` | One-shot VRAM snapshot to console | When the node executes |
| kjnodes `TimerNodeKJ` | Wall-clock elapsed time between start/end of a section | When the end node executes |
| kjnodes `Sleep` | Pauses execution for N seconds (throttling, not telemetry) | When executed |

### Per-section timing

```
                ┌─► TimerNodeKJ (start) ──────► (just a pass-through tag)
                │
upstream value ─┤
                │   (do stuff in between)
                │
                └─► TimerNodeKJ (end) ──► duration_seconds (FLOAT)
                                              │
                                              ▼
                                  bjornulf `ShowFloat`
                                  or DreamFloatToLog
```

Wire the same TimerNodeKJ id on both sides — the node remembers the
start timestamp keyed by its instance and emits a duration on the
"end" port.

## Counter-pattern: timing/profiling vs the wrong layer

If a workflow is slow and you want to find the slow node:

- ✅ Use `TimerNodeKJ` around suspected sections.
- ✅ Use `CUtilsStatSystem` to log VRAM through the run.
- ✅ Check the ComfyUI server log (`journalctl -u comfyui.service`)
  — every node logs its execution time at the end of the run.
- ❌ Don't add `Sleep` "to give the GPU time" — it doesn't help,
  ComfyUI is synchronous within a queue.

For deep model-level profiling (CUDA timelines, sageattn vs flash
attention comparisons, kernel-level), this skill is the wrong layer
— consult the model-family skill (e.g. `wan` for radial sage
attention discussion).
