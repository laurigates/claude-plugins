#!/usr/bin/env python3
"""Scaffold a new ComfyUI custom-node repo in the gallery-loader / sampler-info vein.

Generates a CI-green, ready-to-implement pack: pyproject.toml, CI +
release-please + publish workflows, ruff/biome/pre-commit config, a
vitest + pytest harness, __init__.py, CLAUDE.md, a JS extension skeleton
that already wires the widget.onPointerDown → modal interception, and
(for the backend variant) an aiohttp node + endpoint skeleton with the
extension-whitelist security gate. Optionally copies the proven
modal-shell.js + modal-fuzzy.js primitives from a reference pack.

Stdlib only. Run with `python3 scaffold.py` or `uv run scaffold.py`.

Examples
--------
Frontend-only pack (sampler-info shape):
    python3 scaffold.py \
        --name comfyui-touch-numeric \
        --display "Touch Numeric" \
        --desc "Touch-friendly keypad + slider modal for seed and INT/FLOAT widgets." \
        --variant frontend \
        --widgets seed,noise_seed,cfg,steps,denoise

Pack with a small Python backend (gallery-loader shape):
    python3 scaffold.py \
        --name comfyui-model-gallery \
        --display "Model Gallery" \
        --desc "Touch-first card-grid picker for the folder-backed model combos." \
        --variant backend \
        --widgets lora_name,ckpt_name,vae_name,control_net_name

Canvas-gesture pack (no widget, no modal — a canvas pointer layer):
    python3 scaffold.py \
        --name comfyui-touch-resize \
        --display "Touch Resize" \
        --desc "Selection-gated pinch-to-resize for ComfyUI nodes and groups on touch devices." \
        --variant gesture
"""

from __future__ import annotations

import argparse
import datetime
import shutil
import sys
from pathlib import Path

AUTHOR_DEFAULT = "Lauri Gates"
PUBLISHER_DEFAULT = "laurigates"


# --------------------------------------------------------------------------- #
# Name derivation
# --------------------------------------------------------------------------- #
def derive(name: str) -> dict[str, str]:
    """Derive the family of names a pack needs from its repo name."""
    if not name.startswith("comfyui-"):
        print(f"warning: pack name '{name}' does not start with 'comfyui-'", file=sys.stderr)
    short = name.removeprefix("comfyui-")  # e.g. touch-numeric
    return {
        "NAME": name,  # comfyui-touch-numeric  (repo + served URL segment)
        "SHORT": short,  # touch-numeric
        "EXT_FILE": short,  # web/js/touch-numeric.js
        "PY_MODULE": short.replace("-", "_"),  # touch_numeric  (backend .py)
        "EXT_CONST": short.upper().replace("-", "_"),  # TOUCH_NUMERIC
        "EXT_CONST_CAMEL": _camel(short),  # touchNumeric  (JS guard-flag prefix)
    }


def _camel(short: str) -> str:
    """touch-numeric -> touchNumeric (for a JS widget guard-flag property)."""
    head, *rest = short.split("-")
    return head + "".join(part[:1].upper() + part[1:] for part in rest)


# --------------------------------------------------------------------------- #
# Templates — @@TOKEN@@ placeholders (avoids brace conflicts with JSON/JS)
# --------------------------------------------------------------------------- #
def subst(text: str, ctx: dict[str, str]) -> str:
    for key, val in ctx.items():
        text = text.replace(f"@@{key}@@", val)
    return text


PYPROJECT = '''\
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
    "comfyui-frontend-package>=1.40",
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
'''

INIT_FRONTEND = '''\
"""@@DISPLAY@@ for ComfyUI.

Frontend-only pack: no Python nodes. The whole extension lives in
web/js/@@EXT_FILE@@.js and is loaded via WEB_DIRECTORY below.
"""

WEB_DIRECTORY = "./web"

NODE_CLASS_MAPPINGS = {}
NODE_DISPLAY_NAME_MAPPINGS = {}

__all__ = ["NODE_CLASS_MAPPINGS", "NODE_DISPLAY_NAME_MAPPINGS", "WEB_DIRECTORY"]
'''

