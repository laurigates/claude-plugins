# comfyui-node-authoring — Reproducing Behavioural Bugs Live

Why a static read cannot confirm an interaction bug, and the chrome-devtools technique that settles one. Entry point: [`../SKILL.md`](../SKILL.md).

## Behavioural / touch / visibility bugs: reproduce live, don't trust a static read

Reading the source tells you what the code *says*; for an **interaction
bug** — hover-gating, touch reachability, z-index overlap, focus, a tap that
"does nothing" — a static CSS/template read is not enough to confirm the
mechanism. Reproduce against a live instance (see `comfyui-pack-live-smoke`)
before concluding.

Technique that settled a real case (a workflow-tab close button unreachable
on touch — ComfyUI_frontend #13279 / PR #13280):

- Drive it with the chrome-devtools MCP: `emulate` a mobile viewport with the
  `touch`+`mobile` flags, then **confirm the media state you think you're
  testing** — `matchMedia('(hover: none)').matches` must be `true`, else
  you're not actually testing touch.
- Prove tap reachability with `document.elementFromPoint(cx, cy)` at the
  target control's centre: if it returns an *overlay* element instead of the
  button/its child, the control is visually present but **tap-intercepted**
  — a failure a CSS read of `visibility` alone will miss.
- Mutate-and-recheck live: inject the candidate fix as a `<style>` and
  re-run the same `elementFromPoint` + a real `.click()`, watching the
  result, before committing to it.

When a bug is reported as conditional ("works with a few, breaks with
many"), treat that as ground truth and reproduce the *conditional* rather
than defending a first theory that only explains part of it.
