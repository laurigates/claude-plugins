---
created: 2026-06-04
modified: 2026-07-01
reviewed: 2026-07-01
name: comfyui-node-scaffold
description: >-
  Scaffold a new ComfyUI custom-node repo (TypeScript + bun build, CI,
  release-please, vitest+pytest) consuming @laurigates/comfy-modal-kit. Use when
  bootstrapping or init-ing a comfyui node pack.
allowed-tools: Bash, Read, Write, Edit, Grep, Glob, TodoWrite
---

# comfyui-node-scaffold

Bootstrap a new ComfyUI custom-node pack that matches the established
mobile-first **TypeScript + bun build** architecture of `comfyui-gallery-loader`,
`comfyui-sampler-info`, and `comfyui-touch-numeric`, leaving only the actual
node logic to implement.

## When to Use This Skill

| Use this skill when... | Use the alternative when... |
|---|---|
| Starting a new ComfyUI usability pack repo — CI-green TS toolchain, Comfy Registry publish, and the widget-intercept/gesture skeleton before writing pack logic | You want the full pipeline (repo created + seeded + gitops-adopted) → `comfy-node` |
| Spinning up a `project:comfyui-nodes` backlog idea (touch-numeric, prompt-editor, model-gallery…) | Adding a node to an *existing* pack — this creates a **new** repo |

## The architecture it scaffolds

**TypeScript source in `src/` (entry `src/index.ts`), built to `web/dist/` via
`bun build`** — typed authoring against `@comfyorg/comfyui-frontend-types`,
browser-ESM output, the `/scripts/app.js` runtime import left unbundled. This
supersedes the old vanilla-JS (`web/js/*.js` + copied modal primitives)
template. The generated pack starts with an ADR (`docs/blueprint/adrs/0001-…`)
recording the decision, mirroring sampler-info's ADR-0010.

- **Type gate**: `bun run typecheck` → `tsc --noEmit` (never emits).
- **Emit**: `bun build ./src/index.ts --target browser --format esm --outdir
  web/dist --external '/scripts/*'`. If the pack ships a static data corpus,
  append `&& cp -R web/data web/dist/data`.
- **Serve**: `__init__.py` sets `WEB_DIRECTORY = "./web/dist"`; ComfyUI serves
  that tree at `/extensions/<name>/`.
- **Distribute**: `web/dist/` is committed (tracked) so git clone/update
  carries the served bundle; `[tool.comfy] includes = ["web/dist"]` also
  force-ships it to the registry, and `publish.yml` runs `bun run build` first.
- **The `/scripts/app.js` type shim**: a `paths` mapping in `tsconfig.json`
  points the rooted import at `src/comfyui-shims.d.ts` (TypeScript will not
  match an ambient `declare module` against a `/…` specifier). The emitted
  import string stays `/scripts/app.js` and `--external '/scripts/*'` keeps it
  unbundled.

## The vein

A frontend extension that intercepts `widget.onPointerDown` (modern Vue
frontend, `comfyui-frontend-package >= 1.40`) and opens a touch-friendly HTML
modal in place of a clunky native LiteGraph control. Widgets are matched **by
name** (generic across node packs); the enhancement is **additive** (graceful
fallback, never breaks serialized workflows); the modal is **touch-first** (16px
inputs, big tap targets, momentum scroll). The modal primitives come from
`@laurigates/comfy-modal-kit` (`openModalShell` / `fuzzyRank` /
`highlightMatches`) — **imported, not copied** — and `bun build` inlines them.

## Three variants

