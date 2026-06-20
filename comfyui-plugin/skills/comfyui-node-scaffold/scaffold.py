#!/usr/bin/env python3
"""Scaffold a new ComfyUI custom-node repo (TypeScript + bun build) in the
gallery-loader / sampler-info / touch-numeric vein.

Generates a CI-green, ready-to-implement pack with TypeScript source in `src/`
(entry `src/index.ts`) built to `web/dist/` via `bun build`: pyproject.toml,
CI + release-please + publish workflows, ruff/biome/pre-commit config, a
strict tsconfig + knip + vitest harness, __init__.py (WEB_DIRECTORY pointing at
the built `web/dist`), CLAUDE.md, an ADR recording the TS+bun decision, and the
extension skeleton. The frontend/backend (modal) variants consume the shared
`@laurigates/comfy-modal-kit` primitives via an `import` (NOT copied-in files);
the gesture variant is a self-contained canvas pointer layer with no kit
dependency.

This supersedes the previous vanilla-JS (`web/js/*.js` + copied
modal-shell.js/modal-fuzzy.js) template — see the generated ADR.

Stdlib only. Run with `python3 scaffold.py` or `uv run scaffold.py`.

Examples
--------
Frontend-only pack (sampler-info / touch-numeric shape — consumes the kit):
    python3 scaffold.py \
        --name comfyui-touch-numeric \
        --display "Touch Numeric" \
        --desc "Touch-friendly keypad + slider modal for seed and INT/FLOAT widgets." \
        --variant frontend \
        --widgets seed,noise_seed,cfg,steps,denoise

Pack with a small Python backend (gallery-loader shape — consumes the kit):
    python3 scaffold.py \
        --name comfyui-model-gallery \
        --display "Model Gallery" \
        --desc "Touch-first card-grid picker for the folder-backed model combos." \
        --variant backend \
        --widgets lora_name,ckpt_name,vae_name,control_net_name

Canvas-gesture pack (touch-resize shape — no widget, no modal, no kit):
    python3 scaffold.py \
        --name comfyui-touch-resize \
        --display "Touch Resize" \
        --desc "Selection-gated pinch-to-resize for ComfyUI nodes and groups on touch devices." \
        --variant gesture
"""

from __future__ import annotations

import argparse
import datetime
import sys
from pathlib import Path

AUTHOR_DEFAULT = "Lauri Gates"
PUBLISHER_DEFAULT = "laurigates"

# The shared modal-kit consumed by the modal (frontend/backend) variants. The
# gesture variant does NOT depend on it. Bump in lockstep with the kit's
# published major/minor when its exported API changes.
MODAL_KIT_PKG = "@laurigates/comfy-modal-kit"
MODAL_KIT_VERSION = "^0.2.0"

# Pinned tool versions — kept in ONE place so the biome pin can never drift
# between biome.json, the pre-commit hook, CI, and the justfile. The previous
# template pinned an old 1.x biome in the pre-commit hook while biome.json/CI
# were on 2.x, and the pre-commit hook surfaced that mismatch as a config-parse
# failure. The regression check in scripts/plugin-compliance-check.sh asserts
# every generated biome pin stays on this single version.
BIOME_VERSION = "2.4.15"
COMFY_FRONTEND_TYPES_VERSION = "^1.43.0"


# --------------------------------------------------------------------------- #
# Name derivation
# --------------------------------------------------------------------------- #
def derive(name: str) -> dict[str, str]:
    """Derive the family of names a pack needs from its repo name."""
    if not name.startswith("comfyui-"):
        print(
            f"warning: pack name '{name}' does not start with 'comfyui-'",
            file=sys.stderr,
        )
    short = name.removeprefix("comfyui-")  # e.g. touch-numeric
    return {
        "NAME": name,  # comfyui-touch-numeric  (repo + served URL segment)
        "SHORT": short,  # touch-numeric
        "PY_MODULE": short.replace("-", "_"),  # touch_numeric  (backend .py)
        "EXT_CONST_CAMEL": _camel(short),  # touchNumeric  (JS guard-flag prefix)
    }


def _camel(short: str) -> str:
    """touch-numeric -> touchNumeric (for a JS widget guard-flag property)."""
    head, *rest = short.split("-")
    return head + "".join(part[:1].upper() + part[1:] for part in rest)


# --------------------------------------------------------------------------- #
# Templates — @@TOKEN@@ placeholders (avoids brace conflicts with JSON/JS/TS)
# --------------------------------------------------------------------------- #
def subst(text: str, ctx: dict[str, str]) -> str:
    for key, val in ctx.items():
        text = text.replace(f"@@{key}@@", val)
    return text


PYPROJECT = """\
[project]
name = "@@NAME@@"
description = "@@DESC@@"
version = "0.1.0"
license = { text = "MIT" }
readme = "README.md"
requires-python = ">=3.10"
authors = [{ name = "@@AUTHOR@@" }]
keywords = ["comfyui", "comfyui-nodes", "ui", "picker", "mobile", "touch"]
classifiers = [
    "License :: OSI Approved :: MIT License",
    "Programming Language :: Python :: 3",
    "Programming Language :: JavaScript",
    "Topic :: Multimedia :: Graphics",
]

# @@DEP_FLOOR_NOTE@@ @@BACKEND_DEP_NOTE@@
dependencies = [
    "comfyui-frontend-package>=1.40.0",
]

[project.urls]
Repository = "https://github.com/@@PUBLISHER@@/@@NAME@@"
Issues = "https://github.com/@@PUBLISHER@@/@@NAME@@/issues"

[dependency-groups]
dev = [
    "ruff>=0.11",
    "pytest>=8",
    "pre-commit>=4",
]

[tool.ruff]
target-version = "py310"
line-length = 99

[tool.ruff.lint]
select = ["E", "F", "W", "I", "UP", "B", "SIM", "RUF"]

[tool.ruff.format]
quote-style = "double"

[tool.pytest.ini_options]
testpaths = ["tests"]
pythonpath = ["."]
@@PYTEST_ADDOPTS@@
[tool.comfy]
PublisherId = "@@PUBLISHER@@"
DisplayName = "@@DISPLAY@@"
Icon = ""
# The built frontend (web/dist/) is git-ignored — emitted by `bun run build`.
# publish-node-action honors [tool.comfy] includes to force-add otherwise-
# ignored paths into the published tarball. See ADR-0001.
includes = ["web/dist"]
"""

INIT_FRONTEND = '''\
"""@@DISPLAY@@ for ComfyUI.

Frontend-only pack: no Python nodes. The TypeScript source in `src/` is
compiled to ESM via `bun build` and emitted to `web/dist/`, which ComfyUI
serves as the extension root via WEB_DIRECTORY below. See ADR-0001.
"""

WEB_DIRECTORY = "./web/dist"

NODE_CLASS_MAPPINGS = {}
NODE_DISPLAY_NAME_MAPPINGS = {}

__all__ = ["NODE_CLASS_MAPPINGS", "NODE_DISPLAY_NAME_MAPPINGS", "WEB_DIRECTORY"]
'''

INIT_BACKEND = '''\
"""@@DISPLAY@@ for ComfyUI.

See @@PY_MODULE@@.py for the backend (node + HTTP endpoints). The frontend
TypeScript source in `src/` is compiled to ESM via `bun build` and emitted to
`web/dist/`, which ComfyUI serves via WEB_DIRECTORY below. See ADR-0001.
"""

try:
    # ComfyUI loads custom_nodes as packages — relative import works.
    from .@@PY_MODULE@@ import NODE_CLASS_MAPPINGS, NODE_DISPLAY_NAME_MAPPINGS
except ImportError:
    # Pytest imports __init__.py without a package context; fall back to
    # absolute (the pack root is on sys.path via pyproject pythonpath).
    from @@PY_MODULE@@ import NODE_CLASS_MAPPINGS, NODE_DISPLAY_NAME_MAPPINGS

WEB_DIRECTORY = "./web/dist"

__all__ = ["NODE_CLASS_MAPPINGS", "NODE_DISPLAY_NAME_MAPPINGS", "WEB_DIRECTORY"]
'''

BACKEND_PY = '''\
"""@@DISPLAY@@ — backend node + HTTP endpoints.

Uses ComfyUI-bundled libraries ONLY (aiohttp, plus folder_paths / server
from ComfyUI core). Do not add a Python dependency that ComfyUI does not
already ship; if a feature needs one, make it a separate companion pack.
"""

from __future__ import annotations

from aiohttp import web
from server import PromptServer

# Extensions this pack will read off disk. Any arbitrary-path endpoint MUST
# gate on this whitelist — never read an absolute path without checking.
ALLOWED_EXTENSIONS = {".png", ".jpg", ".jpeg", ".webp"}


@PromptServer.instance.routes.get("/@@PY_MODULE@@/list")
async def _list(request: web.Request) -> web.Response:
    """TODO: return the JSON listing the frontend modal renders.

    Mirror gallery-loader's /gallery_loader/list contract:
    success -> {"ok": True, "items": [...]} ; failure -> {"ok": False, ...}.
    """
    return web.json_response({"ok": True, "items": []})


class @@DISPLAY_NOSPACE@@:
    """Minimal node stub. Replace inputs/outputs/FUNCTION with the real node,
    or delete this class if the pack is purely an interaction enhancer with
    no new node (then move the endpoints to a frontend-only companion)."""

    @classmethod
    def INPUT_TYPES(cls):
        return {"required": {}}

    RETURN_TYPES = ()
    FUNCTION = "run"
    CATEGORY = "@@DISPLAY@@"

    def run(self):
        return ()


NODE_CLASS_MAPPINGS = {"@@DISPLAY_NOSPACE@@": @@DISPLAY_NOSPACE@@}
NODE_DISPLAY_NAME_MAPPINGS = {"@@DISPLAY_NOSPACE@@": "@@DISPLAY@@"}
'''

