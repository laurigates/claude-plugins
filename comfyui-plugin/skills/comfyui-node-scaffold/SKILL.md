---
created: 2026-06-04
modified: 2026-08-13
reviewed: 2026-07-29
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

Supporting material is split across `references/` by the path that needs it;
see [REFERENCE.md](REFERENCE.md) for the index.

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

**Name-matching needs a gate when the modal's content is external.** The emitted
`TARGET_WIDGETS` set matches on name alone, which is correct for a modal that
renders the widget's *own* `options.values`. If your pack instead fills the modal
from a `folder_paths` listing, an endpoint, or a corpus, a node that hardcodes a
combo under the same name (RIFE VFI's `ckpt_name`) has its only valid choices
replaced with values it rejects — see `comfyui-node-authoring` § "A widget name
is not proof of its option source" for the overlap gate.

## Four variants

| Variant | Use when | Shape | Modal kit |
|---------|----------|-------|-----------|
| `frontend` (default) | No Python needed — pure widget UX (seed/numeric keypad, prompt editor, tooltips, enum recipes). | Empty `NODE_CLASS_MAPPINGS`; widget-intercept modal in `src/index.ts`. Like sampler-info / touch-numeric. | **imports** the kit |
| `backend` | Needs to read disk / serve thumbnails / add a node (model thumbnails, file listings). | Adds `<module>.py` (node + aiohttp endpoints, ComfyUI-bundled libs only) + a `tests/conftest.py` that stubs aiohttp/server so pytest is green. Like gallery-loader. | **imports** the kit |
| `gesture` | The UX is a **canvas interaction**, not a widget — pinch/drag/long-press on nodes or groups (resize, move, region-box). | Empty `NODE_CLASS_MAPPINGS`; a canvas pointer layer in `src/index.ts` with exported pure geometry helpers. Like touch-resize. | **no kit** |
| `shim` | The pack's whole job is **injecting scoped CSS / registering commands** to paper over upstream frontend bugs — no modal, no widget hook. | Empty `NODE_CLASS_MAPPINGS`; a `SHIMS` registry in `src/index.ts` with `applyCssShim`/`removeCssShim`, one managed `<style>` per shim driven by a boolean setting, + a jsdom lifecycle smoke test. Like comfyui-touch-shim. | **no kit** |

**Decision rule:** `frontend`/`backend` **with** `--widgets` for a per-widget
modal; `frontend`/`backend` **without** `--widgets` for a standalone modal opened
from the shared **Touch Tools** hub (the family's one action-bar button — a
scaffolded pack contributes a chooser row, never a button of its own); `gesture`
when the interaction is on the
canvas/node frame itself (no widget to hook); `shim` when the pack only injects
scoped CSS / registers commands to paper over an upstream frontend bug (no modal,
no widget). Add `backend` only when the feature
genuinely needs the server to read files or serve data. A non-bundled Python
dependency is never allowed — if you reach for one, it belongs in a separate
companion pack.

For what `--widgets` changes about the emitted modal, and what the `gesture`
and `shim` skeletons contain, see
[references/variants.md](references/variants.md).

## How to run

`scaffold.py` is stdlib-only. Run from the workspace root (`repos/laurigates/`)
so the new repo lands as a sibling of the reference packs.

Frontend-only pack:

```sh
python3 ${CLAUDE_SKILL_DIR}/scaffold.py --name comfyui-touch-numeric --display "Touch Numeric" --desc "Touch-friendly keypad + slider modal for seed and INT/FLOAT widgets." --variant frontend --widgets seed,noise_seed,cfg,steps,denoise
```

The `backend`, standalone-modal, `gesture`, and `shim` recipes, the full flag
list, and the banner-tagline rule live in
[references/invocation.md](references/invocation.md).

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
   For the standalone-modal shape, keep the Touch Tools hub wiring intact and
   swap the placeholder `pi pi-th-large` icon for a fitting PrimeIcon — see
   [references/variants.md](references/variants.md) § "The Touch Tools hub
   contract".
   For the `backend` variant, fill in `<module>.py`'s node + endpoints; widen
   `ALLOWED_EXTENSIONS` explicitly for any new file type read off disk. For the
   `gesture` variant, tune the pinch layer
   (`selectedNodes`/`nodeScreenRect`/`scaledSize`). For the `shim` variant,
   replace the placeholder `SHIMS` entry — link the upstream issue, point the
   selector at a stable `data-testid`, keep each shim fail-soft.
2. **Add the repo to `gitops/repositories.tf`** with `comfy_registry = true`
   (and `release_please = true`). On apply, gitops pushes both the release-please
   App credentials **and** the `REGISTRY_ACCESS_TOKEN` secret. No per-repo secret
   creation is needed.

**Or skip steps 1–2 entirely:** run the **`/comfy-node`** orchestrator, which
chains scaffold → `gh repo create` → seed `main` → the gitops PR.

Before opening the registry PR, grade the pack's finishing pass — the artwork
gate, the `--verify` audit, and the registry-publishing facts are in
[references/registry-readiness.md](references/registry-readiness.md). What the
generator emits, the invariants the emitted code assumes, and what it
deliberately does not generate are in
[references/implementing-the-pack.md](references/implementing-the-pack.md).

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Scaffold a frontend pack | `python3 ${CLAUDE_SKILL_DIR}/scaffold.py --name comfyui-X --display "X" --desc "…" --variant frontend --widgets a,b` |
| Scaffold a gesture pack | `python3 ${CLAUDE_SKILL_DIR}/scaffold.py --name comfyui-X --display "X" --desc "…" --variant gesture` |
| Scaffold a CSS/shim pack | `python3 ${CLAUDE_SKILL_DIR}/scaffold.py --name comfyui-X --display "X" --desc "…" --variant shim` |
| Verify a generated pack | `cd comfyui-X && bun install && just check` |
| Grade one pack's finishing pass | `python3 ${CLAUDE_SKILL_DIR}/scaffold.py --verify path/to/comfyui-X` |
| Sweep the whole fleet for drift | `python3 ${CLAUDE_SKILL_DIR}/scripts/check-fleet-drift.py` |
| Sweep one pack only | `python3 ${CLAUDE_SKILL_DIR}/scripts/check-fleet-drift.py --pack comfyui-X` |
