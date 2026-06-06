#!/usr/bin/env python3
"""Add the containerized README screenshot pipeline to a ComfyUI custom-node pack.

Emits a screenshots/ directory (Docker + Playwright) that boots a pinned ComfyUI
headless, drives the pack's real frontend, and writes a PNG to a mounted docs/.
The generic infra (entrypoint, dockerignore, package.json, Dockerfile) is
identical to the comfyui-gallery-loader / comfyui-sampler-info family; capture.mjs
and workflow.json are emitted as an archetype-matched skeleton to tailor.

Stdlib-only. See SKILL.md for the full workflow (archetypes, the runtime-mount
iteration loop, pins, and gotchas).
"""

from __future__ import annotations

import argparse
import os
import stat
import sys

# --------------------------------------------------------------------------- #
# Generic files — identical across packs (modulo the @@TOKENS@@)
# --------------------------------------------------------------------------- #

DOCKERIGNORE = """# Keep the Docker build context lean. The pack source + screenshots/
# directory are all the build needs.
.git/
.github/
.venv/
.pytest_cache/
.ruff_cache/
node_modules/
docs/
tests/
uv.lock
*.egg-info/
__pycache__/
.DS_Store
.vscode/
.idea/
.claude/
TODO.local.md
NOTES.local.md
"""

ENTRYPOINT = """#!/usr/bin/env bash
#
# Launch ComfyUI headless, wait for it to be ready, then run the
# Playwright capture script. Exits non-zero if any expected screenshot is
# missing afterwards so a failed run surfaces in the build output.
#
# EXPECTED_OUTPUTS is a space-separated list of filenames (relative to
# OUT_DIR) the capture must produce. Set it via ENV in the Dockerfile.

set -euo pipefail

PORT="${COMFYUI_PORT:-8188}"
OUT_DIR="${OUT_DIR:-/out}"
COMFY_DIR="${COMFY_DIR:-/opt/ComfyUI}"
CAPTURE="${CAPTURE_SCRIPT:-/opt/screenshots/capture.mjs}"
EXPECTED_OUTPUTS="${EXPECTED_OUTPUTS:-picker.png}"
READY_URL="http://127.0.0.1:${PORT}/system_stats"
READY_TIMEOUT="${READY_TIMEOUT:-120}"

mkdir -p "${OUT_DIR}"

cd "${COMFY_DIR}"
python main.py \\
    --cpu \\
    --listen 0.0.0.0 \\
    --port "${PORT}" \\
    --disable-auto-launch \\
    >/tmp/comfyui.log 2>&1 &
COMFY_PID=$!

cleanup() {
    if kill -0 "${COMFY_PID}" 2>/dev/null; then
        kill "${COMFY_PID}" 2>/dev/null || true
        wait "${COMFY_PID}" 2>/dev/null || true
    fi
}
trap cleanup EXIT

echo "Waiting for ComfyUI to come up on ${READY_URL} (timeout: ${READY_TIMEOUT}s)..."
deadline=$(( $(date +%s) + READY_TIMEOUT ))
until curl -fs "${READY_URL}" >/dev/null 2>&1; do
    if ! kill -0 "${COMFY_PID}" 2>/dev/null; then
        echo "ComfyUI exited before becoming ready. Log tail:" >&2
        tail -n 200 /tmp/comfyui.log >&2 || true
        exit 1
    fi
    if [ "$(date +%s)" -ge "${deadline}" ]; then
        echo "ComfyUI did not become ready within ${READY_TIMEOUT}s. Log tail:" >&2
        tail -n 200 /tmp/comfyui.log >&2 || true
        exit 1
    fi
    sleep 1
done
echo "ComfyUI is ready."

node "${CAPTURE}"
status=$?

# Word-splitting on EXPECTED_OUTPUTS is intentional - it's a space-separated list.
# shellcheck disable=SC2086
for f in ${EXPECTED_OUTPUTS}; do
    if [ ! -s "${OUT_DIR}/${f}" ]; then
        echo "Missing or empty ${OUT_DIR}/${f} after capture." >&2
        exit 1
    fi
done

echo "Captured: ${EXPECTED_OUTPUTS} (in ${OUT_DIR})."
exit "${status}"
"""

PACKAGE_JSON = """{
  "name": "@@PACK@@-screenshots",
  "private": true,
  "type": "module",
  "description": "Playwright driver for generating README screenshots of @@PACK@@.",
  "dependencies": {
    "playwright": "@@PW@@"
  }
}
"""

