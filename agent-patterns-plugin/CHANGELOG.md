# Changelog

## [2.11.0](https://github.com/laurigates/claude-plugins/compare/agent-patterns-plugin-v2.10.0...agent-patterns-plugin-v2.11.0) (2026-03-08)


### Features

* **agent-patterns-plugin:** add plugin-settings skill ([#897](https://github.com/laurigates/claude-plugins/issues/897)) ([c42e574](https://github.com/laurigates/claude-plugins/commit/c42e574b8f525b79bdd15ceb3fb2b1d75a1e347e))

## [2.10.0](https://github.com/laurigates/claude-plugins/compare/agent-patterns-plugin-v2.9.0...agent-patterns-plugin-v2.10.0) (2026-03-05)


### Features

* standardize shell script conventions and add linting ([#892](https://github.com/laurigates/claude-plugins/issues/892)) ([0eba700](https://github.com/laurigates/claude-plugins/commit/0eba7009728418bdef6355bd91fc9ee50c6982a8))

## [2.9.0](https://github.com/laurigates/claude-plugins/compare/agent-patterns-plugin-v2.8.1...agent-patterns-plugin-v2.9.0) (2026-03-03)


### Features

* **agent-patterns-plugin:** add agent-teams skill ([#868](https://github.com/laurigates/claude-plugins/issues/868)) ([9af253e](https://github.com/laurigates/claude-plugins/commit/9af253e36f189a0f9550cfa5f19e38f9435d27cd)), closes [#860](https://github.com/laurigates/claude-plugins/issues/860)

## [2.8.1](https://github.com/laurigates/claude-plugins/compare/agent-patterns-plugin-v2.8.0...agent-patterns-plugin-v2.8.1) (2026-03-02)


### Documentation

* **rules:** update rules and skills for Claude Code 2.1.50-2.1.63 ([#859](https://github.com/laurigates/claude-plugins/issues/859)) ([6c66021](https://github.com/laurigates/claude-plugins/commit/6c66021fefa205abfc4f575229e3bbb9cdc6263a))

## [2.8.0](https://github.com/laurigates/claude-plugins/compare/agent-patterns-plugin-v2.7.2...agent-patterns-plugin-v2.8.0) (2026-02-27)


### Features

* add metadata fields to skill definitions across all plugins ([#828](https://github.com/laurigates/claude-plugins/issues/828)) ([59b3d1f](https://github.com/laurigates/claude-plugins/commit/59b3d1fadd8fd888f95ced8b071fb66cf6f9c825))
* add skill invocation control via user-invocable and disable-model-invocation frontmatter ([59b3d1f](https://github.com/laurigates/claude-plugins/commit/59b3d1fadd8fd888f95ced8b071fb66cf6f9c825))

## [2.7.2](https://github.com/laurigates/claude-plugins/compare/agent-patterns-plugin-v2.7.1...agent-patterns-plugin-v2.7.2) (2026-02-26)


### Documentation

* **hooks-plugin:** document Claude Code 2.1.50 hook system enhancements ([#813](https://github.com/laurigates/claude-plugins/issues/813)) ([92f1b1d](https://github.com/laurigates/claude-plugins/commit/92f1b1dda1ba03918f283f9961c7a161dd3fdf70)), closes [#798](https://github.com/laurigates/claude-plugins/issues/798)

## [2.7.1](https://github.com/laurigates/claude-plugins/compare/agent-patterns-plugin-v2.7.0...agent-patterns-plugin-v2.7.1) (2026-02-25)


### Bug Fixes

* **skills:** add missing args field to 57 skills with argument-hint ([#812](https://github.com/laurigates/claude-plugins/issues/812)) ([f670423](https://github.com/laurigates/claude-plugins/commit/f670423777d3d0e4edf52a1594ad82efaa13793e)), closes [#805](https://github.com/laurigates/claude-plugins/issues/805)

## [2.7.0](https://github.com/laurigates/claude-plugins/compare/agent-patterns-plugin-v2.6.2...agent-patterns-plugin-v2.7.0) (2026-02-18)


### Features

* introduce three-tier model palette (opus/sonnet/haiku) ([#709](https://github.com/laurigates/claude-plugins/issues/709)) ([2c1e9cc](https://github.com/laurigates/claude-plugins/commit/2c1e9ccff5d48c2b426beac5b3b38cd4576c79a0))

## [2.6.2](https://github.com/laurigates/claude-plugins/compare/agent-patterns-plugin-v2.6.1...agent-patterns-plugin-v2.6.2) (2026-02-15)


### Bug Fixes

* **agent-patterns-plugin:** use systemMessage for PreCompact hook output ([c887829](https://github.com/laurigates/claude-plugins/commit/c887829f229fdb60e54763f32b56cabf07890b58))
* refactor pre-compact primer hook output format to systemMessage ([#641](https://github.com/laurigates/claude-plugins/issues/641)) ([c887829](https://github.com/laurigates/claude-plugins/commit/c887829f229fdb60e54763f32b56cabf07890b58))

## [2.6.1](https://github.com/laurigates/claude-plugins/compare/agent-patterns-plugin-v2.6.0...agent-patterns-plugin-v2.6.1) (2026-02-12)


### Bug Fixes

* standardize skill name fields to kebab-case across all plugins ([72c0f83](https://github.com/laurigates/claude-plugins/commit/72c0f837a1b07004850c5906a30d619a79098f69))

## [2.6.0](https://github.com/laurigates/claude-plugins/compare/agent-patterns-plugin-v2.5.6...agent-patterns-plugin-v2.6.0) (2026-02-11)


### Features

* add required quality sections to refactored skills ([#544](https://github.com/laurigates/claude-plugins/issues/544)) ([342af54](https://github.com/laurigates/claude-plugins/commit/342af54af0f81fa50d239d06b32b353ddb7335fc))

## [2.5.6](https://github.com/laurigates/claude-plugins/compare/agent-patterns-plugin-v2.5.5...agent-patterns-plugin-v2.5.6) (2026-02-08)


### Bug Fixes

* update skill review dates to trigger release sync ([#489](https://github.com/laurigates/claude-plugins/issues/489)) ([ca20d06](https://github.com/laurigates/claude-plugins/commit/ca20d0667baaa31dfa805c7dc775a1828c515223))

## [2.5.5](https://github.com/laurigates/claude-plugins/compare/agent-patterns-plugin-v2.5.4...agent-patterns-plugin-v2.5.5) (2026-02-06)


### Bug Fixes

* **frontmatter:** resolve 83 validation errors across 75 files ([#434](https://github.com/laurigates/claude-plugins/issues/434)) ([5beb75e](https://github.com/laurigates/claude-plugins/commit/5beb75ed4b2cb0431d060bd7102903495c03c6c5))

## [2.5.5](https://github.com/laurigates/claude-plugins/compare/agent-patterns-plugin-v2.5.4...agent-patterns-plugin-v2.5.5) (2026-02-06)


### Bug Fixes

* **frontmatter:** resolve 83 validation errors across 75 files ([#434](https://github.com/laurigates/claude-plugins/issues/434)) ([5beb75e](https://github.com/laurigates/claude-plugins/commit/5beb75ed4b2cb0431d060bd7102903495c03c6c5))

## [2.5.4](https://github.com/laurigates/claude-plugins/compare/agent-patterns-plugin-v2.5.3...agent-patterns-plugin-v2.5.4) (2026-02-03)


### Bug Fixes

* remove shell operators from context commands in multiple plugins ([#326](https://github.com/laurigates/claude-plugins/issues/326)) ([b028f73](https://github.com/laurigates/claude-plugins/commit/b028f7385f66f8f063a95874840c51e553694205))

## [2.5.3](https://github.com/laurigates/claude-plugins/compare/agent-patterns-plugin-v2.5.2...agent-patterns-plugin-v2.5.3) (2026-02-02)


### Bug Fixes

* **agent-patterns-plugin:** block git writes for parallel agents to prevent conflicts ([#299](https://github.com/laurigates/claude-plugins/issues/299)) ([a2c2ce0](https://github.com/laurigates/claude-plugins/commit/a2c2ce07d67ead9b30470b398777be355672281b))

## [2.5.2](https://github.com/laurigates/claude-plugins/compare/agent-patterns-plugin-v2.5.1...agent-patterns-plugin-v2.5.2) (2026-02-01)


### Bug Fixes

* **agent-patterns-plugin:** make orchestrator enforcement opt-in instead of opt-out ([f607b7c](https://github.com/laurigates/claude-plugins/commit/f607b7c8141f6d11bef906f5f11b434284083677))

## [2.5.1](https://github.com/laurigates/claude-plugins/compare/agent-patterns-plugin-v2.5.0...agent-patterns-plugin-v2.5.1) (2026-02-01)


### Bug Fixes

* enforce granular Bash permissions across all plugins ([#267](https://github.com/laurigates/claude-plugins/issues/267)) ([afeb507](https://github.com/laurigates/claude-plugins/commit/afeb50754838c2923807c8f2a248b3798fd4281c))

## [2.5.0](https://github.com/laurigates/claude-plugins/compare/agent-patterns-plugin-v2.4.0...agent-patterns-plugin-v2.5.0) (2026-01-26)


### Features

* **agent-patterns-plugin:** add agentic-patterns.com as source skill ([#229](https://github.com/laurigates/claude-plugins/issues/229)) ([cbac971](https://github.com/laurigates/claude-plugins/commit/cbac97130222c63afb11dd3f7e2b90f057734fc3))

## [2.4.0](https://github.com/laurigates/claude-plugins/compare/agent-patterns-plugin-v2.3.0...agent-patterns-plugin-v2.4.0) (2026-01-23)


### Features

* add model specification to all skills and commands ([#131](https://github.com/laurigates/claude-plugins/issues/131)) ([81f2961](https://github.com/laurigates/claude-plugins/commit/81f296155b50864b8b1687b9eb18a9c2cbb08791))

## [2.3.0](https://github.com/laurigates/claude-plugins/compare/agent-patterns-plugin-v2.2.0...agent-patterns-plugin-v2.3.0) (2026-01-21)


### Features

* **agent-patterns-plugin:** add delegation-first skill for automatic task delegation ([76bb2ce](https://github.com/laurigates/claude-plugins/commit/76bb2ce4d5ea444183908c75db18979ce2851acf))

## [2.2.0](https://github.com/laurigates/claude-plugins/compare/agent-patterns-plugin-v2.1.0...agent-patterns-plugin-v2.2.0) (2026-01-20)


### Features

* implement Claude Code 2.1.7 changelog review updates (issue [#78](https://github.com/laurigates/claude-plugins/issues/78)) ([#112](https://github.com/laurigates/claude-plugins/issues/112)) ([e28d8de](https://github.com/laurigates/claude-plugins/commit/e28d8deec41d3e5070861a3f1c37e9c43f452cb4))

## [2.1.0](https://github.com/laurigates/claude-plugins/compare/agent-patterns-plugin-v2.0.1...agent-patterns-plugin-v2.1.0) (2026-01-15)


### Features

* **agent-patterns-plugin:** add claude-hooks-configuration skill ([#70](https://github.com/laurigates/claude-plugins/issues/70)) ([d97307a](https://github.com/laurigates/claude-plugins/commit/d97307ac33773792ee9e702916abefa87d2ffc7d))

## [2.0.1](https://github.com/laurigates/claude-plugins/compare/agent-patterns-plugin-v2.0.0...agent-patterns-plugin-v2.0.1) (2026-01-09)


### Bug Fixes

* sync plugin.json versions to match release-please manifest ([1ac44e1](https://github.com/laurigates/claude-plugins/commit/1ac44e1240eed27eb3f829edaaac9bc863634d89))

## [2.0.1](https://github.com/laurigates/claude-plugins/compare/agent-patterns-plugin-v2.0.0...agent-patterns-plugin-v2.0.1) (2026-01-09)


### Bug Fixes

* sync plugin.json versions to match release-please manifest ([1ac44e1](https://github.com/laurigates/claude-plugins/commit/1ac44e1240eed27eb3f829edaaac9bc863634d89))

## [2.0.0](https://github.com/laurigates/claude-plugins/compare/agent-patterns-plugin-v1.0.0...agent-patterns-plugin-v2.0.0) (2025-12-28)


### ⚠ BREAKING CHANGES

* **agent-patterns-plugin:** Rename @HANDOFF to @AGENT-HANDOFF-MARKER

### Code Refactoring

* **agent-patterns-plugin:** reorganize handoff markers system ([a0b06f8](https://github.com/laurigates/claude-plugins/commit/a0b06f85e3b3cb7a6ca7926d7940499a7460ef57))