# --------------------------------------------------------------------------- #
# TypeScript source — modal (frontend/backend) variant
# --------------------------------------------------------------------------- #
INDEX_TS_MODAL = """\
// @@DISPLAY@@ — ComfyUI frontend extension.
//
// TypeScript source in `src/`, built to ESM via `bun build` and emitted to
// `web/dist/` (served at /extensions/@@NAME@@/index.js — the pack directory
// name IS the URL segment). Do not rename the pack dir without syncing
// EXT_NAME below (used for log prefixes and any /@@PY_MODULE@@/ fetches).
// See ADR-0001.
//
// Pattern (shared with gallery-loader / sampler-info / touch-numeric):
//   registerExtension -> enhance each node (on create AND on graph load) ->
//   wrap widget.onPointerDown on widgets matched BY NAME -> open an HTML
//   modal instead of the native LiteGraph control. Additive + mobile-first;
//   always chain to the original handler and fall back to the native control.
//   Requires the modern Vue frontend's onPointerDown hook
//   (comfyui-frontend-package >= 1.40).
//
// The shared modal primitives come from @@MODAL_KIT_PKG@@. They are NOT copied
// into this pack — `bun build` INLINES the imported code into web/dist. To add
// fuzzy search to the modal, import the matcher from the same package:
//   import { fuzzyRank, highlightMatches } from "@@MODAL_KIT_PKG@@";
//   fuzzyRank(query, [primaryField, ...otherFields]) -> { score, primaryMatches } | null
import { openModalShell } from "@@MODAL_KIT_PKG@@";
// ComfyUI serves its frontend API at runtime from `/scripts/app.js`. The
// emitted import string stays `/scripts/app.js` (bun's `--external '/scripts/*'`
// keeps it unbundled); the type is supplied via a `paths` mapping in
// tsconfig.json that points the import at `src/comfyui-shims.d.ts`. See ADR-0001.
import { app } from "/scripts/app.js";

const EXT_NAME = "@@NAME@@";

// Widgets this pack enhances, detected by NAME (generic across node packs).
// TODO: tune this set for the pack.
const TARGET_WIDGETS = new Set<string>([@@WIDGET_SET@@]);

// ============================================================
// Types — the narrow LiteGraph surface this pack reaches into
// ============================================================
//
// `@comfyorg/comfyui-frontend-types` exports `ComfyApp` (the type of the
// imported `app`) but NOT `LGraphNode` / the widget interfaces — they are
// declared internally and not re-exported. Model the small surface this pack
// touches with local structural interfaces instead (narrow blast radius).

// A widget plus the custom props this pack hangs off it. `onPointerDown` and
// the private guard flag are this pack's intercept seam, not part of the
// public widget surface.
interface PatchedWidget {
  name: string;
  onPointerDown?: (pointer: unknown, node: PatchedNode, canvas: unknown) => boolean | undefined;
  _@@EXT_CONST_CAMEL@@Patched?: boolean;
}

// Minimal structural type for the LiteGraph node this pack operates on. Named
// to avoid colliding with the package's own un-exported `LGraphNode` at the
// registerExtension lifecycle-hook seam — the hooks receive the package node,
// which we cast to this structural shape.
interface PatchedNode {
  type?: string;
  widgets?: PatchedWidget[];
}

// ============================================================
// Modal
// ============================================================

function openPicker(widget: PatchedWidget, node: PatchedNode | null): void {
  // CONTRACT: openModalShell has NO `body` option — it returns a controller
  // ({ bodyEl, close, setBusy, setStatus, ... }) with an EMPTY bodyEl that you
  // fill AFTER opening. Passing `body:` is silently ignored and the dialog
  // renders empty (a bug that passes green unit tests — only a jsdom/browser
  // check catches it). Always: open, then modal.bodyEl.appendChild(...).
  const modal = openModalShell({
    title: widget.name,
    onClose: () => {},
  });

  // TODO: build the real modal body. This skeleton proves the interception
  // + modal-shell wiring works end to end. Use fuzzyRank for search.
  const body = document.createElement("div");
  body.textContent = `@@DISPLAY@@: picker for "${widget.name}" on ${node?.type} — implement me.`;
  modal.bodyEl.appendChild(body);
}

// ============================================================
// Wiring
// ============================================================

function enhanceNode(node: PatchedNode): void {
  for (const w of node?.widgets ?? []) {
    if (!TARGET_WIDGETS.has(w.name)) continue;
    if (w._@@EXT_CONST_CAMEL@@Patched) continue; // guard against double-patching
    w._@@EXT_CONST_CAMEL@@Patched = true;

    // Strategy A: wrap onPointerDown. Chain to the original first; only open
    // our modal if the original didn't consume the event. Fall back to the
    // native control on error (additive — never break the widget).
    const origDown = w.onPointerDown;
    w.onPointerDown = function (
      this: PatchedWidget,
      pointer: unknown,
      ownerNode: PatchedNode,
      canvas: unknown,
    ): boolean | undefined {
      try {
        if (typeof origDown === "function") {
          const consumed = origDown.call(this, pointer, ownerNode, canvas);
          if (consumed) return consumed;
        }
        openPicker(w, ownerNode || node);
        return true; // consume — suppresses the native control
      } catch (e) {
        console.warn(`[${EXT_NAME}] picker open failed`, e);
        return false; // fall back to native on error
      }
    };
  }
}

app.registerExtension({
  name: "comfy.@@SHORT@@",
  // Handle freshly created nodes AND nodes restored from a saved graph. The
  // lifecycle-hook node params are the package's own `LGraphNode`; cast each to
  // the structural `PatchedNode` this pack operates on.
  async nodeCreated(node) {
    try {
      enhanceNode(node as unknown as PatchedNode);
    } catch (e) {
      console.warn(`[${EXT_NAME}] nodeCreated enhance failed`, e);
    }
  },
  async loadedGraphNode(node) {
    try {
      enhanceNode(node as unknown as PatchedNode);
    } catch (e) {
      console.warn(`[${EXT_NAME}] loadedGraphNode enhance failed`, e);
    }
  },
});

// Re-export the pure helpers a real implementation adds here, so the Vitest
// suite (tests/js) can import them directly from the .ts source. The seed
// example is a placeholder — replace with this pack's own helpers.
export function clampToTargets(name: string): boolean {
  return TARGET_WIDGETS.has(name);
}
"""