DOCKERFILE = """# syntax=docker/dockerfile:1.7
#
# Single-stage build for the README screenshot generator. Base image: the
# official Playwright image (Node 22 + Chromium pre-installed). On top we
# install Python + clone a pinned ComfyUI release + CPU-only torch + ComfyUI's
# requirements. The entrypoint boots ComfyUI headless on :8188, waits for
# /system_stats, then runs the Playwright driver which writes /out/@@OUT@@.

# Pin to a real ComfyUI release. Bumping is deliberate - the render is sensitive
# to the frontend bundle that ships with this release. @@COMFY_REF@@ ships
# comfyui-frontend-package==1.43.18, clearing the pack's >=1.40 floor.
ARG COMFYUI_REF=@@COMFY_REF@@

# Pinning the Playwright image version pins the Chromium revision too, the
# single largest source of cross-host font-rendering drift. Keep in sync with
# the playwright version in package.json.
FROM mcr.microsoft.com/playwright:v@@PW@@-noble

ARG COMFYUI_REF

ENV DEBIAN_FRONTEND=noninteractive \\
    PIP_NO_CACHE_DIR=1 \\
    PIP_DISABLE_PIP_VERSION_CHECK=1 \\
    PIP_BREAK_SYSTEM_PACKAGES=1 \\
    EXPECTED_OUTPUTS="@@OUT@@"

RUN apt-get update \\
    && apt-get install -y --no-install-recommends \\
        python3 python3-pip python3-venv git ca-certificates \\
    && rm -rf /var/lib/apt/lists/* \\
    && ln -sf /usr/bin/python3 /usr/local/bin/python

WORKDIR /opt
RUN git clone --depth 1 --branch "${COMFYUI_REF}" \\
    https://github.com/comfyanonymous/ComfyUI.git /opt/ComfyUI

WORKDIR /opt/ComfyUI

# CPU-only torch keeps the image lean and avoids CUDA driver dependencies.
RUN pip install --index-url https://download.pytorch.org/whl/cpu \\
        torch torchvision torchaudio \\
    && pip install -r requirements.txt
@@SEED_BLOCK@@
WORKDIR /opt/screenshots
COPY screenshots/package.json /opt/screenshots/package.json
# Chromium is pre-installed in the Playwright base image, so we only need the
# npm dependency for the driver script itself.
RUN npm install --omit=dev

# The pack lives under custom_nodes/ with the canonical directory name. This
# name is the served URL prefix (/extensions/@@PACK@@/), so don't rename it.
COPY . /opt/ComfyUI/custom_nodes/@@PACK@@

COPY screenshots/capture.mjs /opt/screenshots/capture.mjs
COPY screenshots/workflow.json /opt/screenshots/workflow.json
COPY screenshots/entrypoint.sh /opt/screenshots/entrypoint.sh
RUN chmod +x /opt/screenshots/entrypoint.sh

WORKDIR /opt/ComfyUI

VOLUME ["/out"]

ENTRYPOINT ["/opt/screenshots/entrypoint.sh"]
"""

SEED_BLOCK = """
# Seed placeholder model files so the gallery grid is populated. The /list
# endpoint enumerates names only (never reads contents), so zero-byte files with
# believable names are enough. Done here so the layer is cached.
COPY screenshots/seed_models.py /opt/screenshots/seed_models.py
RUN python /opt/screenshots/seed_models.py
"""

SEED_MODELS = '''"""Seed placeholder model files so the gallery grid is not empty.

The picker grid lists real files via folder_paths.get_filename_list - a fresh
ComfyUI clone has empty model dirs. The /list endpoint enumerates names only (it
never reads contents), so zero-byte placeholders with believable names + a couple
of subfolders are enough to populate the grid and exercise the subfolder chips.
Run at Docker build time, before ComfyUI starts.
"""

from __future__ import annotations

import os

COMFY_DIR = os.environ.get("COMFY_DIR", "/opt/ComfyUI")
MODELS_DIR = os.path.join(COMFY_DIR, "models")

# category -> relative names (forward-slash subfolders allowed). Illustrative
# only; nothing is loaded. Edit to match the categories your pack lists.
SEED: dict[str, list[str]] = {
    "checkpoints": [
        "sd_xl_base_1.0.safetensors",
        "sd_xl_refiner_1.0.safetensors",
        "v1-5-pruned-emaonly.safetensors",
        "flux/flux1-dev.safetensors",
        "flux/flux1-schnell.safetensors",
        "sd35/sd3.5_large.safetensors",
    ],
    "loras": [
        "detail_tweaker_xl.safetensors",
        "add_detail.safetensors",
        "flux/realism_lora.safetensors",
        "style/ghibli_style.safetensors",
    ],
}


def main() -> None:
    for category, names in SEED.items():
        for name in names:
            path = os.path.join(MODELS_DIR, category, name)
            os.makedirs(os.path.dirname(path), exist_ok=True)
            with open(path, "wb"):
                pass
            print(f"seeded {category}/{name}")


if __name__ == "__main__":
    main()
'''

