---
created: 2026-06-26
modified: 2026-06-26
reviewed: 2026-06-26
name: foundryvtt-module-scaffold
description: >-
  Scaffold a new FoundryVTT v13 module repo (Vite + TS + bun + biome, CI,
  release-please) with basic/app/libwrapper variants. Use when bootstrapping or
  init-ing a foundry module.
allowed-tools: Bash, Read, Write, Edit, Grep, Glob, TodoWrite
args: "[--name <repo>] [--display <title>] [--desc <text>] [--variant <basic|app|libwrapper>]"
argument-hint: --name foundryvtt-x --display "X" --desc "…" --variant basic
---

# foundryvtt-module-scaffold

Bootstrap a new FoundryVTT v13 **module** repo built with **Vite + TypeScript +
bun + biome**, leaving only the actual module logic to implement. The generated
repo passes `just check` (typecheck + build + lint + test) from the first commit
and distributes via the GitHub-release manifest-URL convention.

## When to Use This Skill

| Use this skill when... | Use the alternative when... |
|---|---|
| Starting a new FoundryVTT module repo — CI-green TS toolchain, release-please, and a basic/app/libwrapper skeleton before writing module logic | You want the full pipeline (repo created + seeded + gitops-adopted) → `foundryvtt-module` |
| Spinning up a FoundryVTT module backlog idea | Adding a feature to an *existing* module — this creates a **new** repo |

## The architecture it scaffolds

**TypeScript source in `src/` (entry `src/module.ts`), built to `dist/<id>.mjs`
via Vite library mode.** `vite-plugin-static-copy` places `module.json`, `lang/`,
`styles/` (and `templates/` for the app variant) into `dist/`, which Foundry
serves as the module root. `tsc --noEmit` type-checks; Vite emits — decoupled.

- **Type gate**: `bun run typecheck` → `tsc --noEmit`. Foundry globals are typed
  by loose local ambient shims (`src/foundry-shims.d.ts`), so the build is
  self-contained and CI-green without the (beta, git-only) `fvtt-types`. Verify
  the real Foundry API before relying on a shape — the shims are deliberately
  loose. Opt into `fvtt-types` later if you want richer types.
- **Build**: `bun run build` → `vite build` → `dist/<id>.mjs` + copied assets.
- **Dev**: `bun run dev` → Vite dev server on `:30001` proxying everything to
  Foundry on `:30000` except the module's own files (served with HMR).
- **Distribute via GitHub release**: `module.json` `manifest` →
  `releases/latest/download/module.json`, `download` →
  `releases/latest/download/<id>.zip`. release-please bumps `$.version` in both
  `package.json` and `module.json`; the release job builds, zips `dist/`, and
  attaches the assets. No foundryvtt.com submission is needed to install by URL
  (only to be *listed* in the in-app package browser).

## Three variants

| Variant | Use when | Adds on top of basic |
|---------|----------|----------------------|
| `basic` (default) | Settings + lifecycle behavior — the minimal well-formed module. | `init`/`ready` hooks, a registered `world` setting, i18n, scoped CSS. |
| `app` | The module has a UI panel. | An `ApplicationV2`/`HandlebarsApplicationMixin` window (`src/app.ts` + `templates/app.hbs`) and a `game.settings.registerMenu` button that opens it. |
| `libwrapper` | The module patches a core/system method. | `src/patches.ts` with a `libWrapper.register(...)` call **and** a manual monkey-patch fallback when lib-wrapper is absent; a `relationships.recommends` entry for `lib-wrapper`. |

**Decision rule:** `basic` for behavior driven by hooks/settings; `app` when the
module surfaces a window or dialog; `libwrapper` when it overrides a core method
(the conflict-safe way to do that on Foundry). Variants compose conceptually —
start from the closest one and add the rest by hand.

## How to run

`scaffold.py` is stdlib-only. Run from the workspace where the module should
land (e.g. `repos/laurigates/foundryvtt-dev/`).

Basic settings+hooks module:

```sh
python3 ${CLAUDE_SKILL_DIR}/scaffold.py --name foundryvtt-initiative-tweaks --display "Initiative Tweaks" --desc "Small quality-of-life tweaks to the combat initiative tracker."
```

Module with an ApplicationV2 UI panel:

```sh
python3 ${CLAUDE_SKILL_DIR}/scaffold.py --name foundryvtt-party-overview --display "Party Overview" --desc "A dockable party status panel for GMs." --variant app
```

Module that patches a core method via libWrapper:

```sh
python3 ${CLAUDE_SKILL_DIR}/scaffold.py --name foundryvtt-token-vision-tweak --display "Token Vision Tweak" --desc "Adjusts token vision drawing via a libWrapper-guarded patch." --variant libwrapper
```