# --------------------------------------------------------------------------- #
# TypeScript source — gesture variant (no modal-kit dependency)
# --------------------------------------------------------------------------- #
INDEX_TS_GESTURE = """\
// @@DISPLAY@@ — ComfyUI frontend extension (canvas-gesture pack).
//
// TypeScript source in `src/`, built to ESM via `bun build` and emitted to
// `web/dist/` (served at /extensions/@@NAME@@/index.js — the pack directory
// name IS the URL segment). Do not rename the pack dir without syncing
// EXT_NAME below. See ADR-0001.
//
// Pattern ("the gesture vein"): instead of intercepting a single widget,
// this pack adds a CANVAS-LEVEL pointer layer. A two-finger pinch whose
// centroid lands inside a *selected* node (single tap selects it) resizes
// that node and suppresses the native canvas zoom for the gesture's
// duration. Additive + mobile-first: if app.canvas or the pointer model is
// absent it does nothing and native corner-handle resize still works.
// Resize only writes node.size (already serialized) so no workflow breaks.
//
// This variant has NO @@MODAL_KIT_PKG@@ dependency — there is no widget to
// hook and no modal to open. Pure geometry helpers are exported and
// unit-tested (tests/js); the DOM/canvas wiring below is exercised in the
// manual browser matrix.
//
// ComfyUI serves its frontend API at runtime from `/scripts/app.js`. The
// emitted import string stays `/scripts/app.js` (bun's `--external '/scripts/*'`
// keeps it unbundled); the type is supplied via a `paths` mapping in
// tsconfig.json that points the import at `src/comfyui-shims.d.ts`. See ADR-0001.
import { app } from "/scripts/app.js";

const EXT_NAME = "@@NAME@@";

// LiteGraph maps a canvas point p to screen space as (p + ds.offset) * ds.scale.
// LiteGraph.NODE_TITLE_HEIGHT = 30 (confirm against the frontend sourcemap).
const DEFAULT_TITLE_HEIGHT = 30;

// ============================================================
// Types
// ============================================================

/** A screen-space rectangle. */
interface Rect {
  x: number;
  y: number;
  w: number;
  h: number;
}

/** A 2-tuple of [x, y] / [w, h] used throughout the geometry. */
type Vec2 = [number, number];

/** The narrow node surface this pack reaches into. */
interface GestureNode {
  pos: Vec2;
  size: Vec2;
  computeSize?: () => Vec2;
  onResize?: (size: Vec2) => void;
}

// ============================================================
// Pure helpers (unit-tested in tests/js)
// ============================================================

/** Euclidean distance between two {x, y} pointers. */
export function pinchDistance(a: { x: number; y: number }, b: { x: number; y: number }): number {
  return Math.hypot(a.x - b.x, a.y - b.y);
}

/** Midpoint between two {x, y} pointers. */
export function centroid(
  a: { x: number; y: number },
  b: { x: number; y: number },
): { x: number; y: number } {
  return { x: (a.x + b.x) / 2, y: (a.y + b.y) / 2 };
}

/** Is screen point (x, y) inside rect {x, y, w, h}? */
export function pointInRect(x: number, y: number, rect: Rect): boolean {
  return x >= rect.x && y >= rect.y && x <= rect.x + rect.w && y <= rect.y + rect.h;
}

/** Node bounding rect (incl. title bar) in screen space. */
export function nodeScreenRect(
  node: GestureNode,
  scale: number,
  offset: Vec2,
  titleHeight = DEFAULT_TITLE_HEIGHT,
): Rect {
  const x = (node.pos[0] + offset[0]) * scale;
  const yBody = (node.pos[1] + offset[1]) * scale;
  return {
    x,
    y: yBody - titleHeight * scale,
    w: node.size[0] * scale,
    h: node.size[1] * scale + titleHeight * scale,
  };
}

/**
 * New [w, h] after a uniform pinch scale, clamped to a minimum.
 * ratio = currentPinchDistance / startPinchDistance; minSize = [minW, minH].
 */
export function scaledSize(startSize: Vec2, ratio: number, minSize: Vec2 = [0, 0]): Vec2 {
  return [Math.max(minSize[0], startSize[0] * ratio), Math.max(minSize[1], startSize[1] * ratio)];
}

/** Selected nodes as an array, defensively across LiteGraph variants. */
export function selectedNodes(canvas: unknown): GestureNode[] {
  if (!canvas || typeof canvas !== "object") return [];
  const c = canvas as {
    selected_nodes?: Record<string, GestureNode>;
    selectedItems?: Set<unknown>;
  };
  const sel = c.selected_nodes;
  if (sel && typeof sel === "object") return Object.values(sel);
  if (c.selectedItems instanceof Set) {
    return [...c.selectedItems].filter(
      (it): it is GestureNode => !!it && typeof it === "object" && "size" in it && "pos" in it,
    );
  }
  return [];
}

// ============================================================
// Wiring (DOM + canvas; browser-matrix tested)
// ============================================================

interface PinchLock {
  node: GestureNode;
  startDist: number;
  startSize: Vec2;
  minSize: Vec2;
}

function installGestureLayer(): void {
  const canvas = (
    app as {
      canvas?: {
        canvas?: HTMLCanvasElement;
        ds?: { scale?: number; offset?: Vec2 };
        setDirty?: (a: boolean, b: boolean) => void;
      };
    }
  ).canvas;
  const el = canvas?.canvas; // the actual <canvas> element
  if (!el || !canvas) {
    console.warn(`[${EXT_NAME}] no canvas element — gesture layer not installed`);
    return;
  }

  const pointers = new Map<number, { x: number; y: number }>();
  let lock: PinchLock | null = null;

  const localPoint = (e: PointerEvent): { x: number; y: number } => {
    const r = el.getBoundingClientRect();
    return { x: e.clientX - r.left, y: e.clientY - r.top };
  };

  function tryStartPinch(): void {
    if (pointers.size !== 2 || lock) return;
    const [p1, p2] = [...pointers.values()] as [{ x: number; y: number }, { x: number; y: number }];
    const c = centroid(p1, p2);
    const scale = canvas?.ds?.scale ?? 1;
    const offset = canvas?.ds?.offset ?? ([0, 0] as Vec2);
    for (const node of selectedNodes(canvas)) {
      if (pointInRect(c.x, c.y, nodeScreenRect(node, scale, offset))) {
        const minSize: Vec2 = typeof node.computeSize === "function" ? node.computeSize() : [0, 0];
        lock = {
          node,
          startDist: pinchDistance(p1, p2) || 1,
          startSize: [node.size[0], node.size[1]],
          minSize,
        };
        return;
      }
    }
  }

  el.addEventListener(
    "pointerdown",
    (e) => {
      pointers.set(e.pointerId, localPoint(e));
      tryStartPinch();
      if (lock) e.stopImmediatePropagation(); // suppress native pinch-zoom
    },
    true,
  );

  el.addEventListener(
    "pointermove",
    (e) => {
      if (!pointers.has(e.pointerId)) return;
      pointers.set(e.pointerId, localPoint(e));
      if (!lock || pointers.size < 2) return;
      const [p1, p2] = [...pointers.values()] as [
        { x: number; y: number },
        { x: number; y: number },
      ];
      const ratio = pinchDistance(p1, p2) / lock.startDist;
      const [w, h] = scaledSize(lock.startSize, ratio, lock.minSize);
      lock.node.size[0] = w;
      lock.node.size[1] = h;
      lock.node.onResize?.(lock.node.size);
      canvas?.setDirty?.(true, true);
      e.stopImmediatePropagation();
    },
    true,
  );

  const endPointer = (e: PointerEvent): void => {
    pointers.delete(e.pointerId);
    if (pointers.size < 2) lock = null;
  };
  el.addEventListener("pointerup", endPointer, true);
  el.addEventListener("pointercancel", endPointer, true);

  console.log(`[${EXT_NAME}] gesture layer installed — pinch a selected node to resize`);
}

app.registerExtension({
  name: "comfy.@@SHORT@@",
  async setup() {
    installGestureLayer();
    // TODO: groups — extend selectedNodes()/nodeScreenRect() to graph._groups
    //   (group.pos/group.size; no title bar) so a pinch resizes groups too.
    // TODO: discoverability — draw a faint corner affordance on selected nodes
    //   (canvas onDrawForeground) so the pinch gesture is learnable.
    // TODO: optional anisotropic mode — decompose the two-finger vector into
    //   independent W/H instead of uniform scale (behind a config flag).
  },
});
"""

COMFYUI_SHIMS = """\
// ComfyUI serves its frontend API at runtime from `/scripts/app.js`. The
// `@comfyorg/comfyui-frontend-types` package only types the bare-package
// symbols, not that served-path module. TypeScript will not match an ambient
// `declare module` against a rooted (`/…`) path specifier, so instead a
// `paths` mapping in tsconfig.json points the `/scripts/app.js` import at this
// declaration file. The emitted import string stays `/scripts/app.js` (bun's
// `--external '/scripts/*'` keeps it unbundled, resolved at runtime against
// ComfyUI's served module).
import type { ComfyApp } from "@comfyorg/comfyui-frontend-types";

export declare const app: ComfyApp;
"""

TSCONFIG = """\
{
  "compilerOptions": {
    "target": "ES2022",
    "lib": ["ES2023", "DOM", "DOM.Iterable"],
    "module": "ESNext",
    "moduleResolution": "Bundler",
    "paths": {
      "/scripts/app.js": ["./src/comfyui-shims.d.ts"]
    },
    "verbatimModuleSyntax": true,
    "isolatedModules": true,
    "noEmit": true,
    "allowJs": false,
    "strict": true,
    "noUncheckedIndexedAccess": true,
    "noImplicitOverride": true,
    "noUnusedLocals": true,
    "noUnusedParameters": true,
    "skipLibCheck": true,
    "types": ["@comfyorg/comfyui-frontend-types"]
  },
  "include": ["src"]
}
"""

KNIP_JSON = """\
{
  "$schema": "https://unpkg.com/knip@5/schema.json",
  "entry": ["src/index.ts"],
  "project": ["src/**/*.ts"]
}
"""

README = """\
# @@NAME@@

@@DESC@@

> Part of a family of mobile-first ComfyUI usability packs
> ([gallery-loader](https://github.com/@@PUBLISHER@@/comfyui-gallery-loader),
> [sampler-info](https://github.com/@@PUBLISHER@@/comfyui-sampler-info)):
@@FAMILY_BLURB@@

## Install

```sh
cd <ComfyUI>/custom_nodes
git clone https://github.com/@@PUBLISHER@@/@@NAME@@
cd @@NAME@@
bun install
bun run build      # emit web/dist/ (served by ComfyUI)
```

Restart ComfyUI; hard-refresh the browser tab (Ctrl+Shift+R / Cmd+Shift+R).

## What it does

TODO — describe @@WHAT_DESC@@.

## Compatibility

@@COMPAT_BULLET@@
- Frontend changes take effect after `bun run build` + a browser hard-refresh —
  no ComfyUI restart.

## License

MIT — see `LICENSE`.
"""