# --------------------------------------------------------------------------- #
# workflow.json templates (single-node, or a connected pair for gesture-overlay)
# --------------------------------------------------------------------------- #

WF_KSAMPLER = """{
  "last_node_id": 1,
  "last_link_id": 0,
  "nodes": [
    {
      "id": 1,
      "type": "KSampler",
      "pos": [360, 180],
      "size": [320, 262],
      "flags": {},
      "order": 0,
      "mode": 0,
      "inputs": [
        { "name": "model", "type": "MODEL", "link": null },
        { "name": "positive", "type": "CONDITIONING", "link": null },
        { "name": "negative", "type": "CONDITIONING", "link": null },
        { "name": "latent_image", "type": "LATENT", "link": null }
      ],
      "outputs": [
        { "name": "LATENT", "type": "LATENT", "links": null, "shape": 3 }
      ],
      "properties": { "Node name for S&R": "KSampler" },
      "widgets_values": [156680208700286, "randomize", 20, 8, "dpmpp_2m", "karras", 1]
    }
  ],
  "links": [],
  "groups": [],
  "config": {},
  "extra": {},
  "version": 0.4
}
"""

WF_CHECKPOINT = """{
  "last_node_id": 1,
  "last_link_id": 0,
  "nodes": [
    {
      "id": 1,
      "type": "CheckpointLoaderSimple",
      "pos": [360, 200],
      "size": [340, 100],
      "flags": {},
      "order": 0,
      "mode": 0,
      "inputs": [],
      "outputs": [
        { "name": "MODEL", "type": "MODEL", "links": null, "shape": 3 },
        { "name": "CLIP", "type": "CLIP", "links": null, "shape": 3 },
        { "name": "VAE", "type": "VAE", "links": null, "shape": 3 }
      ],
      "properties": { "Node name for S&R": "CheckpointLoaderSimple" },
      "widgets_values": ["sd_xl_base_1.0.safetensors"]
    }
  ],
  "links": [],
  "groups": [],
  "config": {},
  "extra": {},
  "version": 0.4
}
"""

WF_CLIPTEXT = """{
  "last_node_id": 1,
  "last_link_id": 0,
  "nodes": [
    {
      "id": 1,
      "type": "CLIPTextEncode",
      "pos": [360, 180],
      "size": [400, 200],
      "flags": {},
      "order": 0,
      "mode": 0,
      "inputs": [ { "name": "clip", "type": "CLIP", "link": null } ],
      "outputs": [ { "name": "CONDITIONING", "type": "CONDITIONING", "links": null, "shape": 3 } ],
      "properties": { "Node name for S&R": "CLIPTextEncode" },
      "widgets_values": ["cinematic portrait of an arctic fox in a snowstorm, (rim lighting:1.2), shallow depth of field, 85mm, masterpiece"]
    }
  ],
  "links": [],
  "groups": [],
  "config": {},
  "extra": {},
  "version": 0.4
}
"""

WF_GENERIC = """{
  "last_node_id": 1,
  "last_link_id": 0,
  "nodes": [
    {
      "id": 1,
      "type": "@@NODE@@",
      "pos": [360, 180],
      "size": [320, 220],
      "flags": {},
      "order": 0,
      "mode": 0,
      "inputs": [],
      "outputs": [],
      "properties": { "Node name for S&R": "@@NODE@@" },
      "widgets_values": []
    }
  ],
  "links": [],
  "groups": [],
  "config": {},
  "extra": {},
  "version": 0.4
}
"""

WF_CONNECTED_PAIR = """{
  "last_node_id": 2,
  "last_link_id": 1,
  "nodes": [
    {
      "id": 1,
      "type": "EmptyLatentImage",
      "pos": [80, 200],
      "size": [270, 106],
      "flags": {},
      "order": 0,
      "mode": 0,
      "inputs": [],
      "outputs": [ { "name": "LATENT", "type": "LATENT", "links": [1], "slot_index": 0, "shape": 3 } ],
      "properties": { "Node name for S&R": "EmptyLatentImage" },
      "widgets_values": [512, 512, 1]
    },
    {
      "id": 2,
      "type": "VAEDecode",
      "pos": [470, 220],
      "size": [210, 46],
      "flags": {},
      "order": 1,
      "mode": 0,
      "inputs": [
        { "name": "samples", "type": "LATENT", "link": 1 },
        { "name": "vae", "type": "VAE", "link": null }
      ],
      "outputs": [ { "name": "IMAGE", "type": "IMAGE", "links": null, "slot_index": 0, "shape": 3 } ],
      "properties": { "Node name for S&R": "VAEDecode" },
      "widgets_values": []
    }
  ],
  "links": [ [1, 1, 0, 2, 0, "LATENT"] ],
  "groups": [],
  "config": {},
  "extra": {},
  "version": 0.4
}
"""

