# ComfyUI Plugin

End-to-end lifecycle support for **ComfyUI custom-node packs** in the
laurigates mobile-first picker/gesture vein — from an idea to a pack published
on the Comfy Registry.

## Overview

This plugin packages the two skills that build and ship ComfyUI node packs:
scaffolding a CI-green repository, and orchestrating the full path from idea to
a live-on-registry pipeline (repo creation, seeding, and the gitops adoption PR
that wires branch protection + release-please credentials + the registry token
via Scalr).

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

## When to Use This Plugin

Install when you build ComfyUI custom-node packs and want a repeatable path from
idea to a published, registry-adopted repository. The skills are specific to the
laurigates pack family and its gitops/Scalr adoption flow.
