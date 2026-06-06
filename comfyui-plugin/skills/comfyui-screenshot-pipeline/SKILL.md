---
created: 2026-06-05
modified: 2026-06-05
reviewed: 2026-06-05
name: comfyui-screenshot-pipeline
description: >-
  Containerized README-screenshot pipeline (Docker + Playwright) for ComfyUI
  custom-node packs. Use when generating pack screenshots, adding `just
  screenshots`, or capturing modal/gesture node UI.
allowed-tools: Bash, Read, Write, Edit, Grep, Glob, TodoWrite
---

# comfyui-screenshot-pipeline

Add the containerized README-screenshot generator to a ComfyUI usability pack.
It is the deferred piece from `comfyui-node-scaffold` (which intentionally does
not emit it). The same pattern ships in `comfyui-gallery-loader`,
`comfyui-sampler-info`, `comfyui-touch-numeric`, `comfyui-prompt-editor`,
`comfyui-model-gallery`, `comfyui-touch-resize`, and `comfyui-touch-connect` —
those are the living reference implementations.

## When to Use This Skill

| Use this skill when... | Use the alternative when... |
|---|---|
| Adding a reproducible README-screenshot generator to an existing ComfyUI pack — Docker + Playwright driver, `just screenshots`, committed `docs/<out>.png` | Bootstrapping a brand-new pack repo → `comfyui-node-scaffold` (it intentionally defers the screenshot pipeline) |
| Capturing the pack's real frontend deterministically (modal dialog, gesture affordance, or transient overlay) | Running the full idea→registry lifecycle → `comfy-node` |

## Why containerized

The shot must not depend on whatever models / theme / frontend a dev machine
happens to have. A Docker image pins the ComfyUI release (hence the frontend
bundle) and the Playwright/Chromium revision (the largest source of cross-host
font-rendering drift), boots ComfyUI headless on CPU with no models, drives the
pack's real public surface, and writes a PNG to a mounted `docs/`. Re-runs are
deterministic.

## Pick the archetype

| Archetype | Use when the pack… | What the driver does |
|-----------|--------------------|----------------------|
| `modal` | opens an HTML dialog over a widget (the modal "vein": gallery-loader, sampler-info, touch-numeric, prompt-editor, model-gallery) | load a workflow with the target node, wait for the pack's patch flag on the widget, invoke `widget.onPointerDown`, wait for `.cmp-dialog`, screenshot it |
| `gesture-affordance` | is a canvas gesture whose only static surface is a painted affordance (touch-resize's corner-hint bracket) | select a node directly (no `selectNode` → no Vue toolbox) so `onDrawForeground` paints, optionally inject an illustrative callout overlay, clip the canvas region around the node |
| `gesture-overlay` | shows a transient overlay only during a live gesture that can't run headlessly (touch-connect's magnifier loupe) | force the canvas state (`connecting_links` etc.), dispatch a synthetic **touch** pointer the pack listens for, then screenshot the activated overlay element |

For a backend model pack (model-gallery), add `--seed-models`: a fresh ComfyUI
has empty model dirs, so the grid renders empty. The generator emits
`seed_models.py` that drops zero-byte placeholder files (the `/list` endpoint
enumerates names only, never reads contents) across a couple of subfolders.

## How to run

`add_screenshots.py` is stdlib-only. Run it from the pack repo root (or pass
`--dir <pack>`). The script ships with this skill, so reference it via
`${CLAUDE_SKILL_DIR}`:

```sh
# Modal pack (seed keypad over the `seed` widget)
python3 ${CLAUDE_SKILL_DIR}/add_screenshots.py --name comfyui-touch-numeric --variant modal --node KSampler --widget seed --flag _touchNumericPatched --ready .tn-keypad --out seed.png

# Backend model pack (seed placeholder models first)
python3 ${CLAUDE_SKILL_DIR}/add_screenshots.py --name comfyui-model-gallery --variant modal --node CheckpointLoaderSimple --widget ckpt_name --flag _modelGalleryPatched --ready .mg-card --out picker.png --seed-models

# Gesture pack — painted affordance
python3 ${CLAUDE_SKILL_DIR}/add_screenshots.py --name comfyui-touch-resize --variant gesture-affordance --node KSampler --out hint.png

# Gesture pack — forced overlay
python3 ${CLAUDE_SKILL_DIR}/add_screenshots.py --name comfyui-touch-connect --variant gesture-overlay --out loupe.png
```