CLAUDE_MD = """\
# CLAUDE.md

@@CLAUDE_INTRO@@

## The pattern ("the vein")

@@VEIN@@

## File layout

| Path | Purpose |
|------|---------|
| `src/index.ts` | @@EXT_ROW_DESC@@ |
| `src/comfyui-shims.d.ts` | Types the `/scripts/app.js` runtime import (via the `paths` mapping in `tsconfig.json`). |
| `__init__.py` | Loader stub. @@INIT_DESC@@ |
@@BACKEND_LAYOUT_ROW@@| `web/dist/` | **Generated** by `bun run build` (git-ignored). ComfyUI serves it at `/extensions/@@NAME@@/`. |
| `pyproject.toml` | Comfy Registry metadata. `PublisherId` + `version` are the fields you touch; `[tool.comfy] includes = ["web/dist"]` force-ships the built output. |
| `tsconfig.json` / `biome.json` / `knip.json` | Strict TS config, Biome lint/format, knip dead-code. |
| `.github/workflows/` | `ci.yml` (tsc+build/biome/vitest/ruff/pytest/gitleaks), `publish.yml` (builds then publishes on version bump), `release-please.yml`. |
| `tests/js/` | Vitest suite importing the `.ts` source directly.@@PYTEST_LAYOUT_NOTE@@ |
| `justfile` | `build`, `lint`, `format`, `test`, `check` recipes — the local CI gate. |

## Hard rules

- **Pack directory name is part of the URL.** `web/dist/index.js` is served at
  `/extensions/@@NAME@@/index.js`. Renaming the pack dir breaks every fetch. If
  unavoidable, sync `EXT_NAME` in the source.
- **TypeScript source, bun build.** Author in `src/` (entry `src/index.ts`),
  build to `web/dist/` via `bun build ./src/index.ts --target browser --format
  esm --outdir web/dist --external '/scripts/*'`. `tsc --noEmit` is the type
  gate; `bun build` is the emit — they are decoupled. The `/scripts/app.js`
  import is left **unbundled** (resolved at runtime against ComfyUI's served
  module). See ADR-0001.
- **@@DEP_RULE@@**
- **@@KIT_RULE@@**
- **Additive only.** Never clobber an existing tooltip/control; fall back to
  the native widget when there's no match. Never fabricate data.
- @@HOOK_RULE@@
- **Never hand-edit `CHANGELOG.md` or the `version` field** — release-please
  owns them (conventional commits drive the bump).

## Dev workflow

```sh
uv sync --group dev          # ruff, pytest, pre-commit
bun install                  # TypeScript, Biome, Vitest, knip, @@KIT_DEV_NOTE@@
pre-commit install
just check                   # typecheck + build + lint + test — the local CI gate
```

Iterating on the frontend needs a **`bun run build`** (the served file is
`web/dist/index.js`, not the source) plus a browser hard-refresh — no ComfyUI
restart.@@RESTART_NOTE@@

### Endpoint reachability check

```sh
curl -s -o /dev/null -w "%{http_code}\\n" http://127.0.0.1:8188/extensions/@@NAME@@/index.js
```

## Verify the frontend API against the sourcemap

The ComfyUI frontend (`comfyui-frontend-package`) ships **minified** — property
and method names are renamed in the bundle, so reading the running app's objects
by guessed names (or trusting old tutorials) is unreliable. The TypeScript types
from `@comfyorg/comfyui-frontend-types` cover `ComfyApp` but **not** the internal
`LGraphNode` / `LGraphCanvas` / widget interfaces (un-exported). Model the small
surface you touch with local structural interfaces, and verify the real shape
against the bundled sourcemap before coding against a LiteGraph / canvas API.

LiteGraph is bundled in the **`api-*.js.map`** chunk under
`.venv/lib/python*/site-packages/comfyui_frontend_package/static/assets/`. The
`.js.map` embeds the original TypeScript in `sourcesContent` — grep that, not the
minified `.js`:

```sh
cd .venv/lib/python*/site-packages/comfyui_frontend_package/static/assets
grep -l 'LGraphGroup' *.js.map        # find the chunk
```

Facts worth confirming this way (recheck on a `comfyui-frontend-package` bump):
`LiteGraph.NODE_TITLE_HEIGHT` (30); `canvas.selectedItems` is a
`Set<Positionable>` holding nodes + groups + reroutes; `canvas.selected_nodes` is
a node-only dictionary; canvas zoom is **wheel-driven**
(`processMouseWheel -> ds.changeScale`).

Two gotchas that follow: discriminate selected items by **shape, not
`instanceof`** (the class is renamed under minification); and to suppress native
zoom during a gesture, intercept `wheel` (capture, `passive:false`,
`preventDefault`), not just pointer events. Record what you confirm in a
"Verified frontend API" table above so the next change doesn't re-derive it.

## Releases

Merge the release-please PR → the published GitHub release triggers
`publish.yml`, which runs `bun run build`, publishes via
`Comfy-Org/publish-node-action`, and pushes the release notes to the registry
version changelog (the "Updates" section). Requires the
`REGISTRY_ACCESS_TOKEN` repo secret. Use conventional commits; release-please
maintains `CHANGELOG.md` and the version bump PR.
"""

JUSTFILE = """\
# @@NAME@@ — task runner. Run `just` (or `just --list`) for recipes.

set positional-arguments

# Show available recipes.
default:
    @just --list

##########
# Quality
##########

# Build the frontend bundle to web/dist/ (bun build).
[group: "quality"]
build:
    bun run build

# Typecheck the TypeScript source (tsc --noEmit; bun emits, tsc only checks).
[group: "quality"]
typecheck:
    bun run typecheck

# Lint Python + TS/JSON (no changes).
[group: "quality"]
lint:
    uv run ruff check .
    bunx @biomejs/biome@@@BIOME_VERSION@@ check

# Auto-format Python + TS/JSON.
[group: "quality"]
format:
    uv run ruff format .
    uv run ruff check --fix .
    bunx @biomejs/biome@@@BIOME_VERSION@@ check --write

# Run the full test suite (pytest + Vitest).
[group: "quality"]
test:
    uv run pytest -v
    bun run test

# Typecheck + build + lint + test in one shot — the local CI gate.
[group: "quality"]
check: typecheck build lint test
"""

BIOME_JSON = """\
{
  "$schema": "https://biomejs.dev/schemas/@@BIOME_VERSION@@/schema.json",
  "assist": { "actions": { "source": { "organizeImports": "on" } } },
  "linter": {
    "enabled": true,
    "rules": {
      "recommended": true,
      "complexity": { "noForEach": "warn" },
      "style": { "noNonNullAssertion": "warn", "useConst": "error" }
    }
  },
  "formatter": {
    "enabled": true,
    "indentStyle": "space",
    "indentWidth": 2,
    "lineWidth": 100
  },
  "javascript": {
    "formatter": { "quoteStyle": "double", "semicolons": "always" }
  },
  "files": {
    "includes": [
      "src/**/*.ts",
      "**/web/data/**/*.json",
      "**/tests/js/**/*.js",
      "vitest.config.js",
      "package.json",
      "knip.json",
      "tsconfig.json",
      "!**/node_modules",
      "!**/web/dist",
      "!**/dist",
      "!**/coverage"
    ]
  }
}
"""

PACKAGE_JSON = """\
{
  "name": "@@NAME@@",
  "private": true,
  "type": "module",
  "description": "@@DESC@@ TypeScript source in src/, built to web/dist/ via bun build.@@KIT_PKG_NOTE@@ See ADR-0001.",
  "scripts": {
    "build": "bun build ./src/index.ts --target browser --format esm --outdir web/dist --external '/scripts/*'",
    "typecheck": "tsc --noEmit",
    "test": "vitest run",
    "test:watch": "vitest",
    "lint": "biome check",
    "knip": "knip"
  },@@DEPENDENCIES_BLOCK@@
  "devDependencies": {
    "typescript": "^5.7.0",
    "@comfyorg/comfyui-frontend-types": "@@COMFY_FRONTEND_TYPES_VERSION@@",
    "@biomejs/biome": "^@@BIOME_VERSION@@",
    "vitest": "^4.1.7",
    "knip": "^5.0.0"
  }
}
"""

VITEST_CONFIG = """\
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { defineConfig } from "vitest/config";

const __dirname = dirname(fileURLToPath(import.meta.url));

export default defineConfig({
  test: {
    include: ["tests/js/**/*.test.js"],
    environment: "node",
  },
  resolve: {
    alias: {
      // ComfyUI's served-path runtime import. The TS source imports the
      // absolute `/scripts/app.js` form; vitest aliases it to the mock so
      // the pure functions can be imported (and the module side-effect —
      // app.registerExtension — runs against the stub).
      "/scripts/app.js": resolve(__dirname, "tests/js/__mocks__/app.js"),
    },
  },
});
"""

APP_MOCK = """\
// Minimal stub of ComfyUI's scripts/app.js for the Vitest harness.
// Extension-module tests import `app` without a real frontend.
export const app = {
  registerExtension() {},
  graph: { _nodes: [] },
};
"""

