---
created: 2026-06-04
modified: 2026-06-04
reviewed: 2026-06-04
name: comfyui-node-scaffold
description: >-
  Scaffold a new ComfyUI custom-node repo (pyproject, CI, release-please,
  vitest+pytest, JS extension skeleton) in the picker/gesture vein. Use when
  bootstrapping or init-ing a comfyui node pack.
allowed-tools: Bash, Read, Write, Edit, Grep, Glob, TodoWrite
---

# comfyui-node-scaffold

Bootstrap a new ComfyUI custom-node pack that matches the established
mobile-first architecture of `comfyui-gallery-loader` and
`comfyui-sampler-info`, leaving only the actual node logic to implement.

## When to Use This Skill

| Use this skill when... | Use the alternative when... |
|---|---|
| Starting a new ComfyUI usability pack repo — CI-green tooling, Comfy Registry publish, and the widget-intercept/gesture skeleton before writing pack logic | You want the full pipeline (repo created + seeded + gitops-adopted) → `comfy-node` |
| Spinning up a `project:comfyui-nodes` backlog idea (touch-numeric, prompt-editor, model-gallery…) | Adding a node to an *existing* pack — this creates a **new** repo |

## The pattern it scaffolds ("the vein")

A frontend JS extension that intercepts `widget.onPointerDown` (modern Vue
frontend, `comfyui-frontend-package >= 1.40`) and opens a touch-friendly HTML
modal in place of a clunky native LiteGraph control. Widgets are matched **by
name** (generic across node packs); the enhancement is **additive** (graceful
fallback, never breaks serialized workflows); the modal is **touch-first**
(16px inputs, big tap targets, momentum scroll). Reuses `modal-shell.js`
(`openModalShell` / `closeModalShell`) and `modal-fuzzy.js` (`fuzzyScore` /
`fuzzyRank` / `highlightMatches`).

## Three variants

| Variant | Use when | Shape |
|---------|----------|-------|
| `frontend` (default) | No Python needed — pure widget UX (seed/numeric keypad, prompt editor, tooltips, enum recipes). | Empty `NODE_CLASS_MAPPINGS`; everything in `web/js/`. Widget-intercept modal vein. Like sampler-info. |
| `backend` | Needs to read disk / serve thumbnails / add a node (model thumbnails, file listings). | Adds `<module>.py` with a node + aiohttp endpoints (ComfyUI-bundled libs only) and an extension-whitelist gate. Like gallery-loader. |
| `gesture` | The UX is a **canvas interaction**, not a widget — pinch/drag/long-press on nodes or groups (resize, move, region-box). | Empty `NODE_CLASS_MAPPINGS`; a canvas pointer layer in `web/js/`. No modal primitives copied. Exported pure geometry helpers + unit tests. |

**Decision rule:** pick `frontend` for a per-widget modal; pick `gesture` when
the interaction is on the canvas/node frame itself (no widget to hook); pick
`backend` only when the feature genuinely needs the server to read files or
serve data. A non-bundled Python dependency is never allowed — if you reach for
one, it belongs in a separate companion pack.

The `gesture` variant intercepts the **canvas pointer stream** (capture-phase
`pointerdown`/`move`/`up` on `app.canvas.canvas`), hit-tests against selected
nodes/groups in screen space (via `ds.scale`/`ds.offset`), and acts only when
the gesture lands on a selected target — suppressing the native canvas
pan/zoom for that gesture. It is a no-op when `app.canvas` is absent, so the
native control always survives. Pure math (distance, hit-test, scale-clamp)
lives in exported, unit-tested helpers; DOM/canvas wiring stays below them.

## How to run

`scaffold.py` is stdlib-only. From the workspace root (`repos/laurigates/`, so
the new repo lands as a sibling of the reference packs and the modal primitives
copy cleanly):

Frontend-only pack:

```sh
python3 .claude/skills/comfyui-node-scaffold/scaffold.py --name comfyui-touch-numeric --display "Touch Numeric" --desc "Touch-friendly keypad + slider modal for seed and INT/FLOAT widgets." --variant frontend --widgets seed,noise_seed,cfg,steps,denoise
```

Pack with a Python backend:

```sh
python3 .claude/skills/comfyui-node-scaffold/scaffold.py --name comfyui-model-gallery --display "Model Gallery" --desc "Touch-first card-grid picker for the folder-backed model combos." --variant backend --widgets lora_name,ckpt_name,vae_name,control_net_name
```

Canvas-gesture pack (resize/move/region — no widget, no modal):

```sh
python3 .claude/skills/comfyui-node-scaffold/scaffold.py --name comfyui-touch-resize --display "Touch Resize" --desc "Selection-gated pinch-to-resize for ComfyUI nodes and groups on touch devices." --variant gesture
```

