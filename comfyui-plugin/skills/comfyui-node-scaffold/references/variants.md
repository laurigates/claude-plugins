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

### A gesture must be recognizable on the FIRST `pointerdown`

**This is the design constraint for the whole variant, and the emitted skeleton
does not yet satisfy it.** The skeleton still demonstrates a two-finger pinch;
`comfyui-touch-resize` shipped exactly that, then removed it as unfixable in
`feat!: replace the pinch gesture with corner grab-handles` (touch-resize #58).
Treat the skeleton's pinch as a worked example to *replace*, not a pattern to
extend — rewriting it is tracked upstream.

The root cause is structural, not a bug that can be patched:

> A pinch is not recognizable until the **second** finger lands, by which point
> the first finger's `pointerdown` has already reached LiteGraph and opened a
> node-drag or canvas-pan transaction.

Everything else in that module existed only to paper over the half-open
transaction — move-stream suppression, a wheel interceptor,
`touchstart`/`touchmove` hedges, `touch-action: none`, a synthetic
`pointercancel`, and manual clearing of six canvas-level drag flags. A target
hit-tested on the **first** `pointerdown` is suppressed before LiteGraph opens
any transaction, so there is no half-open state to recover.

Two further traps that a pinch design walks into, both real:

- **`Comfy.SimpleTouchSupport` keeps a module-global `touchCount`** (`+=` on
  `touchstart`, `-=` on `touchend`) and patches `LGraphCanvas.processMouseDown`
  to return early whenever it is truthy. Swallowing `touchstart` at window
  capture while letting `touchend` through drives the count **negative** — also
  truthy — and the canvas stops responding to taps until `resetTouchState` fires
  on `visibilitychange`. That is the "recovers only by switching apps" symptom.
  A pointer-events-only layer that never sets `touch-action` keeps the count
  balanced by construction.
- **Write geometry by assignment, never in-place** (`obj.size = [w, h]`, not
  `obj.size[0] = w`). In-place mutation bypasses `LGraphNode`'s `pos`/`size`
  setters and therefore the Vue layout store they feed
  (`useLayoutMutations.moveNode`/`.resizeNode`).

Place hit targets by **measurement, not guess**: body-corner handles land ~17px
from the first input/output slots — inside the hit radius — so tapping a slot on
a selected node grabs a handle instead of starting a link drag. Tracing the full
outline instead puts them ~21px from the collapse toggle and ~45px from the
slots. Cap the hit radius accordingly and record the ceiling in `CONFIG`.

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