JS_TEST_MODAL = """\
import { describe, expect, it } from "vitest";
// Vitest transpiles TypeScript, so the test imports the `.ts` source directly
// (no build step). Importing the module also confirms the registerExtension
// wiring loads cleanly against tests/js/__mocks__/app.js.
import { clampToTargets } from "../../src/index.ts";

// Smoke test so `bun run test` is green from the first commit. Exercises the
// placeholder pure helper; replace with real tests of this pack's helpers as
// they land. Add at least one jsdom DOM-attach test per modal builder (assert
// the expected element exists in modal.bodyEl after openX()) — the gate below
// covers pure helpers only, which is exactly the gap that let an empty-modal
// bug ship green. Use `vitest --environment jsdom` for those.
describe("@@NAME@@ harness", () => {
  it("recognises a target widget name and rejects a non-target", () => {
    expect(clampToTargets("@@FIRST_WIDGET@@")).toBe(@@FIRST_WIDGET_EXPECT@@);
    expect(clampToTargets("definitely-not-a-target-widget")).toBe(false);
  });
});
"""

JS_TEST_GESTURE = """\
import { describe, expect, it } from "vitest";
// Vitest transpiles TypeScript, so the test imports the `.ts` source directly
// (no build step). Importing the module also confirms the registerExtension
// wiring loads cleanly against tests/js/__mocks__/app.js.
import { pinchDistance, pointInRect, scaledSize } from "../../src/index.ts";

// Smoke tests so `bun run test` is green from the first commit. Exercise the
// pure gesture helpers. Add a jsdom test for installGestureLayer's pointer
// handling as the real resize logic lands.
describe("@@NAME@@ gesture helpers", () => {
  it("measures pinch distance", () => {
    expect(pinchDistance({ x: 0, y: 0 }, { x: 3, y: 4 })).toBe(5);
  });

  it("hit-tests a screen point against a rect", () => {
    const rect = { x: 10, y: 10, w: 100, h: 50 };
    expect(pointInRect(50, 30, rect)).toBe(true);
    expect(pointInRect(5, 30, rect)).toBe(false);
  });

  it("uniform-scales and clamps to a minimum size", () => {
    expect(scaledSize([200, 100], 1.5)).toEqual([300, 150]);
    expect(scaledSize([200, 100], 0.1, [120, 60])).toEqual([120, 60]);
  });
});
"""

TEST_INIT = '''\
"""Smoke tests for the loader stub so CI is green from the first commit."""

import @@PY_MODULE_OR_INIT@@ as pack


def test_web_directory_exported():
    assert pack.WEB_DIRECTORY == "./web/dist"


def test_node_mappings_exported():
    assert isinstance(pack.NODE_CLASS_MAPPINGS, dict)
    assert isinstance(pack.NODE_DISPLAY_NAME_MAPPINGS, dict)
'''

# Backend variant only: the backend module does `from aiohttp import web` and
# `from server import PromptServer` — ComfyUI-bundled libs the dev group does
# NOT ship. This conftest stubs them (the gallery-loader pattern) so __init__.py
# imports cleanly under pytest. Widen the stub set as the real backend grows
# (numpy/torch/PIL/folder_paths/node_helpers are the usual additions).
BACKEND_CONFTEST = '''\
"""Stub ComfyUI-bundled imports so @@PY_MODULE@@.py can be imported in a vanilla
Python environment for unit tests. The dev group ships none of these — they only
exist inside a ComfyUI install — so the module-level imports would otherwise
fail collection.
"""

from __future__ import annotations

import sys
from types import ModuleType, SimpleNamespace
from unittest.mock import MagicMock


class _StubModule(ModuleType):
    def __getattr__(self, attr: str):
        if attr.startswith("__"):
            raise AttributeError(attr)
        m = MagicMock()
        setattr(self, attr, m)
        return m


def _ensure_stub(name: str) -> ModuleType:
    if name in sys.modules and not isinstance(sys.modules[name], _StubModule):
        return sys.modules[name]
    m = _StubModule(name)
    sys.modules[name] = m
    return m


# aiohttp — the backend does `from aiohttp import web`.
_aiohttp = _ensure_stub("aiohttp")
_aiohttp.web = _ensure_stub("aiohttp.web")

# ComfyUI core `server` — the backend does `from server import PromptServer`.
_server = _ensure_stub("server")


class _NoopRoutes:
    """Decorator-shaped no-op for @PromptServer.instance.routes.get(path)."""

    def get(self, path):
        def deco(fn):
            return fn

        return deco

    def post(self, path):
        return self.get(path)


# PromptServer.instance.routes is read at module load; supply a real object so
# the @decorator calls in @@PY_MODULE@@.py return their wrapped function.
_server.PromptServer = SimpleNamespace(instance=SimpleNamespace(routes=_NoopRoutes()))
'''

CI_YML = """\
name: CI

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

permissions:
  contents: read

jobs:
  lint-python:
    name: Lint & format (Python)
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v6
      - name: Install uv
        uses: astral-sh/setup-uv@v7
      - name: Set up Python
        run: uv python install 3.12
      - name: Ruff check
        run: uvx ruff check .
      - name: Ruff format check
        run: uvx ruff format --check .

  lint-js:
    name: Lint & format (TypeScript/JSON)
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v6
      - name: Setup Biome
        uses: biomejs/setup-biome@v2
        with:
          # Pin to the schema version declared in biome.json. Bump in lockstep
          # with a config migration via `biome migrate` when upgrading.
          version: @@BIOME_VERSION@@
      - name: Biome check
        run: biome check .

  typecheck-build:
    name: Typecheck & build (TypeScript)
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v6
      - name: Set up Bun
        uses: oven-sh/setup-bun@v2
      - name: Install dependencies
        run: bun install --frozen-lockfile
      - name: Typecheck
        run: bun run typecheck
      - name: Build
        run: bun run build

  test:
    name: Tests (Python)
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v6
      - name: Install uv
        uses: astral-sh/setup-uv@v7
      - name: Set up Python
        run: uv python install 3.12
      - name: Run tests
        run: uv run --group dev pytest -v

  test-js:
    name: Tests (JavaScript)
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v6
      - name: Set up Bun
        uses: oven-sh/setup-bun@v2
      - name: Install dependencies
        run: bun install --frozen-lockfile
      - name: Run Vitest
        run: bun run test

  security:
    name: Security scanning
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v6
        with:
          # gitleaks scans <prev>^..<head>; the parent commit must be present
          # locally, so a shallow clone fails with "stderr is not empty".
          fetch-depth: 0
      - name: Gitleaks secret scan
        uses: gitleaks/gitleaks-action@v3
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
"""

# Raw string: the embedded changelog transform contains regex backslashes
# (incl. \1 replacement refs) that a normal string literal would corrupt.
PUBLISH_YML = r"""name: Publish to Comfy Registry

on:
  workflow_dispatch:
  release:
    types: [published]

jobs:
  publish-node:
    name: Publish custom node to registry
    runs-on: ubuntu-latest
    permissions:
      issues: write
    steps:
      - name: Check out code
        uses: actions/checkout@v6
      - name: Set up Bun
        uses: oven-sh/setup-bun@v2
      - name: Install dependencies and build frontend
        run: |
          bun install --frozen-lockfile
          bun run build
      - name: Publish Custom Node
        # Pinned to the main SHA that supports `skip_checkout`. The `@v1` and
        # tagged releases predate that input: they run an unconditional
        # actions/checkout that wipes the git-ignored web/dist built above, so
        # the registry tarball ships an EMPTY web/dist and the extension never
        # loads.
        uses: Comfy-Org/publish-node-action@d2366e7abb6ab16f3bb03e3520ae25c8cf749bc9 # main: skip_checkout support
        with:
          # PAT issued at https://registry.comfy.org/, stored as the
          # REGISTRY_ACCESS_TOKEN repo secret.
          personal_access_token: ${{ secrets.REGISTRY_ACCESS_TOKEN }}
          # Reuse the workspace the prior step already built (see pin comment).
          skip_checkout: 'true'

      - name: Set registry changelog from release notes
        # `comfy node publish` cannot send a changelog (Comfy-Org/comfy-cli#467),
        # so the registry's per-version "Updates" section stays empty. The
        # registry does accept the publisher PAT on the version-update endpoint
        # (fixed in Comfy-Org/registry-backend#168), so push the release-please
        # release notes there after publishing. The {versionId} path segment
        # must be the version's database UUID, not the semver string.
        # The registry renders the changelog as PLAIN TEXT (line-clamp-2 card,
        # bare <p> drawer; markdown shows raw and newlines collapse), so the
        # release-please markdown is flattened to compact plain text first.
        # Best-effort: a failure here must not fail the publish itself.
        if: github.event_name == 'release' && github.event.release.body != ''
        env:
          REGISTRY_TOKEN: ${{ secrets.REGISTRY_ACCESS_TOKEN }}
          # Passed via env (not inline interpolation) so markdown/quotes in the
          # release notes cannot inject into the shell.
          RELEASE_BODY: ${{ github.event.release.body }}
        run: |
          set -u
          node_id=$(python3 -c 'import tomllib; print(tomllib.load(open("pyproject.toml","rb"))["project"]["name"])')
          publisher_id=$(python3 -c 'import tomllib; print(tomllib.load(open("pyproject.toml","rb"))["tool"]["comfy"]["PublisherId"])')
          version=$(python3 -c 'import tomllib; print(tomllib.load(open("pyproject.toml","rb"))["project"]["version"])')
          changelog=$(python3 <<'PY'
          import os, re

          def clean(text):
              text = re.sub(r"\(\[[0-9a-f]{6,40}\]\([^)]*\)\)", "", text)
              text = re.sub(r"\[#([0-9]+)\]\([^)]*\)", r"#\1", text)
              text = re.sub(r"\[([^\]]+)\]\([^)]*\)", r"\1", text)
              text = text.replace("**", "")
              return re.sub(r"\s+", " ", text).strip().rstrip(".")

          sections, items, current = [], [], None

          def flush():
              if items:
                  prefix = current + ": " if current else ""
                  sections.append(prefix + "; ".join(items) + ".")

          for raw in os.environ.get("RELEASE_BODY", "").splitlines():
              line = raw.strip()
              if not line:
                  continue
              if re.match(r"^#+\s*\[?[0-9]+\.[0-9]+\.[0-9]+", line):
                  continue
              m = re.match(r"^#+\s+(.*)", line)
              if m:
                  flush()
                  items, current = [], clean(m.group(1))
                  continue
              m = re.match(r"^[*-]\s+(.*)", line)
              cleaned = clean(m.group(1) if m else line)
              if cleaned:
                  items.append(cleaned)

          flush()
          print("\n".join(sections))
          PY
          )
          if [ -z "$changelog" ]; then
            echo "::warning::registry changelog: release notes empty after transform for ${node_id}@${version}; skipping"
            exit 0
          fi
          version_id=$(curl -sf "https://api.comfy.org/nodes/${node_id}/versions" | jq -r --arg v "$version" '.[] | select(.version == $v) | .id')
          if [ -z "$version_id" ] || [ "$version_id" = "null" ]; then
            echo "::warning::registry changelog: could not resolve UUID for ${node_id}@${version}; Updates section left empty"
            exit 0
          fi
          if jq -n --arg c "$changelog" '{changelog: $c}' | curl -sf -X PUT "https://api.comfy.org/publishers/${publisher_id}/nodes/${node_id}/versions/${version_id}" -H "Authorization: Bearer ${REGISTRY_TOKEN}" -H 'Content-Type: application/json' --data-binary @- > /dev/null; then
            echo "registry changelog set for ${node_id}@${version} (${version_id})"
          else
            echo "::warning::registry changelog PUT failed for ${node_id}@${version}; Updates section left empty"
          fi
"""

