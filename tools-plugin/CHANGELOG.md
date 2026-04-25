# Changelog

## [2.7.1](https://github.com/laurigates/claude-plugins/compare/tools-plugin-v2.7.0...tools-plugin-v2.7.1) (2026-04-25)


### Documentation

* **tools-plugin:** standardise When to Use tables ([#1168](https://github.com/laurigates/claude-plugins/issues/1168)) ([9fe92d9](https://github.com/laurigates/claude-plugins/commit/9fe92d94e152f4a04cad2096f705eb8191e06ecf)), closes [#1156](https://github.com/laurigates/claude-plugins/issues/1156)

## [2.7.0](https://github.com/laurigates/claude-plugins/compare/tools-plugin-v2.6.0...tools-plugin-v2.7.0) (2026-04-24)


### Features

* **tools-plugin:** add cli-smoke-recipes skill ([#1137](https://github.com/laurigates/claude-plugins/issues/1137)) ([ce5b70c](https://github.com/laurigates/claude-plugins/commit/ce5b70c3326bb4fe6e9b32ba46a9bdd5ba7e73df))

## [2.6.0](https://github.com/laurigates/claude-plugins/compare/tools-plugin-v2.5.1...tools-plugin-v2.6.0) (2026-04-19)


### Features

* make skills discoverable by Claude's auto-invocation ([#1090](https://github.com/laurigates/claude-plugins/issues/1090)) ([cded1da](https://github.com/laurigates/claude-plugins/commit/cded1da1ebaf350cba1285b58ecadbbaa0eb01f6))

## [2.5.1](https://github.com/laurigates/claude-plugins/compare/tools-plugin-v2.5.0...tools-plugin-v2.5.1) (2026-04-08)


### Bug Fixes

* **blueprint-plugin:** remove model field from skills and fix invocation syntax ([#1007](https://github.com/laurigates/claude-plugins/issues/1007)) ([42e1e5b](https://github.com/laurigates/claude-plugins/commit/42e1e5b6c73d43e5de4b27cdee16e316de44d4c0))

## [2.5.0](https://github.com/laurigates/claude-plugins/compare/tools-plugin-v2.4.8...tools-plugin-v2.5.0) (2026-02-27)


### Features

* add metadata fields to skill definitions across all plugins ([#828](https://github.com/laurigates/claude-plugins/issues/828)) ([59b3d1f](https://github.com/laurigates/claude-plugins/commit/59b3d1fadd8fd888f95ced8b071fb66cf6f9c825))
* add skill invocation control via user-invocable and disable-model-invocation frontmatter ([59b3d1f](https://github.com/laurigates/claude-plugins/commit/59b3d1fadd8fd888f95ced8b071fb66cf6f9c825))

## [2.4.8](https://github.com/laurigates/claude-plugins/compare/tools-plugin-v2.4.7...tools-plugin-v2.4.8) (2026-02-25)


### Bug Fixes

* **skills:** add missing args field to 57 skills with argument-hint ([#812](https://github.com/laurigates/claude-plugins/issues/812)) ([f670423](https://github.com/laurigates/claude-plugins/commit/f670423777d3d0e4edf52a1594ad82efaa13793e)), closes [#805](https://github.com/laurigates/claude-plugins/issues/805)

## [2.4.7](https://github.com/laurigates/claude-plugins/compare/tools-plugin-v2.4.6...tools-plugin-v2.4.7) (2026-02-15)


### Bug Fixes

* remove pipe/ls operators from context commands and add CI linting ([#653](https://github.com/laurigates/claude-plugins/issues/653)) ([7a01eef](https://github.com/laurigates/claude-plugins/commit/7a01eef21495ed6243277fbaa88082b7ecabc793))

## [2.4.6](https://github.com/laurigates/claude-plugins/compare/tools-plugin-v2.4.5...tools-plugin-v2.4.6) (2026-02-14)


### Code Refactoring

* extract detailed content to REFERENCE.md files ([#605](https://github.com/laurigates/claude-plugins/issues/605)) ([7efbd83](https://github.com/laurigates/claude-plugins/commit/7efbd83b9a2b1ef67be702206396ba6d8102684d))

## [2.4.5](https://github.com/laurigates/claude-plugins/compare/tools-plugin-v2.4.4...tools-plugin-v2.4.5) (2026-02-12)


### Bug Fixes

* standardize skill name fields to kebab-case across all plugins ([72c0f83](https://github.com/laurigates/claude-plugins/commit/72c0f837a1b07004850c5906a30d619a79098f69))

## [2.4.4](https://github.com/laurigates/claude-plugins/compare/tools-plugin-v2.4.3...tools-plugin-v2.4.4) (2026-02-09)


### Code Refactoring

* reframe negative guidance as positive guidance across skills ([7e755ee](https://github.com/laurigates/claude-plugins/commit/7e755ee1c32c39c124f3204a0d0a8d1d770e1573))

## [2.4.3](https://github.com/laurigates/claude-plugins/compare/tools-plugin-v2.4.2...tools-plugin-v2.4.3) (2026-02-08)


### Bug Fixes

* update skill review dates to trigger release sync ([#489](https://github.com/laurigates/claude-plugins/issues/489)) ([ca20d06](https://github.com/laurigates/claude-plugins/commit/ca20d0667baaa31dfa805c7dc775a1828c515223))

## [2.4.2](https://github.com/laurigates/claude-plugins/compare/tools-plugin-v2.4.1...tools-plugin-v2.4.2) (2026-02-06)


### Bug Fixes

* **frontmatter:** resolve 83 validation errors across 75 files ([#434](https://github.com/laurigates/claude-plugins/issues/434)) ([5beb75e](https://github.com/laurigates/claude-plugins/commit/5beb75ed4b2cb0431d060bd7102903495c03c6c5))

## [2.4.1](https://github.com/laurigates/claude-plugins/compare/tools-plugin-v2.4.0...tools-plugin-v2.4.1) (2026-02-06)


### Documentation

* **git-plugin:** document PR check watching workflow ([24116de](https://github.com/laurigates/claude-plugins/commit/24116de12541b7af7677d5e1ed195628bf4599eb))
* improve skill documentation with decision guides and references ([#426](https://github.com/laurigates/claude-plugins/issues/426)) ([24116de](https://github.com/laurigates/claude-plugins/commit/24116de12541b7af7677d5e1ed195628bf4599eb))

## [2.4.0](https://github.com/laurigates/claude-plugins/compare/tools-plugin-v2.3.1...tools-plugin-v2.4.0) (2026-02-06)


### Features

* **tools-plugin:** add justfile naming conventions and golden template ([#424](https://github.com/laurigates/claude-plugins/issues/424)) ([75e915d](https://github.com/laurigates/claude-plugins/commit/75e915d2a31cad89854c2ce73cd0877d0990100f))

## [2.3.1](https://github.com/laurigates/claude-plugins/compare/tools-plugin-v2.3.0...tools-plugin-v2.3.1) (2026-02-01)


### Bug Fixes

* enforce granular Bash permissions across all plugins ([#267](https://github.com/laurigates/claude-plugins/issues/267)) ([afeb507](https://github.com/laurigates/claude-plugins/commit/afeb50754838c2923807c8f2a248b3798fd4281c))

## [2.3.0](https://github.com/laurigates/claude-plugins/compare/tools-plugin-v2.2.1...tools-plugin-v2.3.0) (2026-02-01)


### Features

* **tools-plugin:** enhance justfile skill with MCP, shebang, and dotenv features ([#265](https://github.com/laurigates/claude-plugins/issues/265)) ([772b610](https://github.com/laurigates/claude-plugins/commit/772b610baac131c60e3c37c663d5daef341b9a07))

## [2.2.1](https://github.com/laurigates/claude-plugins/compare/tools-plugin-v2.2.0...tools-plugin-v2.2.1) (2026-01-25)


### Bug Fixes

* rename marketplace from 'lgates-claude-plugins' to 'laurigates-plugins' ([#195](https://github.com/laurigates/claude-plugins/issues/195)) ([4310935](https://github.com/laurigates/claude-plugins/commit/43109350d121f9c0749af86461daef9849eea133))

## [2.2.1](https://github.com/laurigates/claude-plugins/compare/tools-plugin-v2.2.0...tools-plugin-v2.2.1) (2026-01-25)


### Bug Fixes

* rename marketplace from 'lgates-claude-plugins' to 'laurigates-plugins' ([#195](https://github.com/laurigates/claude-plugins/issues/195)) ([4310935](https://github.com/laurigates/claude-plugins/commit/43109350d121f9c0749af86461daef9849eea133))

## [2.2.0](https://github.com/laurigates/claude-plugins/compare/tools-plugin-v2.1.0...tools-plugin-v2.2.0) (2026-01-23)


### Features

* add model specification to all skills and commands ([#131](https://github.com/laurigates/claude-plugins/issues/131)) ([81f2961](https://github.com/laurigates/claude-plugins/commit/81f296155b50864b8b1687b9eb18a9c2cbb08791))

## [2.1.0](https://github.com/laurigates/claude-plugins/compare/tools-plugin-v2.0.1...tools-plugin-v2.1.0) (2026-01-21)


### Features

* **tools-plugin:** add --format option and improve fd patterns ([#119](https://github.com/laurigates/claude-plugins/issues/119)) ([06937a9](https://github.com/laurigates/claude-plugins/commit/06937a9402484d346bf67ca92b26c2782aab93de))

## [2.0.1](https://github.com/laurigates/claude-plugins/compare/tools-plugin-v2.0.0...tools-plugin-v2.0.1) (2026-01-09)


### Bug Fixes

* sync plugin.json versions to match release-please manifest ([1ac44e1](https://github.com/laurigates/claude-plugins/commit/1ac44e1240eed27eb3f829edaaac9bc863634d89))

## [2.0.1](https://github.com/laurigates/claude-plugins/compare/tools-plugin-v2.0.0...tools-plugin-v2.0.1) (2026-01-09)


### Bug Fixes

* sync plugin.json versions to match release-please manifest ([1ac44e1](https://github.com/laurigates/claude-plugins/commit/1ac44e1240eed27eb3f829edaaac9bc863634d89))

## [2.0.0](https://github.com/laurigates/claude-plugins/compare/tools-plugin-v1.1.0...tools-plugin-v2.0.0) (2025-12-28)


### ⚠ BREAKING CHANGES

* **agent-patterns-plugin:** Rename @HANDOFF to @AGENT-HANDOFF-MARKER

### Features

* add justfile support to configure and tools plugins ([781bebf](https://github.com/laurigates/claude-plugins/commit/781bebfab3673c02ea3c704048cd22b9923b0890))
* **tools-plugin:** add mermaid and d2 diagram skills ([687ee0c](https://github.com/laurigates/claude-plugins/commit/687ee0cbfe55946b2717db67bad06df053b0ca63))
* **tools-plugin:** add nushell-data-processing skill ([285f74f](https://github.com/laurigates/claude-plugins/commit/285f74fc50a3bda8b4b03bd26d465189835d1219))


### Code Refactoring

* **agent-patterns-plugin:** reorganize handoff markers system ([a0b06f8](https://github.com/laurigates/claude-plugins/commit/a0b06f85e3b3cb7a6ca7926d7940499a7460ef57))

## [1.1.0](https://github.com/laurigates/claude-plugins/compare/v1.0.0...v1.1.0) (2025-12-23)


### Features

* add justfile support to configure and tools plugins ([781bebf](https://github.com/laurigates/claude-plugins/commit/781bebfab3673c02ea3c704048cd22b9923b0890))