# --------------------------------------------------------------------------- #
# capture.mjs templates, one per archetype
# --------------------------------------------------------------------------- #

CAPTURE_MODAL = """// Playwright driver for the README screenshot (MODAL archetype).
//
// Loads a workflow with the target node, invokes the pack's patched
// widget.onPointerDown to open the HTML modal, and screenshots the dialog.
// Direct widget invocation is intentional: clicking the canvas at computed
// coords is fragile; widget.onPointerDown is the exact surface the pack hooks.
//
// TODO: verify these against the real pack JS:
//   WIDGET ("@@WIDGET@@")  - the widget name the pack patches
//   FLAG   ("@@FLAG@@")    - the pack's per-widget patch-guard property
//   READY  ("@@READY@@")   - an inner dialog element proving the body rendered
// If the modal won't open this way, fall back to the pack's Strategy-B button
// (see comfyui-prompt-editor / comfyui-gallery-loader capture.mjs).

import { readFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { chromium } from "playwright";

const HERE = dirname(fileURLToPath(import.meta.url));
const WORKFLOW_PATH = resolve(HERE, "workflow.json");
const OUT_DIR = process.env.OUT_DIR || "/out";
const BASE_URL = process.env.COMFYUI_URL || "http://127.0.0.1:8188/";
// Optional: type into the modal search to show the fuzzy-match state. Empty
// (default) leaves the full view. Only used if the dialog has a .cmp-search.
const PICKER_QUERY = process.env.PICKER_QUERY || "";
const WIDGET = "@@WIDGET@@";
const FLAG = "@@FLAG@@";
const READY = "@@READY@@";

async function dismissStartupDialog(page) {
  await page.keyboard.press("Escape");
  await page.waitForTimeout(150);
  await page.evaluate(() => {
    for (const el of document.querySelectorAll(".p-dialog-mask")) el.remove();
  });
}

async function main() {
  const workflow = JSON.parse(await readFile(WORKFLOW_PATH, "utf8"));
  const browser = await chromium.launch({ args: ["--font-render-hinting=none"] });
  const context = await browser.newContext({
    viewport: { width: 1280, height: 800 },
    deviceScaleFactor: 2,
  });
  const page = await context.newPage();
  page.on("console", (msg) => {
    const t = msg.type();
    if (t === "error" || t === "warning") console.log(`[page:${t}] ${msg.text()}`);
  });

  console.log(`Navigating to ${BASE_URL}...`);
  await page.goto(BASE_URL, { waitUntil: "networkidle" });
  await page.waitForFunction(
    () => window.app && window.app.graph && Array.isArray(window.app.graph._nodes),
    null,
    { timeout: 30_000 },
  );

  console.log("Loading workflow...");
  await page.evaluate((wf) => window.app.loadGraphData(wf, true), workflow);
  await page.waitForFunction(() => window.app.graph._nodes.length >= 1, null, {
    timeout: 10_000,
  });
  await dismissStartupDialog(page);

  // Wait until the pack has patched the target widget.
  await page.waitForFunction(
    ({ widget, flag }) =>
      window.app.graph._nodes.some((n) =>
        (n.widgets || []).some((w) => w.name === widget && w[flag] === true),
      ),
    { widget: WIDGET, flag: FLAG },
    { timeout: 15_000 },
  );

  await page.evaluate(() => {
    window.app.canvas?.setDirty?.(true, true);
    window.app.canvas?.draw?.(true, true);
  });

  console.log(`Opening modal via ${WIDGET}.onPointerDown...`);
  await page.evaluate(
    ({ widget }) => {
      const node = window.app.graph._nodes.find((n) =>
        (n.widgets || []).some((w) => w.name === widget),
      );
      const w = node.widgets.find((x) => x.name === widget);
      w.onPointerDown({}, node, window.app.canvas);
    },
    { widget: WIDGET },
  );

  const dialog = page.locator(".cmp-dialog");
  await dialog.waitFor({ state: "visible", timeout: 10_000 });
  await page.waitForFunction((sel) => document.querySelector(`.cmp-dialog ${sel}`), READY, {
    timeout: 10_000,
  });

  if (PICKER_QUERY) {
    const search = dialog.locator(".cmp-search");
    await search.waitFor({ state: "visible", timeout: 5_000 });
    await search.fill(PICKER_QUERY);
    await page.waitForTimeout(300);
  }
  await page.waitForTimeout(300);

  console.log(`Capturing ${OUT_DIR}/@@OUT@@...`);
  await dialog.screenshot({ path: `${OUT_DIR}/@@OUT@@` });
  await browser.close();
}

main().catch((err) => {
  console.error("capture failed:", err);
  process.exit(1);
});
"""

