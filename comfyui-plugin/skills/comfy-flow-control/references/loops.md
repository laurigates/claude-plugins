# ComfyUI flow control — Loops

easy-use `forLoop` / `whileLoop` setup and best practice. Entry point: [`../SKILL.md`](../SKILL.md).

## Loops

Easy-use ships the only general-purpose loop primitives in this
install. Use sparingly — ComfyUI's execution model wasn't designed for
iteration, and loops expand at prompt-queue time to a sequence of
copied subgraph nodes (so an N=50 loop is N=50 sampler instances in
the graph, not one node looping).

| Loop | Setup |
|---|---|
| `easy forLoopStart` → body → `easy forLoopEnd` | `total` count (INT), `values_1..N` carry state through iterations |
| `easy whileLoopStart` → body → `easy whileLoopEnd` | `condition` (BOOLEAN) checked after each iteration; emits FLOW_CONTROL token + state |

Best practice:

- Keep loop bodies short. Each iteration replicates the entire subgraph
  in the queue, so 30 iterations × 50 nodes ≈ 1500-node queue.
- Always have an exit predicate. `whileLoopEnd` with no terminating
  condition will hang the queue forever.
- The state-carry slots (`values_*`) are how you accumulate — write to
  them at the end, read at the start.
- For per-image batch iteration, prefer ComfyUI's native batch
  semantics (let the sampler process a batch) over a loop. Loops are
  for iteration where each round depends on the previous round's
  output.