RELEASE_PLEASE_YML = """\
name: "Release: release-please"

on:
  push:
    branches:
      - main
  workflow_dispatch: {}

concurrency:
  group: release-please-${{ github.repository }}
  cancel-in-progress: false

permissions:
  contents: write
  pull-requests: write

jobs:
  release-please:
    runs-on: ubuntu-latest
    steps:
      - name: Generate GitHub App Token
        id: app-token
        uses: actions/create-github-app-token@v3
        with:
          app-id: ${{ vars.RELEASE_PLEASE_APP_ID }}
          private-key: ${{ secrets.RELEASE_PLEASE_PRIVATE_KEY }}
      - uses: googleapis/release-please-action@v4
        id: release
        with:
          token: ${{ steps.app-token.outputs.token }}
"""

DEPENDABOT_YML = """\
version: 2
updates:
  - package-ecosystem: "github-actions"
    directory: "/"
    schedule:
      interval: "weekly"
  - package-ecosystem: "pip"
    directory: "/"
    schedule:
      interval: "weekly"
  - package-ecosystem: "npm"
    directory: "/"
    schedule:
      interval: "weekly"
"""

RP_CONFIG = """\
{
  "$schema": "https://raw.githubusercontent.com/googleapis/release-please/main/schemas/config.json",
  "packages": {
    ".": {
      "release-type": "python",
      "package-name": "@@NAME@@",
      "changelog-path": "CHANGELOG.md",
      "bump-minor-pre-major": true,
      "bump-patch-for-minor-pre-major": true
    }
  },
  "pull-request-title-pattern": "chore: release ${version}",
  "changelog-sections": [
    { "type": "feat", "section": "Features" },
    { "type": "fix", "section": "Bug Fixes" },
    { "type": "perf", "section": "Performance Improvements" },
    { "type": "docs", "section": "Documentation" },
    { "type": "chore", "section": "Miscellaneous", "hidden": false }
  ],
  "separate-pull-requests": false
}
"""

RP_MANIFEST = '{\n  ".": "0.1.0"\n}\n'

PRE_COMMIT = """\
repos:
  - repo: https://github.com/astral-sh/ruff-pre-commit
    rev: v0.11.12
    hooks:
      - id: ruff
        args: [--fix]
      - id: ruff-format

  - repo: https://github.com/biomejs/pre-commit
    rev: v0.6.1
    hooks:
      - id: biome-check
        # Match the biome.json schema (2.4.x) and CI's setup-biome pin so the
        # pre-commit hook understands the 2.x config (e.g. files.includes).
        additional_dependencies: ["@biomejs/biome@@@BIOME_VERSION@@"]

  - repo: https://github.com/pre-commit/pre-commit-hooks
    rev: v5.0.0
    hooks:
      - id: check-json
      - id: check-yaml
      - id: end-of-file-fixer
      - id: trailing-whitespace
      - id: check-added-large-files

  - repo: https://github.com/gitleaks/gitleaks
    rev: v8.24.3
    hooks:
      - id: gitleaks
"""

GITIGNORE = """\
__pycache__/
*.py[cod]
*$py.class
.Python
*.egg-info/
.eggs/
.venv/
.pytest_cache/
.ruff_cache/
node_modules/
coverage/

# Built frontend output — emitted by `bun run build`, force-shipped to the
# Comfy Registry via [tool.comfy] includes in pyproject.toml.
web/dist/

# Editor
.vscode/
.idea/
*.swp
*.swo

# OS
.DS_Store
Thumbs.db

# Local notes / scratch
TODO.local.md
NOTES.local.md
"""

# Trims the Comfy Registry tarball to runtime-only files. Fully static (no
# template tokens). Requires comfy-cli >= 1.10.3 to be honored at publish time.
COMFYIGNORE = """\
# .comfyignore — trims the Comfy Registry tarball to runtime-only files.
#
# comfy-cli builds node.zip as:  git-tracked files − .comfyignore matches
# + [tool.comfy] includes.  Patterns use gitignore (gitwildmatch) syntax.
# web/dist is force-shipped via `includes`, so it always survives these rules.
#
# Goal: ship only what ComfyUI loads at runtime (the Python backend, the
# built web/dist bundle, pyproject metadata, README/LICENSE) and keep CI,
# build inputs, tests, docs, and the screenshot pipeline out of the tarball.

# Build inputs — only the built web/dist is served, never the TS source
/src/
tsconfig.json
biome.json
knip.json
vitest.config.js
package.json
bun.lock
uv.lock
pylock.toml

# Tests
/tests/

# Docs + screenshot pipeline (Dockerfile, shell scripts, large PNGs)
/docs/
/screenshots/

# CI, release automation, repo + agent tooling
/.github/
/.claude/
.pre-commit-config.yaml
release-please-config.json
.release-please-manifest.json
.gitattributes
.gitignore
justfile
CLAUDE.md
RELEASE-CHECKLIST.md

# Source-form icon (PNG icon + banner display assets are kept)
icon.svg
"""

GITATTRIBUTES = "* text=auto eol=lf\n*.png binary\n*.jpg binary\n*.webp binary\nuv.lock linguist-generated=true\nbun.lock linguist-generated=true\n"

LICENSE = """\
MIT License

Copyright (c) @@YEAR@@ @@AUTHOR@@

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
"""

RELEASE_CHECKLIST = """\
# Release checklist

## One-time setup

- [ ] Register the publisher / confirm `PublisherId` in `pyproject.toml` `[tool.comfy]`.
- [ ] Add the repo to `gitops/repositories.tf` with `comfy_registry = true` and
      `release_please = true` (do not configure via the GitHub UI). On the Scalr
      apply, gitops pushes `REGISTRY_ACCESS_TOKEN`, `RELEASE_PLEASE_APP_ID` (var),
      and `RELEASE_PLEASE_PRIVATE_KEY` (secret) automatically — no manual secret
      creation. The `/comfy-node` orchestrator does this wiring for you.
- [ ] Verify the secrets landed: `gh secret list -R laurigates/<name>`.

## Per release

- [ ] Land work via conventional commits on feature branches → PRs to `main`.
- [ ] Merge the release-please PR (it bumps `version` + updates `CHANGELOG.md`).
- [ ] Publishing the GitHub release (release-please does this on merge)
      triggers `publish.yml`, which runs `bun install && bun run build` before
      `publish-node-action` so the built `web/dist/` exists at publish time →
      Comfy Registry. A follow-up step sets the registry version changelog
      ("Updates" section) from the release notes.
- [ ] Verify the new version appears on registry.comfy.org.
"""