| Variant | Use when | Shape | Modal kit |
|---------|----------|-------|-----------|
| `frontend` (default) | No Python needed — pure widget UX (seed/numeric keypad, prompt editor, tooltips, enum recipes). | Empty `NODE_CLASS_MAPPINGS`; widget-intercept modal in `src/index.ts`. Like sampler-info / touch-numeric. | **imports** the kit |
| `backend` | Needs to read disk / serve thumbnails / add a node (model thumbnails, file listings). | Adds `<module>.py` (node + aiohttp endpoints, ComfyUI-bundled libs only) + a `tests/conftest.py` that stubs aiohttp/server so pytest is green. Like gallery-loader. | **imports** the kit |
| `gesture` | The UX is a **canvas interaction**, not a widget — pinch/drag/long-press on nodes or groups (resize, move, region-box). | Empty `NODE_CLASS_MAPPINGS`; a canvas pointer layer in `src/index.ts` with exported pure geometry helpers. Like touch-resize. | **no kit** |

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

**Decision rule:** `frontend`/`backend` **with** `--widgets` for a per-widget
modal; `frontend`/`backend` **without** `--widgets` for a standalone modal opened
from the toolbar/command palette; `gesture` when the interaction is on the
canvas/node frame itself (no widget to hook). Add `backend` only when the feature
genuinely needs the server to read files or serve data. A non-bundled Python
dependency is never allowed — if you reach for one, it belongs in a separate
companion pack.

The `gesture` variant intercepts the **canvas pointer stream** (capture-phase
`pointerdown`/`move`/`up` on `app.canvas.canvas`), hit-tests against selected
nodes/groups in screen space (via `ds.scale`/`ds.offset`), and acts only when
the gesture lands on a selected target. It is a no-op when `app.canvas` is
absent, so the native control always survives. Pure math (distance, hit-test,
scale-clamp) lives in exported, unit-tested helpers; DOM/canvas wiring stays
below them. It has **no** `@laurigates/comfy-modal-kit` dependency.

## How to run

`scaffold.py` is stdlib-only. Run from the workspace root (`repos/laurigates/`)
so the new repo lands as a sibling of the reference packs.

Frontend-only pack:

```sh
python3 ${CLAUDE_SKILL_DIR}/scaffold.py --name comfyui-touch-numeric --display "Touch Numeric" --desc "Touch-friendly keypad + slider modal for seed and INT/FLOAT widgets." --variant frontend --widgets seed,noise_seed,cfg,steps,denoise
```

Pack with a Python backend:

```sh
python3 ${CLAUDE_SKILL_DIR}/scaffold.py --name comfyui-model-gallery --display "Model Gallery" --desc "Touch-first card-grid picker for the folder-backed model combos." --variant backend --widgets lora_name,ckpt_name,vae_name,control_net_name
```

Standalone-modal pack (manager/dashboard launched from a toolbar button — modal
variant, **no** `--widgets`):

```sh
python3 ${CLAUDE_SKILL_DIR}/scaffold.py --name comfyui-touch-manager --display "Touch Manager" --desc "Touch-first node/extension manager modal opened from the toolbar." --variant backend
```

Canvas-gesture pack (resize/move/region — no widget, no modal, no kit):

```sh
python3 ${CLAUDE_SKILL_DIR}/scaffold.py --name comfyui-touch-resize --display "Touch Resize" --desc "Selection-gated pinch-to-resize for ComfyUI nodes and groups on touch devices." --variant gesture
```

Flags: `--name` (repo + served URL segment), `--display` (Comfy DisplayName),
`--desc`, `--variant {frontend,backend,gesture}`, `--widgets` (CSV → the TS
stub's `TARGET_WIDGETS`; on a modal variant, **omitting** it emits the
standalone-modal skeleton instead of the widget-intercept one), `--publisher`
(default `laurigates`), `--dir` (parent dir, default cwd).

It refuses to overwrite an existing directory.

## What you get