Flags: `--name` (GitHub repo, e.g. `foundryvtt-x`), `--id` (Foundry module id;
default = `--name` minus the leading `foundryvtt-`), `--display` (title),
`--desc`, `--variant {basic,app,libwrapper}`, `--fvtt-min` / `--fvtt-verified`
(compatibility, default `12` / `13`), `--publisher` (default `laurigates`),
`--author`, `--dir` (parent dir, default cwd).

It refuses to overwrite an existing directory.

## What you get

A repo where `just check` passes from the first commit: a real `module.json`
manifest, `package.json` (bun scripts), `vite.config.ts`, strict `tsconfig.json`,
`biome.json`, `vitest.config.ts` + a green Vitest smoke test (Foundry globals
stubbed in `tests/setup.ts`), `.github/workflows/` (`ci.yml`,
`release-please.yml`, `renovate.yml`), `release-please-config.json` + manifest,
`renovate.json`, a `justfile`, `src/module.ts` + `src/settings.ts` +
`src/constants.ts` + `src/foundry-shims.d.ts`, `lang/en.json`,
`styles/<id>.css`, `CLAUDE.md`, `README.md`, `LICENSE`, and an ADR recording the
toolchain decision. The `app` variant adds `src/app.ts` + `templates/app.hbs`;
`libwrapper` adds `src/patches.ts`.

## After scaffolding

The generator prints the exact next steps. In order:

```sh
cd foundryvtt-<name>
git init -b main
bun install
just check
```

Seed `main` directly (the repo is unprotected until gitops adopts it) — pushing
a feature branch first would leave `main` missing on origin and force a rename +
default-branch fixup later. `bun install` writes `bun.lock`, which the seed
commit must include (CI uses `--frozen-lockfile`).

Then implement, and wire up infra:

1. **Implement the module** — for `basic`, `src/module.ts` + `src/settings.ts`;
   for `app`, `src/app.ts` + `templates/app.hbs`; for `libwrapper`, replace the
   `Token._draw` example in `src/patches.ts` with the real target.
2. **Add the repo to `gitops/repositories.tf`** with `release_please = true` and
   a `foundryvtt` topic (mirror the `foundryvtt-mcp` entry). On apply, gitops
   pushes the release-please App credentials.

**Or skip steps entirely:** run the **`/foundryvtt-module`** orchestrator, which
chains scaffold → `gh repo create` → seed `main` → the gitops PR.

## Hard rules baked into the output

- **`id` is the single source of truth.** `module.json` `id`, the install
  folder, and the release zip name all derive from `--id`. Lowercase kebab-case
  only.
- **ESM-only, paths byte-match the manifest.** `esmodules` references
  `<id>.mjs`; the Vite output filename is pinned to match. A mismatch is a silent
  load failure.
- **Target the harness-pinned Foundry version.** Keep `module.json`
  `compatibility.{minimum,verified}` in sync with what you test against. Verify
  the Foundry API against <https://foundryvtt.com/api/> or the live console — not
  memory.
- **Do not commit `dist/`.** It is git-ignored and rebuilt; CI builds it for
  releases.
- **Scoped CSS.** Every selector is prefixed with the module id — keep it that
  way so styles never clobber core or other modules.
- **Never hand-edit `CHANGELOG.md` or the `version` fields** — release-please
  owns them (it bumps both `package.json` and `module.json`).

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Scaffold a basic module | `python3 ${CLAUDE_SKILL_DIR}/scaffold.py --name foundryvtt-X --display "X" --desc "…"` |
| Scaffold an app module | `python3 ${CLAUDE_SKILL_DIR}/scaffold.py --name foundryvtt-X --display "X" --desc "…" --variant app` |
| Verify a generated module | `cd foundryvtt-X && bun install && just check` |

## Notes & deferrals

- The biome pin is single-sourced in `scaffold.py`'s `BIOME_VERSION` constant so
  `biome.json` and the CI `setup-biome` step never drift.
- Action/tool versions in the generated workflows are current as of scaffolding;
  the generated `renovate.yml` (laurigates reusable workflow) bumps them.
- The generated module uses **local ambient shims**, not `fvtt-types`. This keeps
  the build green and self-contained; switch `tsconfig` `types` to `fvtt-types`
  (`github:League-of-Foundry-Developers/foundry-vtt-types#main`) for full API
  types once you need them.
- Quench (in-Foundry Mocha runner) and Playwright integration tests against the
  harness are **not** scaffolded — add them when the module warrants runtime
  coverage.