CAPTURE_AFFORDANCE = """// Playwright driver for the README screenshot (GESTURE-AFFORDANCE archetype).
//
// Canvas-gesture pack - no modal. Selects a node directly (no canvas.selectNode
// -> no Vue selection toolbox) so the pack's onDrawForeground affordance paints,
// optionally injects an illustrative gesture callout, and clips the canvas around
// the node. Modeled on comfyui-touch-resize.
//
// TODO: this template injects a two-finger PINCH callout (fingertips + diverging
// arrow). If your gesture is different (drag, long-press), adjust or remove the
// injectCallout() overlay. The injected glyph is a documentation annotation -
// the pack draws only its real affordance.

import { readFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { chromium } from "playwright";

const HERE = dirname(fileURLToPath(import.meta.url));
const WORKFLOW_PATH = resolve(HERE, "workflow.json");
const OUT_DIR = process.env.OUT_DIR || "/out";
const BASE_URL = process.env.COMFYUI_URL || "http://127.0.0.1:8188/";
const ACCENT = "#ffb02e"; // keep in sync with the pack's affordance colour

async function dismissStartupDialog(page) {
  await page.keyboard.press("Escape");
  await page.waitForTimeout(150);
  await page.evaluate(() => {
    for (const el of document.querySelectorAll(".p-dialog-mask")) el.remove();
  });
}

async function main() {
  const workflow = JSON.parse(await readFile(WORKFLOW_PATH, "utf8"));
  const browser = await chromium.launch({ args: ["--font-render-hinting=none"] });
  const context = await browser.newContext({
    viewport: { width: 1280, height: 800 },
    deviceScaleFactor: 2,
  });
  const page = await context.newPage();
  page.on("console", (msg) => {
    const t = msg.type();
    if (t === "error" || t === "warning") console.log(`[page:${t}] ${msg.text()}`);
  });

  console.log(`Navigating to ${BASE_URL}...`);
  await page.goto(BASE_URL, { waitUntil: "networkidle" });
  await page.waitForFunction(
    () => window.app && window.app.graph && Array.isArray(window.app.graph._nodes),
    null,
    { timeout: 30_000 },
  );

  console.log("Loading workflow...");
  await page.evaluate((wf) => window.app.loadGraphData(wf, true), workflow);
  await page.waitForFunction(() => window.app.graph._nodes.length >= 1, null, {
    timeout: 10_000,
  });
  await dismissStartupDialog(page);

  console.log("Positioning + selecting the node...");
  const rect = await page.evaluate(() => {
    const node = window.app.graph._nodes[0];
    const canvas = window.app.canvas;
    const ds = canvas.ds;
    ds.scale = 1;
    ds.offset[0] = 240 - node.pos[0];
    ds.offset[1] = 190 - node.pos[1];
    // Select directly (no selectNode -> no Vue selection toolbox).
    node.selected = true;
    canvas.selected_nodes = { [node.id]: node };
    canvas.setDirty(true, true);
    canvas.draw(true, true);
    return {
      bx: (node.pos[0] + ds.offset[0]) * ds.scale,
      by: (node.pos[1] + ds.offset[1]) * ds.scale,
      bw: node.size[0] * ds.scale,
      bh: node.size[1] * ds.scale,
    };
  });

  // Inject a two-finger pinch callout over the node body (documentation overlay).
  await page.evaluate(
    ({ bx, by, bw, bh, accent }) => {
      const cx = bw / 2;
      const cy = bh / 2;
      const L = Math.min(bw, bh) * 0.26;
      const u = Math.SQRT1_2;
      const ax = cx - u * L;
      const ay = cy - u * L;
      const bxp = cx + u * L;
      const byp = cy + u * L;
      const f1x = cx - u * (L - 22);
      const f1y = cy - u * (L - 22);
      const f2x = cx + u * (L - 22);
      const f2y = cy + u * (L - 22);
      const svg = `
        <svg width="${bw}" height="${bh}" viewBox="0 0 ${bw} ${bh}"
             xmlns="http://www.w3.org/2000/svg" style="position:absolute;inset:0;">
          <defs>
            <marker id="tr-ah" markerUnits="userSpaceOnUse" markerWidth="18"
                    markerHeight="18" refX="12" refY="9" orient="auto-start-reverse">
              <path d="M0,0 L16,9 L0,18 Z" fill="${accent}"/>
            </marker>
          </defs>
          <line x1="${ax}" y1="${ay}" x2="${bxp}" y2="${byp}"
                stroke="rgba(0,0,0,0.5)" stroke-width="9" stroke-linecap="round"/>
          <line x1="${ax}" y1="${ay}" x2="${bxp}" y2="${byp}"
                stroke="${accent}" stroke-width="5" stroke-linecap="round"
                marker-start="url(#tr-ah)" marker-end="url(#tr-ah)"/>
          <circle cx="${f1x}" cy="${f1y}" r="15" fill="rgba(255,255,255,0.95)"
                  stroke="${accent}" stroke-width="2.5"/>
          <circle cx="${f2x}" cy="${f2y}" r="15" fill="rgba(255,255,255,0.95)"
                  stroke="${accent}" stroke-width="2.5"/>
        </svg>`;
      const overlay = document.createElement("div");
      overlay.style.cssText = [
        "position:fixed",
        `left:${bx}px`,
        `top:${by}px`,
        `width:${bw}px`,
        `height:${bh}px`,
        "pointer-events:none",
        "z-index:10000",
      ].join(";");
      overlay.innerHTML = svg;
      document.body.appendChild(overlay);
    },
    { bx: rect.bx, by: rect.by, bw: rect.bw, bh: rect.bh, accent: ACCENT },
  );

  await page.waitForTimeout(300);
  const TITLE = 30;
  const PAD = 60;
  const clip = {
    x: Math.max(0, rect.bx - PAD),
    y: Math.max(0, rect.by - TITLE - PAD),
    width: rect.bw + PAD * 2,
    height: rect.bh + TITLE + PAD * 2,
  };
  console.log(`Capturing ${OUT_DIR}/@@OUT@@...`);
  await page.screenshot({ path: `${OUT_DIR}/@@OUT@@`, clip });
  await browser.close();
}

main().catch((err) => {
  console.error("capture failed:", err);
  process.exit(1);
});
"""

