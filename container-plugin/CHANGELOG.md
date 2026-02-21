# Changelog

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