INIT_BACKEND = '''\
"""@@DISPLAY@@ for ComfyUI.

See @@PY_MODULE@@.py for the backend (node + HTTP endpoints) and
web/js/@@EXT_FILE@@.js for the frontend extension.
"""

try:
    # ComfyUI loads custom_nodes as packages — relative import works.
    from .@@PY_MODULE@@ import NODE_CLASS_MAPPINGS, NODE_DISPLAY_NAME_MAPPINGS
except ImportError:
    # Pytest imports __init__.py without a package context; fall back to
    # absolute (the pack root is on sys.path via pyproject pythonpath).
    from @@PY_MODULE@@ import NODE_CLASS_MAPPINGS, NODE_DISPLAY_NAME_MAPPINGS

WEB_DIRECTORY = "./web"

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

EXT_JS = '''\
// @@DISPLAY@@ — ComfyUI frontend extension.
//
// Served at /extensions/@@NAME@@/js/@@EXT_FILE@@.js — the pack directory
// name IS this URL segment. Do not rename the pack dir without syncing
// EXT_NAME below (used for log prefixes and any /@@PY_MODULE@@/ fetches).
//
// Pattern (shared with gallery-loader / sampler-info):
//   registerExtension -> enhance each node (on create AND on graph load) ->
//   wrap widget.onPointerDown on widgets matched BY NAME -> open an HTML
//   modal instead of the native LiteGraph control. Additive + mobile-first;
//   always chain to the original handler and fall back to the native control.
//   Requires the modern Vue frontend's onPointerDown hook
//   (comfyui-frontend-package >= 1.40).
//
// To add fuzzy search to the modal, import from ./modal-fuzzy.js:
//   import { fuzzyRank, highlightMatches } from "./modal-fuzzy.js";
//   fuzzyRank(query, [primaryField, ...otherFields]) -> { score, primaryMatches } | null

import { app } from "../../../scripts/app.js";
import { openModalShell } from "./modal-shell.js";

const EXT_NAME = "@@NAME@@";

// Widgets this pack enhances, detected by NAME (generic across node packs).
// TODO: tune this set for the pack.
const TARGET_WIDGETS = new Set([@@WIDGET_SET@@]);

function openPicker(widget, node) {
  // CONTRACT: openModalShell has NO `body` option — it returns a controller
  // ({ bodyEl, close, setBusy, setStatus, ... }) with an EMPTY bodyEl that you
  // fill AFTER opening. Passing `body:` is silently ignored and the dialog
  // renders empty (a bug that passes green unit tests — only a jsdom/browser
  // check catches it). Always: open, then modal.bodyEl.appendChild(...).
  const modal = openModalShell({
    title: widget.name,
    // search: (query) => { ... fuzzyRank over options, re-render rows ... },
    onClose: () => {},
  });

  // TODO: build the real modal body. This skeleton proves the interception
  // + modal-shell wiring works end to end. Use fuzzyRank for search.
  const body = document.createElement("div");
  body.textContent = `@@DISPLAY@@: picker for "${widget.name}" on ${node?.type} — implement me.`;
  modal.bodyEl.appendChild(body);
}