CAPTURE_OVERLAY = """// Playwright driver for the README screenshot (GESTURE-OVERLAY archetype).
//
// Canvas-gesture pack whose overlay only appears during a live gesture that
// can't run headlessly (e.g. touch-connect's magnifier loupe during a connection
// drag). Synthesizes that state through the pack's real public surface: forces
// the canvas drag state, dispatches a synthetic TOUCH pointer the pack listens
// for, then screenshots the activated overlay element. Modeled on
// comfyui-touch-connect.
//
// TODO: adapt the forced state + the overlay locator to your pack:
//   - what canvas state activates the overlay (here: connecting_links)
//   - how the pack detects the gesture (here: a window touch pointerdown)
//   - how to find the overlay element (here: a fixed circular <canvas>)

import { readFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { chromium } from "playwright";

const HERE = dirname(fileURLToPath(import.meta.url));
const WORKFLOW_PATH = resolve(HERE, "workflow.json");
const OUT_DIR = process.env.OUT_DIR || "/out";
const BASE_URL = process.env.COMFYUI_URL || "http://127.0.0.1:8188/";
const FINGER_X = 560;
const FINGER_Y = 380;
const SCALE = 1.4;

async function dismissStartupDialog(page) {
  await page.keyboard.press("Escape");
  await page.waitForTimeout(150);
  await page.evaluate(() => {
    for (const el of document.querySelectorAll(".p-dialog-mask")) el.remove();
  });
}

async function main() {
  const workflow = JSON.parse(await readFile(WORKFLOW_PATH, "utf8"));
  const browser = await chromium.launch({ args: ["--font-render-hinting=none"] });
  const context = await browser.newContext({
    viewport: { width: 1280, height: 800 },
    deviceScaleFactor: 2,
    hasTouch: true,
  });
  const page = await context.newPage();
  page.on("console", (msg) => {
    const t = msg.type();
    if (t === "error" || t === "warning") console.log(`[page:${t}] ${msg.text()}`);
  });

  console.log(`Navigating to ${BASE_URL}...`);
  await page.goto(BASE_URL, { waitUntil: "networkidle" });
  await page.waitForFunction(
    () => window.app && window.app.graph && Array.isArray(window.app.graph._nodes),
    null,
    { timeout: 30_000 },
  );

  console.log("Loading workflow...");
  await page.evaluate((wf) => window.app.loadGraphData(wf, true), workflow);
  await page.waitForFunction(() => window.app.graph._nodes.length >= 1, null, {
    timeout: 10_000,
  });
  await dismissStartupDialog(page);

  console.log("Positioning view + forcing the gesture state...");
  await page.evaluate(
    ({ fingerX, fingerY, scale }) => {
      const graph = window.app.graph;
      const canvas = window.app.canvas;
      const ds = canvas.ds;
      ds.scale = scale;
      const node1 = graph._nodes[0];
      const node2 = graph._nodes[graph._nodes.length - 1];
      const gx = node2.pos[0];
      const gy = node2.pos[1] + 18;
      ds.offset[0] = fingerX / scale - gx;
      ds.offset[1] = fingerY / scale - gy;
      // Force the LiteGraph connection-drag state (modern + legacy fields).
      const out = node1.outputs && node1.outputs[0];
      if (out) {
        canvas.connecting_links = [
          { node: node1, slot: 0, output: out, type: out.type },
        ];
        canvas.connecting_node = node1;
        canvas.connecting_output = out;
      }
      canvas.setDirty(true, true);
      canvas.draw(true, true);
    },
    { fingerX: FINGER_X, fingerY: FINGER_Y, scale: SCALE },
  );

  console.log("Dispatching synthetic touch pointer...");
  await page.evaluate(
    ({ x, y }) => {
      const fire = (type) =>
        window.dispatchEvent(
          new PointerEvent(type, {
            pointerType: "touch",
            clientX: x,
            clientY: y,
            bubbles: true,
            cancelable: true,
          }),
        );
      fire("pointerdown");
      fire("pointermove");
    },
    { x: FINGER_X, y: FINGER_Y },
  );

  console.log("Waiting for the overlay to activate...");
  await page.waitForFunction(
    () => {
      const c = [...document.querySelectorAll("canvas")].find(
        (el) => el.style?.position === "fixed" && el.style?.borderRadius === "50%",
      );
      if (!c || c.style.display === "none") return false;
      c.id = "overlay-shot";
      return true;
    },
    null,
    { timeout: 8_000 },
  );
  await page.waitForTimeout(500);

  console.log(`Capturing ${OUT_DIR}/@@OUT@@...`);
  await page.locator("#overlay-shot").screenshot({ path: `${OUT_DIR}/@@OUT@@` });
  await browser.close();
}

main().catch((err) => {
  console.error("capture failed:", err);
  process.exit(1);
});
"""

