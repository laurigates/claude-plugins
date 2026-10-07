# ComfyUI math & strings — Gotchas

Compute and string traps: the wrong math node, server-side-only errors, regex dialect, lenient converters that crash, dynamic slots, and `rangeInt` spacing. Entry point: [`../SKILL.md`](../SKILL.md) § Gotchas.

## Gotchas

- **`SimpleMath` ≠ `MathExpression`.** Essentials' SimpleMath is
  AST-safe (no imports, limited function set — no `sqrt`, no `numpy`).
  Pysssss MathExpression has full `math` + `numpy` access. Don't mix
  them up.
- **kjnodes Constants vs Crystools Constants** — they look
  interchangeable. They mostly are, but Crystools' `CFloat` /
  `CInteger` widgets default to wider ranges and Crystools' multiline
  `CTextML` has different newline handling on Windows. Pick one pack
  per workflow for consistency.
- **`MathExpression` errors are server-side**. The node turns red but
  the error message ("Error executing MathExpression: NameError")
  lives in the ComfyUI server log (`journalctl -u comfyui.service`
  on this install). Add a `ShowAnything` on the output to confirm
  it's emitting what you expect.
- **`StringFunction` regex syntax is Python `re`**. Forward slashes
  are NOT escapes; backslashes are. `\.(png|jpg|jpeg|webp)$` works.
  `/\\.(png|jpg|jpeg|webp)$/` does not — that's JavaScript syntax.
- **`AnythingToInt` on a non-numeric string crashes**. `"3.14"` →
  fails; `"3"` → works; `3.14` (float) → 3. To coerce a possibly
  non-numeric STRING, route through `MathExpression` with
  `int(float(a) if a else 0)` and a defensive try wrapper.
- **`JoinStringMulti` shrinks dynamic inputs**. The first time you
  add a downstream consumer, the node grows its slot count. If you
  later disconnect, the empty slots stay around. Drop and re-add the
  node to compact.
- **`easy rangeInt` `num_steps` is INCLUSIVE on both ends**, so
  `start=0, end=10, num_steps=11` gives `[0, 1, 2, ..., 10]`. With
  `num_steps=10`, you get `[0, 1.11, ..., 10]` — not integer.
  Prefer the `step` mode when you want integer-only spacing.
