# comfyui-node-scaffold — Variant and Modal Shape

Detail behind the variant table in [`../SKILL.md`](../SKILL.md) § "Four
variants": what the `--widgets` switch changes about the emitted modal, and what
the `gesture` and `shim` skeletons actually contain.

## The `--widgets` switch

**The `--widgets` switch picks the modal shape.** On a modal variant
(`frontend` / `backend`), passing `--widgets a,b` emits the **widget-intercept**
`src/index.ts` (`TARGET_WIDGETS` + `openPicker` + `widget.onPointerDown`).
**Omitting `--widgets`** emits a **standalone-modal** `src/index.ts` instead — a
`registerExtension` skeleton with an `actionBarButtons` entry + a
`command`/`menuCommand` that calls an exported `openShell()` (no `TARGET_WIDGETS`,
no per-widget hook). Use the standalone skeleton for a manager / dashboard /
gallery-actions panel whose modal is launched from the app chrome rather than a
node widget (e.g. comfyui-touch-manager). It still imports the modal kit, and it
ships a **jsdom modal-mount smoke test** (`jsdom` added to `devDependencies`)
that asserts `openShell()` populates the modal body — the empty-modal gap that
otherwise passes pure-helper unit tests.

## The gesture variant

The `gesture` variant intercepts the **canvas pointer stream** (capture-phase
`pointerdown`/`move`/`up` on `app.canvas.canvas`), hit-tests against selected
nodes/groups in screen space (via `ds.scale`/`ds.offset`), and acts only when
the gesture lands on a selected target. It is a no-op when `app.canvas` is
absent, so the native control always survives. Pure math (distance, hit-test,
scale-clamp) lives in exported, unit-tested helpers; DOM/canvas wiring stays
below them. It has **no** `@laurigates/comfy-modal-kit` dependency.

## The shim variant

The `shim` variant is a home for **small, individually-toggleable stopgap
fixes** that paper over upstream ComfyUI-frontend bugs. It has **no modal and no
widget hook**: `src/index.ts` is a `SHIMS` registry where each entry injects a
scoped, managed `<style>` tag (idempotent `applyCssShim`/`removeCssShim`, one
`<style>` per shim) driven by a boolean setting, plus a command. Every shim
links the upstream issue it papers over (in `upstream` + the settings tooltip)
and is deleted the release the upstream fix ships; selectors should target
stable `data-testid` hooks and every shim must **fail soft** (a dead selector
styles nothing, never throws). The lifecycle helpers are exported and covered by
a jsdom smoke test (inject / idempotent / remove; `jsdom` added to
`devDependencies`). It has **no** `@laurigates/comfy-modal-kit` dependency. Like
comfyui-touch-shim.