ADR_0001 = """\
---
id: ADR-0001
date: @@DATE@@
status: Accepted
deciders: @@AUTHOR@@
domain: build-tooling
github-issues: []
---

# ADR-0001: TypeScript source + bun build (browser ESM)

## Context

This pack reaches deep into the **minified** ComfyUI frontend's LiteGraph
widget/node/canvas objects (`widget.onPointerDown`, `node.widgets`,
`app.canvas`, `ds.scale`/`ds.offset`). Those accesses are exactly where a
frontend-version bump silently breaks the pack. A vanilla-JS single file has no
static type checking at that seam — the largest source of silent breakage is
uncaught until runtime.

## Decision

Author the frontend in **TypeScript** under `src/` (entry `src/index.ts`) and
build to `web/dist/` with **`bun build`**:

```sh
bun build ./src/index.ts --target browser --format esm --outdir web/dist --external '/scripts/*'
```

- **Type gate**: `bun run typecheck` → `tsc --noEmit` against
  `@comfyorg/comfyui-frontend-types`. `tsc` never emits; `bun build` never
  type-checks — the two are decoupled and each stays fast and single-purpose.
- **Emit**: `bun build` produces browser-clean ESM with the `/scripts/app.js`
  runtime import left **unbundled** (`--external '/scripts/*'`), resolved at
  runtime against ComfyUI's served module. If the pack ships a static data
  corpus, append `&& cp -R web/data web/dist/data` to the build script.
- **Serve**: `__init__.py` sets `WEB_DIRECTORY = "./web/dist"`. ComfyUI serves
  that tree at `/extensions/@@NAME@@/`, so the built JS is at
  `/extensions/@@NAME@@/index.js`.
- **Distribution**: `web/dist/` is git-ignored (generated). The Comfy Registry
  tarball includes it via `[tool.comfy] includes = ["web/dist"]`, and
  `publish.yml` runs `bun run build` before `publish-node-action`.

@@ADR_KIT_SECTION@@## Type-seam notes (for future maintainers)

- `@comfyorg/comfyui-frontend-types` exports `ComfyApp` at the module root but
  **not** `LGraphNode` / `LGraphCanvas` / the widget interfaces (declared
  internally, un-exported). Model the small surface this pack touches with local
  structural interfaces rather than importing un-exportable types.
- TypeScript will not match an ambient `declare module` against a rooted
  (`/scripts/app.js`) path specifier. A `paths` mapping in `tsconfig.json` points
  that import at `src/comfyui-shims.d.ts` for type resolution; the emitted import
  string stays `/scripts/app.js` and `--external '/scripts/*'` keeps it unbundled.

## Consequences

- **Positive**: static type checking at the version-sensitive frontend seam;
  output is still plain browser ESM served as a static file (no runtime bundler,
  no framework); `knip` + `tsc` + Vitest + Biome give a complete local gate
  chain; Vitest imports the `.ts` source directly (no build dependency in tests).
- **Negative**: the edit → refresh loop now requires a `bun run build` step; a
  build artifact must exist before the registry publish (CI wires this); one more
  dev-dependency set (`typescript`, `@comfyorg/comfyui-frontend-types`, `knip`)
  and a `tsconfig.json` to maintain.

## Supersedes

This replaces the earlier vanilla-JS approach (a single `web/js/<short>.js` with
copied-in `modal-shell.js` / `modal-fuzzy.js`). The modal primitives are now
consumed from `@@MODAL_KIT_PKG@@` and `bun build` inlines them.
"""

ADR_KIT_SECTION_MODAL = """\
## Shared modal kit (not copied)

The modal-shell + fuzzy-matcher primitives come from `@@MODAL_KIT_PKG@@`
(a dependency), imported in `src/index.ts`. They are **not** vendored into the
pack — `bun build` inlines the imported code into `web/dist`. This single-sources
the primitives that were previously copied byte-identically across packs.

"""


