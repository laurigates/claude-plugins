# ComfyUI debug & preview — Gotchas

Why a display, timer, or logger shows nothing, the wrong value, or slows the run. Entry point: [`../SKILL.md`](../SKILL.md) § Gotchas.

## Gotchas

- **`ShowText` updates AFTER queue completion**, not live during the
  run. For mid-run display you need a console log
  (`DebugTensorShape`, `CConsoleAny`) plus tailing the server log.
- **`Preview Bridge` swallows `ExecutionBlocker`** — see above.
  Mitigations: tee off the path BEFORE any potential blocker, or use
  `FastPreview` downstream.
- **`CUtilsStatSystem` only polls when its output is consumed**.
  Wiring it to nothing means it never runs. Wire the output to a
  console logger or a `ShowFloat` to make it actually poll.
- **`DisplayAny` truncates large strings** to ~10 lines / ~1000 chars.
  For longer values use `ShowStringText` (bjornulf) which scrolls,
  or `DreamStringToLog` which writes to the server log without
  truncation.
- **`TimerNodeKJ` start/end pairing**: the `id` parameter must
  match between the start and end instances. Multiple Timer pairs
  with the same id cross-pollute their start times.
- **`Sleep` is on the *graph* execution thread**, not GPU. It blocks
  the entire queue, including unrelated parallel branches. Use only
  when intentionally throttling.
- **`FloatsVisualizer` renders to image at fixed resolution** — the
  output is an IMAGE, not a graph object. Wire it through
  `PreviewImage` to display.
- **`DreamLogFile` opens the file in append mode each call** — for
  high-frequency logging in a loop, file IO becomes the bottleneck.
  Use a console logger instead and tail the server log offline.
- **Crystools metadata nodes operate on PNG `image.info` only** —
  they don't read MP4/WebP/EXIF. For those, the offline
  `comfy-metadata` skill covers the full range.
