# ComfyUI Plugin

End-to-end lifecycle support for **ComfyUI custom-node packs** in the
laurigates mobile-first picker/gesture vein — from an idea to a pack published
on the Comfy Registry.

## Overview

This plugin packages the three skills that build and ship ComfyUI node packs:
scaffolding a CI-green repository, orchestrating the full path from idea to a
live-on-registry pipeline (repo creation, seeding, and the gitops adoption PR
that wires branch protection + release-please credentials + the registry token
via Scalr), and adding a reproducible README-screenshot pipeline to a pack.

## Skills

### comfyui-node-scaffold

Scaffold a new ComfyUI custom-node repository ready for implementation:

- `pyproject.toml` with Comfy Registry metadata
- CI + release-please + publish GitHub Actions
- ruff / biome / pre-commit config
- vitest + pytest harness
- `__init__.py`, `CLAUDE.md`, and a JS extension skeleton
- Three variants: `frontend` (per-widget modal), `backend` (adds a node +
  aiohttp endpoints), `gesture` (canvas pointer layer — pinch/drag)

The generated `CLAUDE.md` teaches the pack to **verify the LiteGraph/canvas API
against the frontend sourcemap** (the `api-*.js.map` chunk) before coding against
the minified frontend — names are renamed in the bundle, so `instanceof` and
guessed property names are unreliable.

**Use when** bootstrapping / init-ing a new ComfyUI node pack repo.

### comfy-node

Orchestrate a pack from idea to live-on-registry: scaffold (via
`comfyui-node-scaffold`), create + seed the GitHub repo, then open the gitops PR
that adds the `comfy_registry = true` entry and a transient import block so Scalr
adopts the repo. Stops at the single human gate (merging the gitops PR triggers
the Scalr apply), then finishes the import-block-removal follow-up.

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

## When to Use This Plugin

Install when you build ComfyUI custom-node packs and want a repeatable path from
idea to a published, registry-adopted repository. The skills are specific to the
laurigates pack family and its gitops/Scalr adoption flow.