README_TMPL = """# README screenshot pipeline

Containerized [Playwright](https://playwright.dev) + ComfyUI generator that
regenerates the README screenshot (`docs/@@OUT@@`) reproducibly, so the shot
doesn't depend on whatever models/theme/frontend a particular dev machine has.

## Run

From the repo root:

```sh
just screenshots
```

First build is ~4 min (clones ComfyUI, installs CPU torch + ComfyUI deps, pulls
the npm driver dep on top of the pre-baked Chromium). Cached rebuilds are ~30s.
The PNG lands at `docs/@@OUT@@`.

## Iterating without a rebuild

`capture.mjs` + `workflow.json` are COPY'd late, so editing them rebuilds in
~30s. To iterate even faster, mount them into the cached image:

```sh
docker build -f screenshots/Dockerfile -t @@PACK@@-screenshots .
docker run --rm -v "$(pwd)/docs:/out" -v "$(pwd)/screenshots/capture.mjs:/opt/screenshots/capture.mjs" -v "$(pwd)/screenshots/workflow.json:/opt/screenshots/workflow.json" @@PACK@@-screenshots
```

## Pins (bump deliberately)

- **`ARG COMFYUI_REF`** (`Dockerfile`) - the ComfyUI release pins the frontend
  bundle the render depends on.
- **Playwright version** - pinned in BOTH `Dockerfile` (`FROM ...playwright:v@@PW@@-noble`)
  and `package.json`. Keep them in lockstep; bump together.

## Don't hand-edit `docs/@@OUT@@`

It's generated. To change it, edit `capture.mjs` / `workflow.json` and re-run
`just screenshots`.
"""

JUST_RECIPE = """
##########
# Documentation artifacts
##########

# Regenerate docs/@@OUT@@ via the containerized screenshot generator.
[group: "docs"]
screenshots:
    docker build -f screenshots/Dockerfile -t @@PACK@@-screenshots .
    docker run --rm -v "$(pwd)/docs:/out" @@PACK@@-screenshots
"""


# --------------------------------------------------------------------------- #
# Generation
# --------------------------------------------------------------------------- #


def render(tmpl: str, repl: dict[str, str]) -> str:
    out = tmpl
    for key, val in repl.items():
        out = out.replace(f"@@{key}@@", val)
    return out


def write(path: str, content: str, *, executable: bool = False) -> None:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(content)
    if executable:
        mode = os.stat(path).st_mode
        os.chmod(path, mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)
    print(f"  wrote {path}")


def pick_workflow(variant: str, node: str) -> str:
    if variant == "gesture-overlay":
        return WF_CONNECTED_PAIR
    return {
        "KSampler": WF_KSAMPLER,
        "CheckpointLoaderSimple": WF_CHECKPOINT,
        "CLIPTextEncode": WF_CLIPTEXT,
    }.get(node, WF_GENERIC)


