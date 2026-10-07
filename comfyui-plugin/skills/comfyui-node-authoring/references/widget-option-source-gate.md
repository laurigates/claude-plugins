# comfyui-node-authoring — A Widget Name Is Not Proof of Its Option Source

When a pack matches widgets by name and renders options from an external source, gate the modal on overlap with the widget's own values. Entry point: [`../SKILL.md`](../SKILL.md).

## A widget name is not proof of its option source

Matching widgets **by name** is what makes a usability pack generic across node
packs — any node exposing `lora_name` gets the LoRA picker, whatever its node
type. But a name is a *convention*, not a contract: a third-party node can
hardcode a combo under a canonical name, and its options then have nothing to do
with `folder_paths`.

**The split that decides whether you need a gate:**

| The modal renders… | Risk | Gate needed |
|---|---|---|
| The widget's **own** `options.values` (reformatted, filtered, searchable) | none — you show what the node offers | no |
| Content from an **external** source (a `folder_paths` listing, an endpoint, a corpus) | you can replace the node's only valid choices with values it rejects | **yes** |

> Evidence (2026-08, `comfyui-model-gallery` #66): ComfyUI-Frame-Interpolation's
> **RIFE VFI** node hardcodes `ckpt_name` to `rife47.pth`, `rife49.pth`,
> `rife417.pth`, `rife426.pth`, `sudo_rife4_269…pth` — weights living in that
> pack's own `ckpts/` dir. The gallery matched the name, listed
> `models/checkpoints` instead, and offered two diffusion checkpoints the node
> cannot load. Zero overlap between the two sets, which is exactly the signal.

**The gate: require the widget's own values to overlap the external source.**

```ts
// names = the external source's contents for this category; null when unknown
function optionsMatchSource(w, names) {
  if (!names) return true;                       // source unknown — stay optimistic
  const values = w?.options?.values;
  if (!Array.isArray(values) || values.length === 0) return true;
  return values.some((v) => names.has((v ?? "").toString()));
}
```

Four things make it work in practice:

- **Prime the source per category at enhance time** (fire-and-forget, once), so
  the check answers **synchronously** when the user taps. A gate that has to
  await a fetch mid-pointer-event is a gate that opens the wrong modal first.
- **Decide at tap time, not patch time.** The listing arrives asynchronously and
  a node's options can be rebuilt by a definition refresh, so test inside the
  opener, not in the `if` that decides whether to patch.
- **Decline by returning `false`** from the `patchWidgetPointer` opener — that
  falls through to the native control, preserving the additive contract. Do not
  skip patching entirely; you still want the tooltip/callback enhancements.
- **Stay optimistic on unknown.** Unknown source or an empty `values` array must
  open the modal, exactly as before the gate existed. A conservative default
  silently withholds the feature whenever the backend is unreachable — a
  regression that presents as "the pack stopped working" with no error.

Partial overlap is a pass, not a failure: a stale entry alongside real files
(a deleted model still listed in a loaded workflow) is normal.
