# ComfyUI Plugin

End-to-end lifecycle support for **ComfyUI custom-node packs** in the
laurigates mobile-first picker/gesture vein — from an idea to a pack published
on the Comfy Registry.

## Overview

This plugin packages the skills that build and ship ComfyUI node packs:
scaffolding a CI-green repository, orchestrating the full path from idea to a
live-on-registry pipeline (repo creation, seeding, and the gitops adoption PR
that wires branch protection + release-please credentials + the registry token
via the gitops repo's tofu GitHub Actions workflows), adding a reproducible
README-screenshot pipeline to a pack, plus a set of ComfyUI reference skills —
frontend/backend authoring facts, the registry release pipeline, live-smoke
testing, workflow-JSON editing, and workflow-graph node-selection reference —
useful in **any** ComfyUI pack or install, not just this plugin's own scaffold
output.

## Skills

### comfyui-node-scaffold

Scaffold a new ComfyUI custom-node repository ready for implementation, in the
**TypeScript + bun build** architecture (source in `src/`, built to `web/dist/`):

- `pyproject.toml` with Comfy Registry metadata (`[tool.comfy] includes =
  ["web/dist"]` force-ships the built output)
- CI + release-please + publish GitHub Actions (CI runs `tsc` + `bun build`;
  `publish.yml` builds before publishing)
- strict `tsconfig.json` + ruff / biome / knip / pre-commit config
- vitest (imports the `.ts` source) + pytest harness
- `src/index.ts` + `src/comfyui-shims.d.ts`, `__init__.py`
  (`WEB_DIRECTORY = "./web/dist"`), `CLAUDE.md`, and a migration ADR
- Four variants: `frontend` (per-widget modal), `backend` (adds a node +
  aiohttp endpoints), `gesture` (canvas pointer layer — pinch/drag), `shim`
  (scoped CSS injection + commands — no modal, for papering over upstream
  frontend bugs)

The `frontend`/`backend` (modal) variants consume the shared
[`@laurigates/comfy-modal-kit`](https://www.npmjs.com/package/@laurigates/comfy-modal-kit)
primitives via an `import` (inlined by `bun build`) — they no longer copy
`modal-shell.js` / `modal-fuzzy.js` in. The `gesture` and `shim` variants have
no kit dependency.

The generated `CLAUDE.md` teaches the pack to **verify the LiteGraph/canvas API
against the frontend sourcemap** (the `api-*.js.map` chunk) before coding against
the minified frontend — names are renamed in the bundle, so `instanceof` and
guessed property names are unreliable. Static types from
`@comfyorg/comfyui-frontend-types` cover the seam `ComfyApp`; the un-exported
internals are modelled with local structural interfaces.

**Use when** bootstrapping / init-ing a new ComfyUI node pack repo.

### comfy-node

Orchestrate a pack from idea to live-on-registry: scaffold (via
`comfyui-node-scaffold`), create + seed the GitHub repo, then open the gitops PR
that adds the `comfy_registry = true` entry and a transient import block so
gitops adopts the repo. Stops at the single human gate (merging the gitops PR
feeds the release-please → `tofu-apply.yml` chain), then finishes the
import-block-removal follow-up.

**Use when** releasing or spinning up a new comfyui node pack with minimal manual
steps.

### comfyui-screenshot-pipeline

Add a reproducible, containerized README-screenshot generator to an existing
pack — the piece `comfyui-node-scaffold` intentionally defers:

- Docker image pins the ComfyUI release + Playwright/Chromium revision, boots
  ComfyUI headless on CPU, drives the pack's real frontend, writes a PNG to
  `docs/`
- A `just screenshots` recipe and a `capture.mjs` driver matched to the pack
  archetype — `modal` (widget → HTML dialog), `gesture-affordance` (painted
  canvas hint), or `gesture-overlay` (synthetic-touch transient overlay)
- `--seed-models` for backend model packs whose grid would otherwise render empty

**Use when** generating README screenshots for a comfyui pack, or wiring up the
screenshot pipeline like `comfyui-gallery-loader`.

### comfyui-node-authoring

ComfyUI frontend/backend facts for writing or patching a custom node's code:
pack layout (vanilla `web/js/` and TS+bun-build), hiding a widget correctly,
the `widget.serialize = false` + append-last rule for non-persisted widgets,
DOM event isolation on the canvas, endpoint/subfolder-safety patterns, the
tooltip lookup chain, canvas hit-testing, and how to verify an undocumented
LiteGraph/Vue API against the frontend's own sourcemap instead of guessing.

**Use when** writing or patching a ComfyUI custom node's frontend or backend
code.

### comfy-registry-lifecycle

The Comfy Registry release pipeline end to end: release-please +
`uv.lock`/`bun.lock` drift traps, the empty-`web/dist` publish-action bug and
how to verify a publish actually shipped the frontend, version status states
(Pending/Active/Flagged), the security scan (any-severity flagging, email-only
reasons, `python_network_operations` / `vendored_unknown` issue classes, and
the `.comfyignore` + publish-hygiene-test surface trimming), phantom versions,
`Release-As` footers stripped by squash-merge, the `registry-health` workflow,
and generating a registry icon/banner (with `scripts/registry_banner_bg.py` +
`registry_banner_compose.py`).

**Use when** setting up, debugging, or auditing a pack's release-please →
`publish.yml` → registry.comfy.org pipeline, or when a published node's
frontend or artwork isn't showing up correctly.

### comfyui-pack-live-smoke

Stand a pack up in a real running ComfyUI instance and exercise it end to
end before publishing — both browser-driven (chrome-devtools MCP) and
headless API-driven (queue a workflow JSON, poll for completion) variants.
Catches frontend↔backend contract bugs (gating predicates, empty modals,
route mismatches) that pytest/vitest miss because they test each half in
isolation. Reads the target host from the `COMFYUI_HOST` environment
variable (default `127.0.0.1:8188`) — set it per-machine in
`.claude/settings.local.json`'s `env` block.

**Use when** verifying a pack before opening a registry/gitops PR, or
confirming an edited/built workflow JSON actually runs.

### comfy-workflow-json

Programmatically edit ComfyUI workflow JSON with a Python script instead of
hand-editing: the edge-list rebuild pattern for mutating links without
hand-surgery, the two link-encoding schemas (top-level array vs
subgraph-internal dict), preserving the `extra` block (App Mode config
lives there), and a JSON-only diagnostic for a swapped positive/negative
wiring bug.

**Use when** a workflow JSON exceeds a file-read size limit, when splicing
or rewiring nodes programmatically, or when a round-trip transform is
silently dropping App Mode or canvas state.

### comfy-subgraphs-app-mode

ComfyUI's interactive Subgraph, Subgraph Blueprint, and App Mode
(linear-mode) features: creating/editing/publishing subgraphs, why a
Blueprint instance is an isolated snapshot rather than a live reference, and
how App Mode turns a finished workflow into a fill-the-form UI.

**Use when** deciding whether to package part of a workflow as a subgraph, a
reusable Blueprint, or an App Mode UI.

### comfy-corpus-validation

The method for keeping a pack's *factual* corpus true: the source-of-truth
ladder (executable ground truth > shipped vendor templates > secondary
sources), *executing* a scheduler to measure its sigma curve rather than
asserting — or even source-reading — what it does, escalating or staying
silent when sources disagree, and treating
coverage — what the live install offers that the corpus never describes — as
a first-class check. Routes to `just corpus-check` in `comfyui-sampler-info`.

**Use when** writing or auditing sampler/scheduler/model metadata, or deciding
whether to believe a source that says "model M wants sampler S".

### Workflow-graph node-selection reference

`comfy-cli`, `comfy-conditionals`, `comfy-debug-preview`, `comfy-flow-control`,
`comfy-image-utils`, `comfy-math-strings`, `comfy-metadata`, and
`comfy-workflow-layout` are a set of "which node do I use for X" reference
skills covering the `comfy` CLI and the wider node ecosystem (predicates and
branching, debug/preview/telemetry nodes, flow-control/routing, image
processing, math/string utilities, output-metadata extraction, and
auto-layout). Each documents which installed custom-node pack owns a given
primitive and the gotchas around it (type coercion, `ExecutionBlocker`
propagation, save-node widget shapes, and so on).

**Use when** building or debugging a workflow graph and unsure which node
(or which of several similar nodes) is the right one.

## When to Use This Plugin

Install when you build ComfyUI custom-node packs and want a repeatable path from
idea to a published, registry-adopted repository. `comfyui-node-scaffold`,
`comfy-node`, and `comfyui-screenshot-pipeline` are specific to the laurigates
pack family and its gitops (tofu-in-GitHub-Actions) adoption flow; the
remaining skills (node authoring, registry lifecycle, live-smoke, workflow-JSON
editing, subgraphs/App Mode, and the workflow-graph node-selection reference)
are general ComfyUI knowledge useful in any pack repo or ComfyUI install.