def pick_capture(variant: str) -> str:
    return {
        "modal": CAPTURE_MODAL,
        "gesture-affordance": CAPTURE_AFFORDANCE,
        "gesture-overlay": CAPTURE_OVERLAY,
    }[variant]


def append_just_recipe(pack_dir: str, repl: dict[str, str]) -> None:
    justfile = os.path.join(pack_dir, "justfile")
    recipe = render(JUST_RECIPE, repl)
    if not os.path.exists(justfile):
        print(f"  note: no justfile at {justfile}; skipping recipe (add it by hand)")
        return
    with open(justfile, encoding="utf-8") as fh:
        existing = fh.read()
    if "screenshots:" in existing:
        print(f"  note: {justfile} already has a `screenshots` recipe; not appending")
        return
    with open(justfile, "a", encoding="utf-8") as fh:
        if not existing.endswith("\n"):
            fh.write("\n")
        fh.write(recipe)
    print(f"  appended `screenshots` recipe to {justfile}")


def main() -> int:
    p = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    p.add_argument("--name", required=True, help="pack dir name = served URL segment, e.g. comfyui-touch-numeric")
    p.add_argument(
        "--variant",
        choices=["modal", "gesture-affordance", "gesture-overlay"],
        default="modal",
    )
    p.add_argument("--out", default="picker.png", help="output PNG filename (also EXPECTED_OUTPUTS)")
    p.add_argument("--node", default="KSampler", help="node type for workflow.json (modal/affordance)")
    p.add_argument("--widget", default="seed", help="widget name the pack patches (modal)")
    p.add_argument("--flag", default="_examplePatched", help="pack's per-widget patch-guard property (modal)")
    p.add_argument("--ready", default=".cmp-body", help="inner dialog selector proving the body rendered (modal)")
    p.add_argument("--seed-models", action="store_true", help="emit seed_models.py + Dockerfile seeding (backend model packs)")
    p.add_argument("--comfy-ref", default="v0.22.0", help="ComfyUI release to pin")
    p.add_argument("--playwright", default="1.49.1", help="Playwright version (Dockerfile FROM + package.json)")
    p.add_argument("--dir", default=".", help="pack repo root (default: cwd)")
    p.add_argument("--force", action="store_true", help="overwrite an existing screenshots/ dir")
    args = p.parse_args()

    pack_dir = os.path.abspath(args.dir)
    if not os.path.isdir(pack_dir):
        print(f"error: --dir {pack_dir} is not a directory", file=sys.stderr)
        return 1
    ss_dir = os.path.join(pack_dir, "screenshots")
    if os.path.isdir(ss_dir) and not args.force:
        print(f"error: {ss_dir} already exists (use --force to overwrite)", file=sys.stderr)
        return 1

    repl = {
        "PACK": args.name,
        "OUT": args.out,
        "COMFY_REF": args.comfy_ref,
        "PW": args.playwright,
        "NODE": args.node,
        "WIDGET": args.widget,
        "FLAG": args.flag,
        "READY": args.ready,
        "SEED_BLOCK": SEED_BLOCK if args.seed_models else "",
    }

    print(f"Generating screenshots/ for {args.name} (variant={args.variant})")
    write(os.path.join(ss_dir, "Dockerfile.dockerignore"), DOCKERIGNORE)
    write(os.path.join(ss_dir, "entrypoint.sh"), ENTRYPOINT, executable=True)
    write(os.path.join(ss_dir, "package.json"), render(PACKAGE_JSON, repl))
    write(os.path.join(ss_dir, "Dockerfile"), render(DOCKERFILE, repl))
    write(os.path.join(ss_dir, "workflow.json"), render(pick_workflow(args.variant, args.node), repl))
    write(os.path.join(ss_dir, "capture.mjs"), render(pick_capture(args.variant), repl))
    write(os.path.join(ss_dir, "README.md"), render(README_TMPL, repl))
    if args.seed_models:
        write(os.path.join(ss_dir, "seed_models.py"), SEED_MODELS)
    append_just_recipe(pack_dir, repl)

    print("\nNext steps:")
    print(f"  1. Tailor screenshots/capture.mjs + workflow.json to {args.name}.")
    if args.variant == "modal":
        print(f"     Verify --widget ({args.widget}), --flag ({args.flag}), --ready ({args.ready}) against the pack JS.")
    print("  2. Iterate fast (mount capture.mjs/workflow.json into the cached image - see screenshots/README.md).")
    print("  3. just screenshots  -> docs/" + args.out + ", then embed it in the README.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
