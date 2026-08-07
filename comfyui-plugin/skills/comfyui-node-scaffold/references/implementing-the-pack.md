# comfyui-node-scaffold — Implementing the Pack

What the generator leaves in the new repo, the invariants the emitted code
assumes, and the pieces it deliberately does not generate. Read this while
filling in `src/index.ts` (and `<module>.py` on the `backend` variant), after
[`../SKILL.md`](../SKILL.md) § "After scaffolding" has the repo building.

## What you get

A repo where `just check` (typecheck + build + lint + test) passes from the
first commit: `pyproject.toml` (`[tool.comfy]` metadata with `includes =
["web/dist"]` and `Icon`/`Banner` wired to the raw-GitHub PNG URLs, ruff config,
dev deps), `.github/workflows/` (`ci.yml`, `publish.yml`, `release-please.yml`,
`renovate.yml`, `registry-health.yml`, `clear-autorelease-labels.yml`),
`renovate.json` (Renovate, **not** dependabot), strict `tsconfig.json`,
`biome.json`, `knip.json`, `.pre-commit-config.yaml`,
`release-please-config.json` (carrying the `uv.lock` `toml` updater) + manifest,
`vitest.config.js`, `package.json`
(bun scripts; modal variants add `@laurigates/comfy-modal-kit`; the build
carries a `--banner` provenance comment naming what the bundle inlines),
`tests/` (a green pytest + vitest smoke test, plus
`test_publish_hygiene.py` — simulates the comfy-cli tarball and pins the
registry scan surface; kept byte-identical across all pack repos),
`src/index.ts` + `src/comfyui-shims.d.ts`,
`__init__.py` (`WEB_DIRECTORY = "./web/dist"`), `icon.svg` + `banner.svg`
(family-style placeholders — `just assets` rasterizes them to the PNGs the
registry serves), `CLAUDE.md`, the migration ADR, `README`, `LICENSE`, and
`RELEASE-CHECKLIST.md`. The `backend` variant additionally gets `<module>.py`
(node + endpoint + whitelist gate) and `tests/conftest.py` (stubs aiohttp/server).

## Hard rules baked into the output

- **TypeScript source, bun build.** Author in `src/`; build to `web/dist/`.
  `tsc --noEmit` checks, `bun build` emits — decoupled. Never hand-edit
  `web/dist/` (it is generated; rebuild with `bun run build` and commit).
- **Modal primitives come from `@laurigates/comfy-modal-kit`** (modal variants)
  — import them; never copy `modal-shell.js`/`modal-fuzzy.js` into the pack.
  `bun build` inlines the imported code. The `gesture` and `shim` variants have
  no kit (no modal at all).
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

## Notes & deferrals

- The screenshot pipeline (`screenshots/` Docker + Playwright) and the full
  `docs/blueprint/` PRD/ADR set (beyond the single migration ADR) are **not**
  generated — they are heavy and pack-specific. Add them later (the
  `comfyui-screenshot-pipeline` skill wires the screenshots). The
  finishing-pass audit at the end of a scaffold flags this so it isn't silently
  forgotten (issue #1877).
- Icon/banner ship as **source SVGs** in the pack-family spec (400×400 dark
  inset tile `rect 28,28,344,344 rx76` + one accent glyph; 1344×576 family
  banner) — canonical spec in `comfy-registry-lifecycle` "Icon design system".
  The emitted glyph is a **placeholder letter**: replace it with a bespoke
  pictogram (no sibling pack ships a letter) in the family accent — pass
  `--subfamily touch` (default, `#ffb02e`) or `--subfamily info` (`#6ba6ff`)
  and BOTH the icon and the banner are emitted in that accent. Before this
  flag both templates hardcoded orange, so an info/gallery pack silently
  started off-spec and had to be recoloured by hand. The PNGs the registry serves are produced by
  `just assets` (rsvg-convert), not at scaffold time (stdlib-only generator);
  that recipe also **gates framing** — the tile must trim to `346×346+27+27` on
  a 400×400 canvas, which catches an icon that drifted off-spec (the trap that
  left `comfyui-touch-shim` shipping the raw 512×512 full-bleed placeholder).
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

