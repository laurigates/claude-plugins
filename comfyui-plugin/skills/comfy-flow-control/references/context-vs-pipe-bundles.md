# ComfyUI flow control — Context vs Pipe Bundles

rgthree `Context` vs easy-use `pipeIn`/`pipeOut`: field access, editing, unpacking, and bridging. Entry point: [`../SKILL.md`](../SKILL.md).

## Context vs pipe bundles

Both rgthree's `Context` and easy-use's `pipeIn`/`pipeOut` carry a
multi-typed bundle on a single wire. They are not interchangeable.

| | rgthree Context | easy-use pipe |
|---|---|---|
| Wire type | `RGTHREE_CONTEXT` (custom) | `PIPE_LINE` (custom) |
| Field access | Named (model / clip / vae / positive / negative / latent / image / seed) | Positional (model, pos, neg, latent, vae, clip, image, seed) |
| Override / edit mid-graph | `Context Merge` / `Context Merge Big` | `pipeEdit` |
| Unpack | `Context Switch` selects between multiple full contexts; individual fields auto-emerge from the Context node's right side | `pipeOut` emits all 8 slots; or downstream nodes consume `PIPE_LINE` directly |
| Bridge between | Convert manually: unpack with `Context` outputs → repack with `pipeIn` (and vice-versa) | Same, reverse |
| Best for | Sharing a stable model/clip/vae across many subgraphs | easy-use's own ecosystem (its samplers and pre-samplers expect PIPE_LINE) |

Mixing the two in one workflow is allowed but every cross-bridge is a
manual repack. Pick one bundle convention per workflow.