Flags: `--name` (pack dir name = the served URL segment, used as the Docker
COPY target — must match the real dir), `--variant`, `--out` (PNG filename, also
the `EXPECTED_OUTPUTS` the entrypoint asserts), `--node`/`--widget`/`--flag`/
`--ready` (modal capture placeholders — the node type, the widget name the pack
patches, the pack's per-widget patch-guard property, and an inner dialog
selector that proves the body rendered), `--seed-models`, `--dir`, `--comfy-ref`
(default `v0.22.0`), `--playwright` (default `1.49.1`). It refuses to overwrite
an existing `screenshots/` unless `--force`.

It writes `screenshots/{Dockerfile,Dockerfile.dockerignore,entrypoint.sh,package.json,capture.mjs,workflow.json,README.md}`
(+ `seed_models.py` with `--seed-models`), and **appends** a `screenshots`
recipe to the pack's `justfile` if one isn't already there.

## After running: tailor, iterate, embed

1. **Tailor `capture.mjs` + `workflow.json`.** The generic infra is done; the
   capture is pack-specific. For `modal`, the placeholders are filled from your
   flags but verify the widget name, patch flag, and the `--ready` inner
   selector against the real pack JS. For the gesture variants, the emitted
   driver is the touch-resize / touch-connect approach — adjust selectors,
   forced state, and any injected overlay to your pack.

2. **Iterate without rebuilding.** Build once, then mount the fast-changing
   files into the cached image so each run is ~10–15s instead of a ~4-min
   rebuild:

   ```sh
   docker build -f screenshots/Dockerfile -t <pack>-screenshots .
   docker run --rm -v "$(pwd)/docs:/out" -v "$(pwd)/screenshots/capture.mjs:/opt/screenshots/capture.mjs" -v "$(pwd)/screenshots/workflow.json:/opt/screenshots/workflow.json" <pack>-screenshots
   ```

   For a gesture pack iterating on the extension itself, also mount the pack JS:
   `-v "$(pwd)/web/js/<ext>.js:/opt/ComfyUI/custom_nodes/<pack>/web/js/<ext>.js"`.

3. **Final run + embed.** `just screenshots` produces the committed `docs/<out>.png`.
   Embed it as a README hero with an italic caption (see the reference packs).
   Land it as a `docs(screenshots):` change (no release bump). If the work also
   changes pack behavior (e.g. an affordance color), split that into its own
   `fix(...)`/`feat(...)` commit so release-please attributes it correctly.

## Gotchas (all encountered building the family)

- **`biome` ignores `screenshots/`** in these packs, so CI's `biome check .`
  won't lint `capture.mjs` — but keep it clean anyway (2-space indent, double
  quotes) to match the family.
- **`ruff` DOES lint `seed_models.py`** via `ruff check .` / `ruff format --check .`.
  The generator's output is already ruff-clean and formatted.
- **`entrypoint.sh` shellcheck**: the `for f in ${EXPECTED_OUTPUTS}` loop is
  intentional word-splitting; the generator includes the `# shellcheck disable=SC2086`
  directive so a pre-commit shellcheck hook doesn't fail.
- **Dismiss the first-run dialog.** A fresh ComfyUI profile opens a PrimeVue
  "Workflow Templates" dialog (`.p-dialog-mask`) over the canvas; the drivers
  press Escape and remove the mask before shooting.
- **`deviceScaleFactor: 2`** gives crisp 2× PNGs; the modal shell is `.cmp-dialog`.
- **`widget.onPointerDown` may be the pack's own wrapper** that chains the
  original first and only opens the modal if the original didn't consume the
  event — invoking it with `{}` as the pointer works for the family's widgets.
  If a modal won't open this way, fall back to the pack's Strategy-B button
  (prompt-editor's `⤢`, gallery-loader's 📁) — see those capture scripts.
- **Pin lockstep.** The Playwright version is pinned in BOTH the Dockerfile
  `FROM` and `package.json`; bump together. `COMFYUI_REF` pins the frontend
  bundle — bump deliberately (the modal/canvas render is sensitive to it).

## The generic files (what's identical across packs)

`entrypoint.sh` (boots ComfyUI on `--cpu :8188`, waits for `/system_stats`, runs
the driver, asserts `$EXPECTED_OUTPUTS` exist), `Dockerfile.dockerignore`, and
`package.json` (modulo the name) are the same everywhere. The Dockerfile differs
only by pack name, `EXPECTED_OUTPUTS`, and the optional model-seeding block.
`capture.mjs` + `workflow.json` are the only genuinely pack-specific files — and
the reference packs are the canonical examples to crib from.