Flags: `--name` (repo + served URL segment), `--display` (Comfy DisplayName),
`--desc`, `--variant {frontend,backend,gesture}`, `--widgets` (CSV → the JS
stub's `TARGET_WIDGETS`; modal variants only), `--publisher` (default
`laurigates`), `--dir` (parent dir, default cwd), `--modal-source` (pack to copy
`modal-shell.js`/`modal-fuzzy.js` from; default `<parent>/comfyui-gallery-loader`;
`none` to skip — the `gesture` variant defaults to `none`).

It refuses to overwrite an existing directory.

## What you get

A repo where `just check` (ruff + biome + pytest + vitest) passes from the first
commit, with: `pyproject.toml` (`[tool.comfy]` metadata, ruff config, dev deps),
`.github/workflows/` (`ci.yml`, `publish.yml`, `release-please.yml`),
`dependabot.yml`, `biome.json`, `.pre-commit-config.yaml`,
`release-please-config.json` + manifest, `vitest.config.js`, `package.json`
(dev-only), `tests/` (a green pytest + vitest smoke test), `__init__.py`, a
`CLAUDE.md` seeded with the pattern + hard rules, `README`, `LICENSE`,
`RELEASE-CHECKLIST.md`, the `web/js/<short>.js` extension skeleton with the
`onPointerDown` interception already wired, and copies of `modal-shell.js` +
`modal-fuzzy.js`. The `backend` variant additionally gets `<module>.py` (node +
endpoint + whitelist gate).

## After scaffolding

The generator prints the exact next steps. In order:

```sh
cd comfyui-<name>
git init -b main
uv sync --group dev
npm install --no-audit --no-fund
pre-commit install
just check
```

Seed `main` directly (the repo is unprotected until gitops adopts it) — pushing
a feature branch first would leave `main` missing on origin and force a rename
+ default-branch fixup later.

Then implement, and wire up infra:

1. **Implement the modal** in `web/js/<short>.js` — tune `TARGET_WIDGETS` and
   replace the `openPicker` stub with the real modal body (use `fuzzyRank` for
   search, `openModalShell` for the dialog). For the `backend` variant, fill in
   `<module>.py`'s node + endpoints; widen `ALLOWED_EXTENSIONS` explicitly for
   any new file type read off disk.
2. **Add the repo to `gitops/repositories.tf`** with `comfy_registry = true`
   (and `release_please = true`) — repos are managed via OpenTofu/Scalr, *not*
   the GitHub UI (see `laurigates/CLAUDE.md` and `gitops/CLAUDE.md`). On apply,
   gitops pushes both the release-please App credentials **and** the
   `REGISTRY_ACCESS_TOKEN` secret (from the Scalr `comfy_registry_token` var).
   No per-repo secret creation is needed.

**Or skip steps 1–2 entirely:** run the **`/comfy-node`** orchestrator, which
chains scaffold → `gh repo create` → seed `main` → the gitops PR (entry +
transient `import` block), stopping at the single human gate (merge the gitops
PR → Scalr applies).

## Hard rules baked into the output

- **Pack directory name is part of the served URL** (`/extensions/<name>/js/…`).
  Don't rename the dir without syncing `EXT_NAME` in the JS.
- **No non-bundled Python deps.** `dependencies` is `comfyui-frontend-package`
  only; the backend variant may use ComfyUI-bundled `aiohttp` / `folder_paths` /
  `server` and nothing else.
- **Additive, never clobbering;** always fall back to the native control.
- **Never hand-edit `CHANGELOG.md` or the `version` field** — release-please
  owns them (conventional commits drive the bump).
- **Arbitrary-path endpoints gate on an extension whitelist** (backend variant).
- **`openModalShell` has NO `body` option.** It returns a controller
  (`{ bodyEl, close, setBusy, setStatus, ... }`) whose `bodyEl` starts empty;
  fill it *after* opening (`const m = openModalShell({title}); m.bodyEl.appendChild(el)`).
  Passing `body:` is silently ignored and the dialog renders empty — a bug that
  **passes green unit tests** because modal builders are DOM-uncovered (it shipped
  once; the scaffold stub now does it right). Same for `closeModalShell()` vs the
  controller's `.close()`.

## Notes & deferrals

- The screenshot pipeline (`screenshots/` Docker + Playwright) and the
  `docs/blueprint/` PRD/ADR set are **not** generated — they are heavy and
  pack-specific. Add them later (copy `screenshots/` from a reference pack and
  re-point the Dockerfile COPY target / served URL prefix to the new pack name).
- Action/tool versions in the generated workflows mirror the reference packs as
  of scaffolding; Dependabot/Renovate will bump them.
- The JS stub imports only `openModalShell`; add `fuzzyRank` / `highlightMatches`
  from `./modal-fuzzy.js` when the real modal's search lands.
- **Add at least one jsdom DOM-attach test for each modal builder** (assert the
  expected element exists in `modal.bodyEl` after `openX()`). The generated pytest
  + vitest gate covers pure helpers only; modal DOM is otherwise left to the manual
  browser smoke matrix — which is exactly the gap that let an empty-modal bug ship
  green. A single `expect(modal.bodyEl.querySelector(...)).toBeTruthy()` would have
  caught it. (`vitest --environment jsdom`.)