A repo where `just check` (typecheck + build + lint + test) passes from the
first commit: `pyproject.toml` (`[tool.comfy]` metadata with `includes =
["web/dist"]` and `Icon`/`Banner` wired to the raw-GitHub PNG URLs, ruff config,
dev deps), `.github/workflows/` (`ci.yml`, `publish.yml`, `release-please.yml`,
`renovate.yml`, `registry-health.yml`, `clear-autorelease-labels.yml`),
`renovate.json` (Renovate, **not** dependabot), strict `tsconfig.json`,
`biome.json`, `knip.json`, `.pre-commit-config.yaml`,
`release-please-config.json` + manifest, `vitest.config.js`, `package.json`
(bun scripts; modal variants add `@laurigates/comfy-modal-kit`), `tests/` (a
green pytest + vitest smoke test), `src/index.ts` + `src/comfyui-shims.d.ts`,
`__init__.py` (`WEB_DIRECTORY = "./web/dist"`), `icon.svg` + `banner.svg`
(family-style placeholders — `just assets` rasterizes them to the PNGs the
registry serves), `CLAUDE.md`, the migration ADR, `README`, `LICENSE`, and
`RELEASE-CHECKLIST.md`. The `backend` variant additionally gets `<module>.py`
(node + endpoint + whitelist gate) and `tests/conftest.py` (stubs aiohttp/server).

## The finishing pass

A CI-green pack is not yet a registry-ready, fleet-consistent one. The scaffold
**emits** the deterministic finishing-pass pieces and **audits + warns** (at the
end of every run) for the two it can't do from stdlib alone (issue #1877):

| Piece | Status | Follow-up |
|-------|--------|-----------|
| Registry icon | emitted `icon.svg` + `Icon = …/main/icon.png` | `just assets` (needs `rsvg-convert`) → commit `icon.png` |
| Registry banner | emitted `banner.svg` + `Banner = …/main/banner.png` | `just assets` → commit `banner.png` |
| Renovate (not dependabot) | emitted `renovate.json` + `renovate.yml` + `registry-health.yml` + `clear-autorelease-labels.yml` | — |
| Screenshot pipeline | **deferred** (heavy, pack-specific) | run `comfyui-screenshot-pipeline`, then `just screenshots` + embed the README hero |

The final audit also diffs the new pack's top-level entries against a mature
sibling (`comfyui-gallery-loader` / `comfyui-sampler-info` / …) and reports the
gap — the drift this fixes was `comfyui-touch-manager` silently missing all four
for weeks while CI stayed green.

## After scaffolding

The generator prints the exact next steps. In order:

```sh
cd comfyui-<name>
git init -b main
uv sync --group dev
bun install
pre-commit install
just check
```

Seed `main` directly (the repo is unprotected until gitops adopts it) — pushing
a feature branch first would leave `main` missing on origin and force a rename
+ default-branch fixup later.

Then implement, and wire up infra:

1. **Implement the modal** in `src/index.ts` — tune `TARGET_WIDGETS` and replace
   the `openPicker` stub with the real modal body (`import { fuzzyRank } from
   "@laurigates/comfy-modal-kit"` for search, `openModalShell` for the dialog).
   For the `backend` variant, fill in `<module>.py`'s node + endpoints; widen
   `ALLOWED_EXTENSIONS` explicitly for any new file type read off disk. For the
   `gesture` variant, tune the pinch layer
   (`selectedNodes`/`nodeScreenRect`/`scaledSize`).
2. **Add the repo to `gitops/repositories.tf`** with `comfy_registry = true`
   (and `release_please = true`). On apply, gitops pushes both the release-please
   App credentials **and** the `REGISTRY_ACCESS_TOKEN` secret. No per-repo secret
   creation is needed.

**Or skip steps 1–2 entirely:** run the **`/comfy-node`** orchestrator, which
chains scaffold → `gh repo create` → seed `main` → the gitops PR.

## Hard rules baked into the output

- **TypeScript source, bun build.** Author in `src/`; build to `web/dist/`.
  `tsc --noEmit` checks, `bun build` emits — decoupled. Never hand-edit
  `web/dist/` (it is generated; rebuild with `bun run build` and commit).
- **Modal primitives come from `@laurigates/comfy-modal-kit`** (modal variants)
  — import them; never copy `modal-shell.js`/`modal-fuzzy.js` into the pack.
  `bun build` inlines the imported code. The gesture variant has no kit.