function enhanceNode(node) {
  for (const w of node?.widgets ?? []) {
    if (!TARGET_WIDGETS.has(w.name)) continue;
    if (w._@@EXT_CONST_CAMEL@@Patched) continue; // guard against double-patching
    w._@@EXT_CONST_CAMEL@@Patched = true;

    // Strategy A: wrap onPointerDown. Chain to the original first; only open
    // our modal if the original didn't consume the event.
    const origDown = w.onPointerDown;
    w.onPointerDown = function (pointer, ownerNode, canvas) {
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

    // Strategy B safety net: if a future frontend drops the onPointerDown
    // hook, an explicit button widget keeps the modal reachable. Uncomment
    // if this pack depends on the modal always being openable:
    // node.addWidget("button", `\\u{1F50D} ${w.name}`, null, () => openPicker(w, node));
  }
}

app.registerExtension({
  name: "comfy.@@SHORT@@",
  // Handle freshly created nodes AND nodes restored from a saved graph.
  async nodeCreated(node) {
    enhanceNode(node);
  },
  async loadedGraphNode(node) {
    enhanceNode(node);
  },
});
'''

GESTURE_JS = '''\
// @@DISPLAY@@ — ComfyUI frontend extension (canvas-gesture pack).
//
// Served at /extensions/@@NAME@@/js/@@EXT_FILE@@.js — the pack directory
// name IS this URL segment. Do not rename the pack dir without syncing
// EXT_NAME below.
//
// Pattern ("the gesture vein"): instead of intercepting a single widget,
// this pack adds a CANVAS-LEVEL pointer layer. A two-finger pinch whose
// centroid lands inside a *selected* node (single tap selects it) resizes
// that node and suppresses the native canvas zoom for the gesture's
// duration. Additive + mobile-first: if app.canvas or the pointer model is
// absent it does nothing and native corner-handle resize still works.
// Resize only writes node.size (already serialized) so no workflow breaks.
//
// Pure geometry helpers are exported and unit-tested (tests/js); the
// DOM/canvas wiring below is exercised in the manual browser matrix.

import { app } from "../../../scripts/app.js";

const EXT_NAME = "@@NAME@@";

// LiteGraph maps a canvas point p to screen space as (p + ds.offset) * ds.scale.
const DEFAULT_TITLE_HEIGHT = 30; // LiteGraph.NODE_TITLE_HEIGHT default.

// --- Pure helpers (unit-tested) ----------------------------------------- //

/** Euclidean distance between two {x, y} pointers. */
export function pinchDistance(a, b) {
  return Math.hypot(a.x - b.x, a.y - b.y);
}

/** Midpoint between two {x, y} pointers. */
export function centroid(a, b) {
  return { x: (a.x + b.x) / 2, y: (a.y + b.y) / 2 };
}

/** Is screen point (x, y) inside rect {x, y, w, h}? */
export function pointInRect(x, y, rect) {
  return x >= rect.x && y >= rect.y && x <= rect.x + rect.w && y <= rect.y + rect.h;
}

/** Node bounding rect (incl. title bar) in screen space. */
export function nodeScreenRect(node, scale, offset, titleHeight = DEFAULT_TITLE_HEIGHT) {
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
export function scaledSize(startSize, ratio, minSize = [0, 0]) {
  return [Math.max(minSize[0], startSize[0] * ratio), Math.max(minSize[1], startSize[1] * ratio)];
}

/** Selected nodes as an array, defensively across LiteGraph variants. */
export function selectedNodes(canvas) {
  if (!canvas) return [];
  const sel = canvas.selected_nodes;
  if (sel && typeof sel === "object") return Object.values(sel);
  if (canvas.selectedItems instanceof Set) {
    return [...canvas.selectedItems].filter((it) => it?.size && it?.pos);
  }
  return [];
}

// --- Wiring (DOM + canvas; browser-matrix tested) ----------------------- //

function installGestureLayer() {
  const canvas = app.canvas;
  const el = canvas?.canvas; // the actual <canvas> element
  if (!el) {
    console.warn(`[${EXT_NAME}] no canvas element — gesture layer not installed`);
    return;
  }

  const pointers = new Map(); // pointerId -> { x, y } in canvas-element-local space
  let lock = null; // { node, startDist, startSize, minSize }

  const localPoint = (e) => {
    const r = el.getBoundingClientRect();
    return { x: e.clientX - r.left, y: e.clientY - r.top };
  };

  function tryStartPinch() {
    if (pointers.size !== 2 || lock) return;
    const [p1, p2] = [...pointers.values()];
    const c = centroid(p1, p2);
    const scale = canvas.ds?.scale ?? 1;
    const offset = canvas.ds?.offset ?? [0, 0];
    for (const node of selectedNodes(canvas)) {
      if (pointInRect(c.x, c.y, nodeScreenRect(node, scale, offset))) {
        const minSize = typeof node.computeSize === "function" ? node.computeSize() : [0, 0];
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
      const [p1, p2] = [...pointers.values()];
      const ratio = pinchDistance(p1, p2) / lock.startDist;
      const [w, h] = scaledSize(lock.startSize, ratio, lock.minSize);
      lock.node.size[0] = w;
      lock.node.size[1] = h;
      lock.node.onResize?.(lock.node.size);
      canvas.setDirty(true, true);
      e.stopImmediatePropagation();
    },
    true,
  );

  const endPointer = (e) => {
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
'''

README = '''\
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
```

Restart ComfyUI; hard-refresh the browser tab (Ctrl+Shift+R / Cmd+Shift+R).

## What it does

TODO — describe the widgets it enhances and the modal it opens.

## Compatibility

@@COMPAT_BULLET@@
- Frontend changes (JS/CSS) take effect on browser hard-refresh — no restart.

## License

MIT — see `LICENSE`.
'''

CLAUDE_MD = '''\
# CLAUDE.md

@@CLAUDE_INTRO@@

## The pattern ("the vein")

@@VEIN@@

## File layout

| Path | Purpose |
|------|---------|
| `__init__.py` | Loader stub. @@INIT_DESC@@ |
@@BACKEND_LAYOUT_ROW@@| `web/js/@@EXT_FILE@@.js` | @@EXT_ROW_DESC@@ |
@@MODAL_LAYOUT_ROWS@@| `pyproject.toml` | Comfy Registry metadata. `PublisherId` + `version` are the fields you touch. |
| `.github/workflows/` | `ci.yml` (ruff/biome/pytest/vitest/gitleaks), `publish.yml` (auto-publish on version bump), `release-please.yml`. |
| `tests/` | pytest backend suite. `tests/js/` Vitest suite for pure JS helpers. |
| `justfile` | `lint`, `format`, `test`, `check` recipes — the local CI gate. |

## Hard rules

- **Pack directory name is part of the URL.** `web/js/@@EXT_FILE@@.js` is
  served at `/extensions/@@NAME@@/js/@@EXT_FILE@@.js`. Renaming the pack dir
  breaks every fetch. If unavoidable, sync `EXT_NAME` in the JS.
- **@@DEP_RULE@@**
- **Additive only.** Never clobber an existing tooltip/control; fall back to
  the native widget when there's no match. Never fabricate data.
- @@HOOK_RULE@@

## Dev workflow

```sh
uv sync --group dev          # ruff, pytest, pre-commit
npm install --no-audit --no-fund   # Vitest (dev-only; nothing ships from node_modules)
pre-commit install
just check                   # lint + test — the local CI gate
```

Iterating on JS/CSS/JSON needs **no ComfyUI restart** — hard-refresh the tab.
@@RESTART_NOTE@@

### Endpoint reachability check

```sh
curl -s -o /dev/null -w "%{http_code}\\n" http://127.0.0.1:8188/extensions/@@NAME@@/js/@@EXT_FILE@@.js
```

## Verify the frontend API against the sourcemap

The ComfyUI frontend (`comfyui-frontend-package`) ships **minified** — property
and method names are renamed in the bundle, so reading the running app's objects
by guessed names (or trusting old tutorials) is unreliable. Before coding against
a LiteGraph / canvas API, verify its real shape against the bundled sourcemap.

LiteGraph is bundled in the **`api-*.js.map`** chunk under
`.venv/lib/python*/site-packages/comfyui_frontend_package/static/assets/`. The
`.js.map` embeds the original TypeScript in `sourcesContent` — grep that, not the
minified `.js`:

```sh
cd .venv/lib/python*/site-packages/comfyui_frontend_package/static/assets
grep -l 'LGraphGroup' *.js.map        # find the chunk
```

```sh
python3 - <<'PY'
import json
m = json.load(open("api-<hash>.js.map"))
for name, src in zip(m["sources"], m["sourcesContent"] or []):
    if src and "class LGraphGroup" in src:
        i = src.index("class LGraphGroup"); print(name); print(src[i:i+2000]); break
PY
```

Facts worth confirming this way (recheck on a `comfyui-frontend-package` bump):
`LiteGraph.NODE_TITLE_HEIGHT` (30); `canvas.selectedItems` is a
`Set<Positionable>` holding nodes + groups + reroutes; `canvas.selected_nodes` is
a node-only dictionary; `LGraphGroup.size` self-clamps to 140×80 and has
`recomputeInsideNodes()`; canvas zoom is **wheel-driven**
(`processMouseWheel → ds.changeScale`).

Two gotchas that follow: discriminate selected items by **shape, not
`instanceof`** (the class is renamed under minification); and to suppress native
zoom during a gesture, intercept `wheel` (capture, `passive:false`,
`preventDefault`), not just pointer events. Record what you confirm in a
"Verified frontend API" table above so the next change doesn't re-derive it.

## Releases

Bump `version` in `pyproject.toml` and push to `main` →
`Comfy-Org/publish-node-action` publishes to the Comfy Registry. Requires
the `REGISTRY_ACCESS_TOKEN` repo secret. Use conventional commits;
release-please maintains `CHANGELOG.md` and the version bump PR.
'''

JUSTFILE = '''\
# @@NAME@@ — task runner. Run `just` (or `just --list`) for recipes.

set positional-arguments

# Show available recipes.
default:
    @just --list

##########
# Quality
##########

# Lint Python + JS/JSON (no changes).
[group: "quality"]
lint:
    uv run ruff check .
    npx @biomejs/biome check .

# Auto-format Python + JS/JSON.
[group: "quality"]
format:
    uv run ruff format .
    uv run ruff check --fix .
    npx @biomejs/biome check --write .

# Run the full test suite (pytest + Vitest) — the local CI gate.
[group: "quality"]
test:
    uv run pytest -v
    npm test

# Lint + test in one shot.
[group: "quality"]
check: lint test
'''

BIOME_JSON = '''\
{
  "$schema": "https://biomejs.dev/schemas/2.4.15/schema.json",
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
      "**/web/**/*.js",
      "**/web/**/*.json",
      "**/tests/js/**/*.js",
      "vitest.config.js",
      "package.json",
      "!**/node_modules",
      "!**/dist",
      "!**/coverage"
    ]
  }
}
'''

PACKAGE_JSON = '''\
{
  "name": "@@NAME@@-dev",
  "private": true,
  "type": "module",
  "description": "Dev-only test harness for @@NAME@@. Nothing here ships to users.",
  "scripts": {
    "test": "vitest run",
    "test:watch": "vitest"
  },
  "devDependencies": {
    "vitest": "^4.1.7"
  }
}
'''

VITEST_CONFIG = '''\
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
      "../../../scripts/app.js": resolve(__dirname, "tests/js/__mocks__/app.js"),
    },
  },
});
'''

APP_MOCK = '''\
// Minimal stub of ComfyUI's scripts/app.js for the Vitest harness.
// Picker-module tests import `app` without a real frontend.
export const app = {
  registerExtension() {},
  graph: { _nodes: [] },
};
'''

JS_TEST = '''\
import { describe, expect, it } from "vitest";
import { fuzzyRank } from "../../web/js/modal-fuzzy.js";

// Smoke test so `npm test` is green from the first commit. Exercises the
// copied fuzzy matcher; replace with real tests of this pack's pure helpers
// as they land. fuzzyRank(query, [primary, ...rest]) -> {score, primaryMatches} | null.
describe("@@NAME@@ harness", () => {
  it("scores a subsequence match and returns null for a non-match", () => {
    const hit = fuzzyRank("eul", ["euler"]);
    expect(hit).not.toBeNull();
    expect(hit.score).toBeGreaterThan(0);

    const miss = fuzzyRank("zzz", ["euler"]);
    expect(miss).toBeNull();
  });
});
'''

GESTURE_JS_TEST = '''\
import { describe, expect, it } from "vitest";
import { pinchDistance, pointInRect, scaledSize } from "../../web/js/@@EXT_FILE@@.js";

// Smoke tests so `npm test` is green from the first commit. Exercise the pure
// gesture helpers; importing the module also confirms the registerExtension
// wiring loads cleanly. Add a jsdom test for installGestureLayer's pointer
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
'''

TEST_INIT = '''\
"""Smoke tests for the loader stub so CI is green from the first commit."""

import @@PY_MODULE_OR_INIT@@ as pack


def test_web_directory_exported():
    assert pack.WEB_DIRECTORY == "./web"


def test_node_mappings_exported():
    assert isinstance(pack.NODE_CLASS_MAPPINGS, dict)
    assert isinstance(pack.NODE_DISPLAY_NAME_MAPPINGS, dict)
'''

CI_YML = '''\
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
    name: Lint & format (JavaScript)
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v6
      - name: Setup Biome
        uses: biomejs/setup-biome@v2
        with:
          version: 2.4.15
      - name: Biome check
        run: biome check .

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
      - name: Set up Node
        uses: actions/setup-node@v6
        with:
          node-version: '22'
      - name: Install dev dependencies
        run: npm install --no-audit --no-fund
      - name: Run Vitest
        run: npm test

  security:
    name: Security scanning
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v6
        with:
          fetch-depth: 0
      - name: Gitleaks secret scan
        uses: gitleaks/gitleaks-action@v2
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
'''

PUBLISH_YML = '''\
name: Publish to Comfy Registry

on:
  workflow_dispatch:
  push:
    branches:
      - main
    paths:
      - pyproject.toml

jobs:
  publish-node:
    name: Publish custom node to registry
    runs-on: ubuntu-latest
    permissions:
      issues: write
    steps:
      - name: Check out code
        uses: actions/checkout@v6
      - name: Publish Custom Node
        uses: Comfy-Org/publish-node-action@v1
        with:
          # PAT issued at https://registry.comfy.org/, stored as the
          # REGISTRY_ACCESS_TOKEN repo secret.
          personal_access_token: ${{ secrets.REGISTRY_ACCESS_TOKEN }}
'''

RELEASE_PLEASE_YML = '''\
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
'''

DEPENDABOT_YML = '''\
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
'''

RP_CONFIG = '''\
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
'''

RP_MANIFEST = '{\n  ".": "0.1.0"\n}\n'

PRE_COMMIT = '''\
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
        additional_dependencies: ["@biomejs/biome@1.9.4"]

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
'''

GITIGNORE = '''\
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
'''

GITATTRIBUTES = "* text=auto eol=lf\n*.png binary\n*.jpg binary\n*.webp binary\nuv.lock linguist-generated=true\npackage-lock.json linguist-generated=true\n"

LICENSE = '''\
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
'''

RELEASE_CHECKLIST = '''\
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
- [ ] The version bump on `main` triggers `publish.yml` → Comfy Registry.
- [ ] Verify the new version appears on registry.comfy.org.
'''


# --------------------------------------------------------------------------- #
# Generation
# --------------------------------------------------------------------------- #
def build_file_map(ctx: dict[str, str], variant: str, widgets: list[str]) -> dict[str, str]:
    backend = variant == "backend"
    gesture = variant == "gesture"

    # Variant-conditional pyproject bits.
    ctx["BACKEND_DEP_NOTE"] = (
        "Backend uses ComfyUI-bundled libs only (aiohttp, folder_paths, server)."
        if backend
        else "Frontend-only pack — no runtime Python deps."
    )
    ctx["PYTEST_ADDOPTS"] = (
        '# importlib mode avoids pytest treating the pack-root __init__.py\n'
        '# (with its relative import) as a discovered package.\n'
        'addopts = "--import-mode=importlib"\n'
        if backend
        else ""
    )
    ctx["WIDGET_SET"] = ", ".join(f'"{w}"' for w in widgets)

    # CLAUDE.md conditional fragments.
    if backend:
        ctx["CLAUDE_INTRO"] = (
            f"ComfyUI custom-node pack with a thin Python backend (a node + HTTP "
            f"endpoints in `{ctx['PY_MODULE']}.py`) and a JS frontend extension."
        )
    elif gesture:
        ctx["CLAUDE_INTRO"] = (
            "Frontend-only ComfyUI custom-node pack in the canvas-gesture vein. "
            "`__init__.py` is a loader stub; the whole extension lives in `web/js/`."
        )
    else:
        ctx["CLAUDE_INTRO"] = (
            "Frontend-only ComfyUI custom-node pack. `__init__.py` is a loader "
            "stub; the whole extension lives in `web/js/`."
        )
    ctx["INIT_DESC"] = (
        "Imports node mappings from the backend module; exports `WEB_DIRECTORY`."
        if backend
        else "Empty `NODE_CLASS_MAPPINGS`; exports `WEB_DIRECTORY = \"./web\"`."
    )
    ctx["BACKEND_LAYOUT_ROW"] = (
        f"| `{ctx['PY_MODULE']}.py` | Node + HTTP endpoints. Bundled libs only; "
        f"arbitrary-path endpoints gate on an extension whitelist. |\n"
        if backend
        else ""
    )
    ctx["DEP_RULE"] = (
        "No new Python dependencies. Backend uses ComfyUI-bundled libs only "
        "(aiohttp, folder_paths, server). A feature needing another lib → a "
        "separate companion pack."
        if backend
        else "No Python dependencies. The pack is frontend-only; a feature "
        "genuinely needing Python belongs in a separate companion pack."
    )
    ctx["RESTART_NOTE"] = (
        f"Changes to `{ctx['PY_MODULE']}.py` (backend) DO require a ComfyUI restart."
        if backend
        else ""
    )
    ctx["PY_MODULE_OR_INIT"] = ctx["PY_MODULE"] if backend else "__init__"
    ctx["DISPLAY_NOSPACE"] = ctx["DISPLAY"].replace(" ", "")

    # Vein-conditional fragments: the modal vein (frontend/backend) intercepts a
    # widget and opens an HTML modal; the gesture vein adds a canvas pointer layer.
    if gesture:
        ctx["DEP_FLOOR_NOTE"] = "Floor tied to the modern Vue canvas/pointer model."
        ctx["VEIN"] = (
            "A mobile-first ComfyUI usability pack in the *gesture* vein: instead "
            "of intercepting a single widget, a frontend JS extension adds a "
            "CANVAS-LEVEL pointer layer. A two-finger pinch whose centroid lands "
            "inside a **selected** node (single tap selects it) resizes that node "
            "and suppresses the native canvas zoom for the gesture's duration. The "
            "enhancement is **additive** (no-op fallback if `app.canvas` or the "
            "pointer model is absent — native corner-handle resize still works), "
            "**touch-first**, and never breaks serialized workflows (it only writes "
            "`node.size`, which is already serialized). Pure geometry helpers live "
            "at the top of the extension and are unit-tested; DOM/canvas wiring "
            "stays below them."
        )
        ctx["EXT_ROW_DESC"] = "The extension: canvas pointer layer + pure geometry helpers."
        ctx["MODAL_LAYOUT_ROWS"] = ""
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
        ctx["VEIN"] = (
            "A mobile-first ComfyUI usability pack: a frontend JS extension that "
            "intercepts a widget interaction (`widget.onPointerDown`, modern Vue "
            "frontend) and opens a touch-friendly HTML modal in place of a clunky "
            "native LiteGraph control. Widgets are matched **by name** (generic "
            "across node packs), the enhancement is **additive** (graceful fallback "
            "to the native control, never breaks serialized workflows), and the "
            "modal is **touch-first** (16px inputs to avoid iOS zoom, big tap "
            "targets, momentum scroll). Reuses `modal-shell.js` (`openModalShell` / "
            "`closeModalShell`) and `modal-fuzzy.js` (`fuzzyScore` / `fuzzyRank` / "
            "`highlightMatches`)."
        )
        ctx["EXT_ROW_DESC"] = "The extension: widget interception + modal."
        ctx["MODAL_LAYOUT_ROWS"] = (
            "| `web/js/modal-shell.js` | Reusable modal dialog (copied from gallery-loader). |\n"
            "| `web/js/modal-fuzzy.js` | fzf-lite fuzzy matcher (copied from gallery-loader). |\n"
        )
        ctx["HOOK_RULE"] = (
            "**Frontend hook is version-sensitive.** The modal opens via "
            "`widget.onPointerDown`. Keep an explicit button-widget fallback "
            "(Strategy B) if you depend on the modal being reachable."
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
        "package.json": PACKAGE_JSON,
        "vitest.config.js": VITEST_CONFIG,
        ".pre-commit-config.yaml": PRE_COMMIT,
        ".gitignore": GITIGNORE,
        ".gitattributes": GITATTRIBUTES,
        "release-please-config.json": RP_CONFIG,
        ".release-please-manifest.json": RP_MANIFEST,
        ".github/workflows/ci.yml": CI_YML,
        ".github/workflows/publish.yml": PUBLISH_YML,
        ".github/workflows/release-please.yml": RELEASE_PLEASE_YML,
        ".github/dependabot.yml": DEPENDABOT_YML,
        f"web/js/{ctx['EXT_FILE']}.js": GESTURE_JS if gesture else EXT_JS,
        "tests/test_init.py": TEST_INIT,
        "tests/js/__mocks__/app.js": APP_MOCK,
        f"tests/js/{ctx['EXT_FILE']}.test.js": GESTURE_JS_TEST if gesture else JS_TEST,
    }
    if backend:
        files["__init__.py"] = INIT_BACKEND
        files[f"{ctx['PY_MODULE']}.py"] = BACKEND_PY
    else:
        files["__init__.py"] = INIT_FRONTEND

    return {path: subst(body, ctx) for path, body in files.items()}


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--name", required=True, help="pack/repo name, e.g. comfyui-touch-numeric")
    p.add_argument("--display", required=True, help='Comfy DisplayName, e.g. "Touch Numeric"')
    p.add_argument("--desc", required=True, help="one-line description")
    p.add_argument("--variant", choices=["frontend", "backend", "gesture"], default="frontend")
    p.add_argument("--widgets", default="", help="CSV of target widget names for the JS stub (modal variants only)")
    p.add_argument("--publisher", default=PUBLISHER_DEFAULT)
    p.add_argument("--author", default=AUTHOR_DEFAULT)
    p.add_argument("--dir", default=".", help="parent directory to create the pack in (default: cwd)")
    p.add_argument(
        "--modal-source",
        default="",
        help="pack dir to copy modal-shell.js + modal-fuzzy.js from "
        "(default: <parent>/comfyui-gallery-loader). Pass 'none' to skip.",
    )
    args = p.parse_args()

    # The gesture variant imports no modal primitives — skip the copy by default.
    if args.variant == "gesture" and not args.modal_source:
        args.modal_source = "none"

    ctx = derive(args.name)
    ctx.update(
        DISPLAY=args.display,
        DESC=args.desc,
        PUBLISHER=args.publisher,
        AUTHOR=args.author,
        YEAR=str(datetime.date.today().year),
    )
    widgets = [w.strip() for w in args.widgets.split(",") if w.strip()]

    parent = Path(args.dir).resolve()
    target = parent / args.name
    if target.exists():
        print(f"error: {target} already exists — refusing to overwrite", file=sys.stderr)
        return 1

    file_map = build_file_map(ctx, args.variant, widgets)
    for rel, content in file_map.items():
        dest = target / rel
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_text(content)

    # Copy the proven modal primitives so the JS stub's imports resolve.
    copied = []
    if args.modal_source.lower() != "none":
        src_dir = Path(args.modal_source).resolve() if args.modal_source else parent / "comfyui-gallery-loader"
        for fname in ("modal-shell.js", "modal-fuzzy.js"):
            src = src_dir / "web" / "js" / fname
            if src.is_file():
                shutil.copy2(src, target / "web" / "js" / fname)
                copied.append(fname)
        if not copied:
            print(
                f"note: no modal primitives copied (looked in {src_dir}/web/js). "
                f"The JS stub imports ./modal-shell.js and ./modal-fuzzy.js — "
                f"copy them in, or adjust the imports.",
                file=sys.stderr,
            )

    n = len(file_map) + len(copied)
    print(f"\nScaffolded {args.name} ({args.variant}) — {n} files in {target}")
    if copied:
        print(f"  copied modal primitives: {', '.join(copied)}")
    print(
        "\nNext steps:\n"
        f"  cd {target}\n"
        "  git init -b main                       # seed main directly (no branch juggling)\n"
        "  uv sync --group dev\n"
        "  npm install --no-audit --no-fund\n"
        "  pre-commit install\n"
        "  just check                              # lint + test should pass green\n"
        "\nThen:\n"
        + (
            f"  - tune the pinch layer in web/js/{ctx['EXT_FILE']}.js "
            "(selectedNodes/nodeScreenRect/scaledSize; groups + affordance TODOs)\n"
            if args.variant == "gesture"
            else f"  - implement the modal in web/js/{ctx['EXT_FILE']}.js (TARGET_WIDGETS + openPicker)\n"
        )
        + (f"  - implement the node/endpoints in {ctx['PY_MODULE']}.py\n" if args.variant == "backend" else "")
        + "  - add the repo to gitops/repositories.tf with comfy_registry = true\n"
        "    (do NOT create via the GitHub UI; gitops auto-pushes REGISTRY_ACCESS_TOKEN)\n"
        "  - or run the /comfy-node orchestrator, which does the gitops wiring for you\n"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
