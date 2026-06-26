# FoundryVTT Plugin

End-to-end lifecycle support for **FoundryVTT v13 modules** — from an idea to a
gitops-adopted repo with release-please distribution, built on a **Vite +
TypeScript + bun + biome** toolchain.

## Overview

This plugin packages the two skills that build and ship FoundryVTT modules:
scaffolding a CI-green module repository, and orchestrating the full path from
idea to a release pipeline (repo creation, seeding, and the gitops adoption PR
that wires branch protection + release-please credentials via Scalr).

FoundryVTT modules distribute by **GitHub release manifest URL** — `manifest`
points at `releases/latest/download/module.json` and `download` at
`releases/latest/download/<id>.zip`. No foundryvtt.com submission is needed to
install by URL (only to be *listed* in the in-app package browser).

## Skills

### foundryvtt-module-scaffold

Scaffold a new FoundryVTT v13 module repository ready for implementation, in the
**Vite + TypeScript** architecture (source in `src/`, built to `dist/<id>.mjs`):

- a real `module.json` manifest (GitHub-release distribution), `package.json`
  (bun scripts), `vite.config.ts` (library build + `vite-plugin-static-copy`
  for assets + a dev-server proxy to Foundry on `:30000`)
- strict `tsconfig.json` with **local Foundry ambient shims**
  (`src/foundry-shims.d.ts`) — keeps the build self-contained and CI-green
  without the beta, git-only `fvtt-types`
- `biome.json`, a green Vitest smoke test (Foundry globals stubbed), a justfile
- CI + release-please + renovate GitHub Actions; release-please bumps both
  `package.json` and `module.json` `$.version`, and the release job zips `dist/`
  and attaches the install assets
- localization, scoped CSS, `CLAUDE.md`, `README.md`, `LICENSE`, and a toolchain ADR

Three variants:

| Variant | Adds |
|---------|------|
| `basic` (default) | `init`/`ready` hooks, a registered world setting, i18n, scoped CSS |
| `app` | an `ApplicationV2`/`HandlebarsApplicationMixin` window + a settings-menu button that opens it (Foundry v13 UI) |
| `libwrapper` | a `libWrapper`-guarded core-method patch with a manual fallback + a `relationships.recommends` for `lib-wrapper` |

**Use when** bootstrapping / init-ing a new FoundryVTT module repo.

### foundryvtt-module

Orchestrate a module from idea to release-ready: scaffold (via
`foundryvtt-module-scaffold`), create + seed the GitHub repo, then open the
gitops PR that adds the `release_please = true` entry and a transient import
block so Scalr adopts the repo. Stops at the single human gate (merging the
gitops PR triggers the Scalr apply), then finishes the import-block-removal
follow-up.

**Use when** releasing or spinning up a new FoundryVTT module with minimal
manual steps.

## When to Use This Plugin

Install when you build FoundryVTT modules and want a repeatable path from idea to
a release-pipeline-ready, gitops-adopted repository. The skills are specific to
the laurigates module family and its gitops/Scalr adoption flow, and target the
local `foundryvtt-harness` as the run/test environment.
