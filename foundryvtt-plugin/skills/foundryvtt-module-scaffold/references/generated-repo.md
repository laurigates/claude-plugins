# foundryvtt-module-scaffold: generated repo contents and notes

## What you get

A repo where `just check` passes from the first commit: a real `module.json`
manifest, `package.json` (bun scripts), `vite.config.ts`, strict `tsconfig.json`,
`biome.json`, `vitest.config.ts` + a green Vitest smoke test (Foundry globals
stubbed in `tests/setup.ts`) and `tests/manifest.test.ts` (the manifest-vs-build
gate above), `.github/workflows/` (`ci.yml`,
`release-please.yml`), `release-please-config.json` + manifest,
`renovate.json`, a `justfile`, `src/module.ts` + `src/settings.ts` +
`src/constants.ts` + `src/foundry-shims.d.ts`, `lang/en.json`,
`styles/<id>.css`, `CLAUDE.md`, `README.md`, `LICENSE`, and an ADR recording the
toolchain decision. The `app` variant adds `src/app.ts` + `templates/app.hbs`;
`libwrapper` adds `src/patches.ts`.

## Notes & deferrals

- The biome pin is single-sourced in `scaffold.py`'s `BIOME_VERSION` constant so
  `biome.json` and the CI `setup-biome` step never drift.
- Action/tool versions in the generated workflows are current as of scaffolding;
  the account-wide gitops Renovate App reads the emitted `renovate.json` and
  bumps them. No repo-local `renovate.yml` is emitted: a second runner kept a
  second dependency dashboard under a second bot identity (#2708).
- The generated module uses **local ambient shims**, not `fvtt-types`. This keeps
  the build green and self-contained; switch `tsconfig` `types` to `fvtt-types`
  (`github:League-of-Foundry-Developers/foundry-vtt-types#main`) for full API
  types once you need them.
- Quench (in-Foundry Mocha runner) and Playwright integration tests against the
  harness are **not** scaffolded — add them when the module warrants runtime
  coverage.