- **Pack directory name is part of the served URL** (`/extensions/<name>/index.js`).
- **No non-bundled Python deps.** `dependencies` is `comfyui-frontend-package`
  only; the backend variant may use ComfyUI-bundled `aiohttp` / `folder_paths` /
  `server` and nothing else.
- **Additive, never clobbering;** always fall back to the native control.
- **Never hand-edit `CHANGELOG.md` or the `version` field** — release-please
  owns them.
- **Arbitrary-path endpoints gate on an extension whitelist** (backend variant).
- **`openModalShell` has NO `body` option.** It returns a controller
  (`{ bodyEl, close, setBusy, setStatus, ... }`) whose `bodyEl` starts empty;
  fill it *after* opening (`const m = openModalShell({title}); m.bodyEl.appendChild(el)`).
  Passing `body:` is silently ignored and the dialog renders empty — a bug that
  **passes green unit tests** because modal builders are DOM-uncovered. The stub
  does it right.

## Registry publishing

The generated `publish.yml` builds `web/dist/` then publishes via
`Comfy-Org/publish-node-action`. Three registry facts worth knowing:

- **Active vs Flagged is a pointer.** The registry serves one *Active* version
  per node; publishing moves that pointer to the new version. A version that gets
  **Flagged** (review) stays in the registry but is no longer the Active target —
  installs fall back to the last Active version. Publishing a fresh good version
  re-points Active forward.
- **Flags are content-independent.** A version can be Flagged for reasons
  unrelated to its file contents (publisher / automated review state), so a
  byte-identical re-publish can flip status. A Flag does not by itself mean the
  tarball is bad — check the registry version page.
- **`.comfyignore` trims the tarball.** comfy-cli builds the published `node.zip`
  as *git-tracked files − `.comfyignore` matches + `[tool.comfy] includes`*. The
  scaffold ships a default `.comfyignore` so only the runtime backend, the built
  `web/dist`, and metadata ship — CI, tests, docs, build inputs, and the TS source
  stay out. Tarball trimming requires **comfy-cli >= 1.10.3**.

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Scaffold a frontend pack | `python3 ${CLAUDE_SKILL_DIR}/scaffold.py --name comfyui-X --display "X" --desc "…" --variant frontend --widgets a,b` |
| Scaffold a gesture pack | `python3 ${CLAUDE_SKILL_DIR}/scaffold.py --name comfyui-X --display "X" --desc "…" --variant gesture` |
| Verify a generated pack | `cd comfyui-X && bun install && just check` |

## Notes & deferrals

- The screenshot pipeline (`screenshots/` Docker + Playwright) and the full
  `docs/blueprint/` PRD/ADR set (beyond the single migration ADR) are **not**
  generated — they are heavy and pack-specific. Add them later (the
  `comfyui-screenshot-pipeline` skill wires the screenshots). The
  finishing-pass audit at the end of a scaffold flags this so it isn't silently
  forgotten (issue #1877).
- Icon/banner ship as **source SVGs**; the PNGs the registry serves are produced
  by `just assets` (rsvg-convert), not at scaffold time (stdlib-only generator).
  Edit the SVG and re-run `just assets` to keep the PNG in sync.
- Action/tool versions in the generated workflows mirror the reference packs as
  of scaffolding; Dependabot/Renovate will bump them. The biome pin is
  single-sourced in `scaffold.py`'s `BIOME_VERSION` constant so biome.json,
  pre-commit, CI, and the justfile never drift (a guard in
  `scripts/plugin-compliance-check.sh` enforces this).
- The TS stub imports only `openModalShell`; add `fuzzyRank` /
  `highlightMatches` from `@laurigates/comfy-modal-kit` when the real modal's
  search lands.
- **Add at least one jsdom DOM-attach test for each modal builder** (assert the
  expected element exists in `modal.bodyEl` after `openX()`). The generated
  pytest + vitest gate covers pure helpers only; modal DOM is otherwise left to
  the manual browser smoke matrix — which is exactly the gap that let an
  empty-modal bug ship green. (`vitest --environment jsdom`.)
