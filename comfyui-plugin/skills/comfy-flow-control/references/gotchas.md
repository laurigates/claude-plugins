# ComfyUI flow control — Gotchas

Routing traps that silently pick the wrong input, run an unwanted branch, or drop a value. Entry point: [`../SKILL.md`](../SKILL.md) § Gotchas.

## Gotchas

- **`ComfySwitchNode` (core)** is widget-overridden by an input.
  When you wire a BOOLEAN into the `switch` slot of `ComfySwitchNode`,
  the node's own widget value is ignored — the connected input wins.
  This bites you when the widget shows False but a connected
  PrimitiveBoolean(True) is in effect.
- **`Any Switch` (rgthree)** is eager — it evaluates *all* upstream
  inputs before picking the first non-None. Don't use it as a
  performance optimizer; use a typed `CSwitchBoolean*` for laziness.
- **`Preview Bridge` swallows `ExecutionBlocker`**: if you tee a path
  through Preview Bridge to inspect it, and the path is blocked, the
  Preview shows nothing and the downstream abort doesn't propagate
  through the bridge. Use `FastPreview` (`comfyui-kjnodes`) downstream
  of a Preview Bridge when blockers may appear, or wire previews off
  branches that can't be blocked.
- **`ImpactConditionalBranch.cond` is BOOLEAN, not INT/FLOAT**.
  `SimpleMathCondition` (essentials) returns FLOAT — convert with a
  comparator before feeding the branch.
- **Context Big silently drops mismatched slots**. If you wire an
  `IMAGE` to a `Context Big.latent` slot the wire is ignored at
  evaluation. Hover the Context outputs to check what's actually
  populated.
- **Easy-use loops expand at queue-time, not runtime**. A loop of 50
  iterations becomes 50 copies of the body inside the queue's prompt
  graph. Very large loops can OOM the *frontend* (browser) before
  even reaching the backend.