# --------------------------------------------------------------------------- #
# Generation
# --------------------------------------------------------------------------- #
def build_file_map(
    ctx: dict[str, str], variant: str, widgets: list[str]
) -> dict[str, str]:
    backend = variant == "backend"
    gesture = variant == "gesture"
    modal = not gesture  # frontend or backend → consumes the kit

    # Shared pinned versions injected into every templated config.
    ctx["BIOME_VERSION"] = BIOME_VERSION
    ctx["COMFY_FRONTEND_TYPES_VERSION"] = COMFY_FRONTEND_TYPES_VERSION
    ctx["MODAL_KIT_PKG"] = MODAL_KIT_PKG

    # Variant-conditional pyproject bits.
    ctx["BACKEND_DEP_NOTE"] = (
        "Backend uses ComfyUI-bundled libs only (aiohttp, folder_paths, server)."
        if backend
        else "Frontend-only pack — no runtime Python deps."
    )
    # importlib import-mode keeps pytest from importing the pack-root
    # __init__.py as a discovered package (its relative import would fail).
    # Backend-only — frontend/gesture import the stub cleanly with the default.
    ctx["PYTEST_ADDOPTS"] = (
        "# importlib mode avoids pytest treating the pack-root __init__.py\n"
        "# (with its relative import) as a discovered package.\n"
        'addopts = "--import-mode=importlib"\n'
        if backend
        else ""
    )
    ctx["WIDGET_SET"] = ", ".join(f'"{w}"' for w in widgets)
    # First widget drives the modal smoke test's positive assertion.
    first_widget = widgets[0] if widgets else ""
    ctx["FIRST_WIDGET"] = first_widget
    ctx["FIRST_WIDGET_EXPECT"] = "true" if first_widget else "false"

    # package.json: only the modal variants add the kit as a runtime dependency.
    if modal:
        ctx["DEPENDENCIES_BLOCK"] = (
            '\n  "dependencies": {\n'
            f'    "{MODAL_KIT_PKG}": "{MODAL_KIT_VERSION}"\n'
            "  },"
        )
        ctx["KIT_PKG_NOTE"] = (
            f" The {MODAL_KIT_PKG} primitives are inlined by bun build."
        )
    else:
        ctx["DEPENDENCIES_BLOCK"] = ""
        ctx["KIT_PKG_NOTE"] = ""

    # CLAUDE.md conditional fragments.
    if backend:
        ctx["CLAUDE_INTRO"] = (
            f"ComfyUI custom-node pack with a thin Python backend (a node + HTTP "
            f"endpoints in `{ctx['PY_MODULE']}.py`) and a TypeScript frontend "
            f"extension built to `web/dist/` via bun. See ADR-0001."
        )
    elif gesture:
        ctx["CLAUDE_INTRO"] = (
            "Frontend-only ComfyUI custom-node pack in the canvas-gesture vein. "
            "`__init__.py` is a loader stub; the whole extension is TypeScript in "
            "`src/`, built to `web/dist/` via bun. See ADR-0001."
        )
    else:
        ctx["CLAUDE_INTRO"] = (
            "Frontend-only ComfyUI custom-node pack. `__init__.py` is a loader "
            "stub; the whole extension is TypeScript in `src/`, built to "
            "`web/dist/` via bun. See ADR-0001."
        )
    ctx["INIT_DESC"] = (
        'Imports node mappings from the backend module; exports `WEB_DIRECTORY = "./web/dist"`.'
        if backend
        else 'Empty `NODE_CLASS_MAPPINGS`; exports `WEB_DIRECTORY = "./web/dist"`.'
    )
    ctx["BACKEND_LAYOUT_ROW"] = (
        f"| `{ctx['PY_MODULE']}.py` | Node + HTTP endpoints. Bundled libs only; "
        f"arbitrary-path endpoints gate on an extension whitelist. |\n"
        if backend
        else ""
    )
    ctx["PYTEST_LAYOUT_NOTE"] = (
        " `tests/test_init.py` is the pytest backend suite."
        if backend
        else " `tests/test_init.py` is a pytest loader-stub smoke test."
    )
    ctx["DEP_RULE"] = (
        "No new Python dependencies. Backend uses ComfyUI-bundled libs only "
        "(aiohttp, folder_paths, server). A feature needing another lib → a "
        "separate companion pack."
        if backend
        else "No Python dependencies. The pack is frontend-only; a feature "
        "genuinely needing Python belongs in a separate companion pack."
    )
    ctx["KIT_RULE"] = (
        f"**Modal primitives come from `{MODAL_KIT_PKG}`** — import them, do NOT "
        "copy `modal-shell.js`/`modal-fuzzy.js` into the pack. `bun build` inlines "
        "the imported code into `web/dist`."
        if modal
        else "**No modal kit.** This gesture pack has no widget to hook and no "
        "modal; it adds a canvas pointer layer with self-contained pure helpers."
    )
    ctx["KIT_DEV_NOTE"] = (
        f"{MODAL_KIT_PKG} (inlined at build)"
        if modal
        else "(no modal kit — gesture pack)"
    )
    ctx["RESTART_NOTE"] = (
        f" Changes to `{ctx['PY_MODULE']}.py` (backend) DO require a ComfyUI restart."
        if backend
        else ""
    )
    # The smoke test imports `__init__` for both: it defines WEB_DIRECTORY and
    # re-exports the node mappings. The backend conftest stubs aiohttp/server so
    # `__init__`'s import of the backend module resolves under pytest.
    ctx["PY_MODULE_OR_INIT"] = "__init__"
    ctx["DISPLAY_NOSPACE"] = ctx["DISPLAY"].replace(" ", "")

    # ADR conditional: the modal variants document the shared-kit decision.
    ctx["ADR_KIT_SECTION"] = subst(ADR_KIT_SECTION_MODAL, ctx) if modal else ""

    # Vein-conditional fragments.
    if gesture:
        ctx["DEP_FLOOR_NOTE"] = "Floor tied to the modern Vue canvas/pointer model."
        ctx["WHAT_DESC"] = "the canvas gesture it adds and which targets it acts on"
        ctx["VEIN"] = (
            "A mobile-first ComfyUI usability pack in the *gesture* vein: instead "
            "of intercepting a single widget, a frontend extension adds a "
            "CANVAS-LEVEL pointer layer. A two-finger pinch whose centroid lands "
            "inside a **selected** node (single tap selects it) resizes that node "
            "and suppresses the native canvas zoom for the gesture's duration. The "
            "enhancement is **additive** (no-op fallback if `app.canvas` or the "
            "pointer model is absent — native corner-handle resize still works), "
            "**touch-first**, and never breaks serialized workflows (it only writes "
            "`node.size`, which is already serialized). Pure geometry helpers are "
            "exported from `src/index.ts` and unit-tested; DOM/canvas wiring stays "
            "below them."
        )
        ctx["EXT_ROW_DESC"] = (
            "The extension: canvas pointer layer + exported pure geometry helpers."
        )
        ctx["HOOK_RULE"] = (
            "**Canvas pointer model is version-sensitive.** The pinch layer reads "
            "`app.canvas` / `ds.scale` / `ds.offset` and the pointer-event stream. "
            "Keep the no-op fallback (do nothing when they are absent) so native "
            "corner-handle resize always works."
        )
        ctx["FAMILY_BLURB"] = (
            "> touch-friendly gestures and HTML modals that replace clunky native\n"
            "> LiteGraph interactions, additive and non-clobbering."
        )
        ctx["COMPAT_BULLET"] = (
            "- ComfyUI: modern Vue frontend (`comfyui-frontend-package >= 1.40`) for\n"
            "  the canvas pointer-event model (`app.canvas`, `ds.scale`/`ds.offset`)."
        )
    else:
        ctx["DEP_FLOOR_NOTE"] = "Floor tied to widget.onPointerDown availability."
        ctx["WHAT_DESC"] = "the widgets it enhances and the modal it opens"
        ctx["VEIN"] = (
            "A mobile-first ComfyUI usability pack: a frontend extension that "
            "intercepts a widget interaction (`widget.onPointerDown`, modern Vue "
            "frontend) and opens a touch-friendly HTML modal in place of a clunky "
            "native LiteGraph control. Widgets are matched **by name** (generic "
            "across node packs), the enhancement is **additive** (graceful fallback "
            "to the native control, never breaks serialized workflows), and the "
            "modal is **touch-first** (16px inputs to avoid iOS zoom, big tap "
            f"targets, momentum scroll). The modal primitives come from "
            f"`{MODAL_KIT_PKG}` (`openModalShell` / `fuzzyRank` / `highlightMatches`), "
            "imported and inlined by `bun build` — not copied into the pack."
        )
        ctx["EXT_ROW_DESC"] = (
            "The extension: widget interception + modal (consumes the modal kit)."
        )
        ctx["HOOK_RULE"] = (
            "**Frontend hook is version-sensitive.** The modal opens via "
            "`widget.onPointerDown`. Keep an explicit button-widget fallback if "
            "you depend on the modal being reachable."
        )
        ctx["FAMILY_BLURB"] = (
            "> touch-friendly HTML modals that replace clunky native LiteGraph\n"
            "> controls, detected by widget name, additive and non-clobbering."
        )
        ctx["COMPAT_BULLET"] = (
            "- ComfyUI: modern Vue frontend (`comfyui-frontend-package >= 1.40`) for the\n"
            "  `widget.onPointerDown` interception hook."
        )

    files: dict[str, str] = {
        "pyproject.toml": PYPROJECT,
        "README.md": README,
        "CLAUDE.md": CLAUDE_MD,
        "LICENSE": LICENSE,
        "RELEASE-CHECKLIST.md": RELEASE_CHECKLIST,
        "justfile": JUSTFILE,
        "biome.json": BIOME_JSON,
        "knip.json": KNIP_JSON,
        "tsconfig.json": TSCONFIG,
        "package.json": PACKAGE_JSON,
        "vitest.config.js": VITEST_CONFIG,
        ".pre-commit-config.yaml": PRE_COMMIT,
        ".gitignore": GITIGNORE,
        ".comfyignore": COMFYIGNORE,
        ".gitattributes": GITATTRIBUTES,
        "release-please-config.json": RP_CONFIG,
        ".release-please-manifest.json": RP_MANIFEST,
        ".github/workflows/ci.yml": CI_YML,
        ".github/workflows/publish.yml": PUBLISH_YML,
        ".github/workflows/release-please.yml": RELEASE_PLEASE_YML,
        ".github/dependabot.yml": DEPENDABOT_YML,
        "docs/blueprint/adrs/0001-adopt-typescript-bun-build.md": ADR_0001,
        "src/index.ts": INDEX_TS_GESTURE if gesture else INDEX_TS_MODAL,
        "src/comfyui-shims.d.ts": COMFYUI_SHIMS,
        "tests/test_init.py": TEST_INIT,
        "tests/js/__mocks__/app.js": APP_MOCK,
        "tests/js/index.test.js": JS_TEST_GESTURE if gesture else JS_TEST_MODAL,
    }
    if backend:
        files["__init__.py"] = INIT_BACKEND
        files[f"{ctx['PY_MODULE']}.py"] = BACKEND_PY
        # Stub aiohttp/server so the backend imports cleanly under pytest.
        files["tests/conftest.py"] = BACKEND_CONFTEST
    else:
        files["__init__.py"] = INIT_FRONTEND

    return {path: subst(body, ctx) for path, body in files.items()}


def main() -> int:
    p = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    p.add_argument(
        "--name", required=True, help="pack/repo name, e.g. comfyui-touch-numeric"
    )
    p.add_argument(
        "--display", required=True, help='Comfy DisplayName, e.g. "Touch Numeric"'
    )
    p.add_argument("--desc", required=True, help="one-line description")
    p.add_argument(
        "--variant", choices=["frontend", "backend", "gesture"], default="frontend"
    )
    p.add_argument(
        "--widgets",
        default="",
        help="CSV of target widget names for the TS stub (modal variants only)",
    )
    p.add_argument("--publisher", default=PUBLISHER_DEFAULT)
    p.add_argument("--author", default=AUTHOR_DEFAULT)
    p.add_argument(
        "--dir",
        default=".",
        help="parent directory to create the pack in (default: cwd)",
    )
    args = p.parse_args()

    ctx = derive(args.name)
    ctx.update(
        DISPLAY=args.display,
        DESC=args.desc,
        PUBLISHER=args.publisher,
        AUTHOR=args.author,
        YEAR=str(datetime.date.today().year),
        DATE=datetime.date.today().isoformat(),
    )
    widgets = [w.strip() for w in args.widgets.split(",") if w.strip()]

    parent = Path(args.dir).resolve()
    target = parent / args.name
    if target.exists():
        print(
            f"error: {target} already exists — refusing to overwrite", file=sys.stderr
        )
        return 1

    file_map = build_file_map(ctx, args.variant, widgets)
    for rel, content in file_map.items():
        dest = target / rel
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_text(content)

    n = len(file_map)
    print(f"\nScaffolded {args.name} ({args.variant}) — {n} files in {target}")
    print(
        "\nNext steps:\n"
        f"  cd {target}\n"
        "  git init -b main                       # seed main directly (no branch juggling)\n"
        "  uv sync --group dev\n"
        "  bun install                            # TypeScript, Biome, Vitest, knip"
        + (", comfy-modal-kit\n" if args.variant != "gesture" else "\n")
        + "  pre-commit install\n"
        "  just check                              # typecheck + build + lint + test should pass green\n"
        "\nThen:\n"
        + (
            "  - tune the pinch layer in src/index.ts "
            "(selectedNodes/nodeScreenRect/scaledSize; groups + affordance TODOs)\n"
            if args.variant == "gesture"
            else "  - implement the modal in src/index.ts (TARGET_WIDGETS + openPicker; "
            "import fuzzyRank from @laurigates/comfy-modal-kit for search)\n"
        )
        + (
            f"  - implement the node/endpoints in {ctx['PY_MODULE']}.py\n"
            if args.variant == "backend"
            else ""
        )
        + "  - add the repo to gitops/repositories.tf with comfy_registry = true\n"
        "    (do NOT create via the GitHub UI; gitops auto-pushes REGISTRY_ACCESS_TOKEN)\n"
        "  - or run the /comfy-node orchestrator, which does the gitops wiring for you\n"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
