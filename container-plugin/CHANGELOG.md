# Changelog

## [2.8.2](https://github.com/laurigates/claude-plugins/compare/container-plugin-v2.8.1...container-plugin-v2.8.2) (2026-05-06)


### Bug Fixes

* **plugins:** quote args/argument-hint values to fix skill autocomplete ([#1254](https://github.com/laurigates/claude-plugins/issues/1254)) ([1874cff](https://github.com/laurigates/claude-plugins/commit/1874cfff8b724819bea6d9604b654cadf10b8038))

## [2.8.1](https://github.com/laurigates/claude-plugins/compare/container-plugin-v2.8.0...container-plugin-v2.8.1) (2026-04-25)


### Documentation

* **container-plugin:** standardise When to Use tables ([#1167](https://github.com/laurigates/claude-plugins/issues/1167)) ([9541a07](https://github.com/laurigates/claude-plugins/commit/9541a0767d0c7a35830671cd50d4d2ecf2e186c3)), closes [#1156](https://github.com/laurigates/claude-plugins/issues/1156)

## [2.8.0](https://github.com/laurigates/claude-plugins/compare/container-plugin-v2.7.1...container-plugin-v2.8.0) (2026-04-19)


### Features

* make skills discoverable by Claude's auto-invocation ([#1090](https://github.com/laurigates/claude-plugins/issues/1090)) ([cded1da](https://github.com/laurigates/claude-plugins/commit/cded1da1ebaf350cba1285b58ecadbbaa0eb01f6))

## [2.7.1](https://github.com/laurigates/claude-plugins/compare/container-plugin-v2.7.0...container-plugin-v2.7.1) (2026-04-08)


### Bug Fixes

* **blueprint-plugin:** remove model field from skills and fix invocation syntax ([#1007](https://github.com/laurigates/claude-plugins/issues/1007)) ([42e1e5b](https://github.com/laurigates/claude-plugins/commit/42e1e5b6c73d43e5de4b27cdee16e316de44d4c0))

## [2.7.0](https://github.com/laurigates/claude-plugins/compare/container-plugin-v2.6.0...container-plugin-v2.7.0) (2026-03-09)


### Features

* **rules:** update rules for Claude Code 2.1.63-2.1.71 changes ([#917](https://github.com/laurigates/claude-plugins/issues/917)) ([20341e8](https://github.com/laurigates/claude-plugins/commit/20341e871fe7e91eb79d51aa02ad7bc9003a93e1))

## [2.6.0](https://github.com/laurigates/claude-plugins/compare/container-plugin-v2.5.3...container-plugin-v2.6.0) (2026-02-27)


### Features

* add metadata fields to skill definitions across all plugins ([#828](https://github.com/laurigates/claude-plugins/issues/828)) ([59b3d1f](https://github.com/laurigates/claude-plugins/commit/59b3d1fadd8fd888f95ced8b071fb66cf6f9c825))
* add skill invocation control via user-invocable and disable-model-invocation frontmatter ([59b3d1f](https://github.com/laurigates/claude-plugins/commit/59b3d1fadd8fd888f95ced8b071fb66cf6f9c825))

## [2.5.3](https://github.com/laurigates/claude-plugins/compare/container-plugin-v2.5.2...container-plugin-v2.5.3) (2026-02-25)


### Bug Fixes

* **skills:** add missing args field to 57 skills with argument-hint ([#812](https://github.com/laurigates/claude-plugins/issues/812)) ([f670423](https://github.com/laurigates/claude-plugins/commit/f670423777d3d0e4edf52a1594ad82efaa13793e)), closes [#805](https://github.com/laurigates/claude-plugins/issues/805)

## [2.5.2](https://github.com/laurigates/claude-plugins/compare/container-plugin-v2.5.1...container-plugin-v2.5.2) (2026-02-25)


### Bug Fixes

* replace git remote get-url with git remote -v for verbose output ([#804](https://github.com/laurigates/claude-plugins/issues/804)) ([e39407a](https://github.com/laurigates/claude-plugins/commit/e39407a366d2d0ba431df0f456074b847073eea8))
* **skills:** replace git remote get-url origin with git remote -v in context commands ([e39407a](https://github.com/laurigates/claude-plugins/commit/e39407a366d2d0ba431df0f456074b847073eea8))

## [2.5.1](https://github.com/laurigates/claude-plugins/compare/container-plugin-v2.5.0...container-plugin-v2.5.1) (2026-02-23)


### Bug Fixes

* remove 2&gt;/dev/null from context commands across all plugins ([#792](https://github.com/laurigates/claude-plugins/issues/792)) ([c72e67e](https://github.com/laurigates/claude-plugins/commit/c72e67ee37e809449f0e6282c48fac01363a59fd))

## [2.5.0](https://github.com/laurigates/claude-plugins/compare/container-plugin-v2.4.0...container-plugin-v2.5.0) (2026-02-18)


### Features

* introduce three-tier model palette (opus/sonnet/haiku) ([#709](https://github.com/laurigates/claude-plugins/issues/709)) ([2c1e9cc](https://github.com/laurigates/claude-plugins/commit/2c1e9ccff5d48c2b426beac5b3b38cd4576c79a0))

## [2.4.0](https://github.com/laurigates/claude-plugins/compare/container-plugin-v2.3.5...container-plugin-v2.4.0) (2026-02-16)


### Features

* **configure-plugin:** replace detect-secrets with gitleaks for secret scanning ([#668](https://github.com/laurigates/claude-plugins/issues/668)) ([3fc5bbc](https://github.com/laurigates/claude-plugins/commit/3fc5bbc2f8500f30160cc5dfeb5e3d1253ed0a54))

## [2.3.5](https://github.com/laurigates/claude-plugins/compare/container-plugin-v2.3.4...container-plugin-v2.3.5) (2026-02-15)


### Bug Fixes

* replace broken context command patterns in skill files ([#644](https://github.com/laurigates/claude-plugins/issues/644)) ([440ba34](https://github.com/laurigates/claude-plugins/commit/440ba347bcc73a0512f74975cfd6b4af9fe8566e))

## [2.3.4](https://github.com/laurigates/claude-plugins/compare/container-plugin-v2.3.3...container-plugin-v2.3.4) (2026-02-14)


### Code Refactoring

* extract detailed content to REFERENCE.md files ([#605](https://github.com/laurigates/claude-plugins/issues/605)) ([7efbd83](https://github.com/laurigates/claude-plugins/commit/7efbd83b9a2b1ef67be702206396ba6d8102684d))

## [2.3.3](https://github.com/laurigates/claude-plugins/compare/container-plugin-v2.3.2...container-plugin-v2.3.3) (2026-02-12)


### Bug Fixes

* standardize skill name fields to kebab-case across all plugins ([72c0f83](https://github.com/laurigates/claude-plugins/commit/72c0f837a1b07004850c5906a30d619a79098f69))

## [2.3.2](https://github.com/laurigates/claude-plugins/compare/container-plugin-v2.3.1...container-plugin-v2.3.2) (2026-02-06)


### Bug Fixes

* **frontmatter:** resolve 83 validation errors across 75 files ([#434](https://github.com/laurigates/claude-plugins/issues/434)) ([5beb75e](https://github.com/laurigates/claude-plugins/commit/5beb75ed4b2cb0431d060bd7102903495c03c6c5))

## [2.3.1](https://github.com/laurigates/claude-plugins/compare/container-plugin-v2.3.0...container-plugin-v2.3.1) (2026-02-02)


### Bug Fixes

* **agent-patterns-plugin:** block git writes for parallel agents to prevent conflicts ([#299](https://github.com/laurigates/claude-plugins/issues/299)) ([a2c2ce0](https://github.com/laurigates/claude-plugins/commit/a2c2ce07d67ead9b30470b398777be355672281b))

## [2.3.0](https://github.com/laurigates/claude-plugins/compare/container-plugin-v2.2.0...container-plugin-v2.3.0) (2026-01-23)


### Features

* add model specification to all skills and commands ([#131](https://github.com/laurigates/claude-plugins/issues/131)) ([81f2961](https://github.com/laurigates/claude-plugins/commit/81f296155b50864b8b1687b9eb18a9c2cbb08791))

## [2.2.0](https://github.com/laurigates/claude-plugins/compare/container-plugin-v2.1.0...container-plugin-v2.2.0) (2026-01-21)


### Features

* **container-plugin:** add skaffold-filesync skill ([#121](https://github.com/laurigates/claude-plugins/issues/121)) ([1113703](https://github.com/laurigates/claude-plugins/commit/111370326a19e8c82fe7d45fdc7d406027e281e6))

## [2.1.0](https://github.com/laurigates/claude-plugins/compare/container-plugin-v2.0.1...container-plugin-v2.1.0) (2026-01-19)


### Features

* **container:** add OCI container labels support for GHCR integration ([#104](https://github.com/laurigates/claude-plugins/issues/104)) ([6fb88b2](https://github.com/laurigates/claude-plugins/commit/6fb88b278571ac76a11a40ae55d648b6f4320c1a))

## [2.0.1](https://github.com/laurigates/claude-plugins/compare/container-plugin-v2.0.0...container-plugin-v2.0.1) (2026-01-09)


### Bug Fixes

* sync plugin.json versions to match release-please manifest ([1ac44e1](https://github.com/laurigates/claude-plugins/commit/1ac44e1240eed27eb3f829edaaac9bc863634d89))

## [2.0.0](https://github.com/laurigates/claude-plugins/compare/container-plugin-v1.0.0...container-plugin-v2.0.0) (2025-12-28)


### ⚠ BREAKING CHANGES

* **agent-patterns-plugin:** Rename @HANDOFF to @AGENT-HANDOFF-MARKER

### Features

* **container-plugin:** add skaffold-testing skill for image validation ([29a25cb](https://github.com/laurigates/claude-plugins/commit/29a25cbb0be50d95b4dd47f1ff6ddd6cb0799cf1))


### Code Refactoring

* **agent-patterns-plugin:** reorganize handoff markers system ([a0b06f8](https://github.com/laurigates/claude-plugins/commit/a0b06f85e3b3cb7a6ca7926d7940499a7460ef57))
