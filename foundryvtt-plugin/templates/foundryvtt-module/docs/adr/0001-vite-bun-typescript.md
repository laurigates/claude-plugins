# ADR-0001: Vite + bun + TypeScript toolchain for the FoundryVTT module

- Status: Accepted
- Date: {{ today }}

## Context

FoundryVTT modules are ESM bundles loaded from a `module.json` manifest. We need
a build that produces a single ESM file at a stable path, copies the manifest
and static assets, type-checks our code, and distributes via GitHub releases.

## Decision

- **Vite library build** (`build.lib`, ESM) → `dist/{{ module_id }}.mjs`, with
  `vite-plugin-static-copy` placing `module.json`, `lang/`, `styles/`{% if variant == "app" %}, `templates/`{% endif %}
  into `dist/`. The dev server proxies to Foundry on `:30000` with HMR.
- **bun** as the package manager/runner; **biome** for lint + format; **Vitest**
  for unit tests (Foundry globals stubbed in `tests/setup.ts`).
- **TypeScript with local ambient shims** (`src/foundry-shims.d.ts`) rather than
  the `fvtt-types` package, which is git-only and still beta for v13. The shims
  keep the build self-contained and CI-green; richer types can be opted into
  later by switching `tsconfig` `types` to `fvtt-types`.
- **Distribution via GitHub release manifest URL**: `manifest` →
  `releases/latest/download/module.json`, `download` →
  `releases/latest/download/{{ module_id }}.zip`. release-please bumps both
  `package.json` and `module.json` `$.version`; the release job builds + zips +
  attaches the assets.

## Consequences

- No foundryvtt.com submission is required to install by manifest URL (only to be
  listed in the in-app package browser).
- Foundry API types are loose — verify against the live API/docs before relying
  on a shape. This is the deliberate trade for a self-contained, green build.
