# Changelog

## [3.13.1](https://github.com/laurigates/claude-plugins/compare/testing-plugin-v3.13.0...testing-plugin-v3.13.1) (2026-04-25)


### Documentation

* **testing-plugin:** standardise When to Use tables ([#1169](https://github.com/laurigates/claude-plugins/issues/1169)) ([fe9f03f](https://github.com/laurigates/claude-plugins/commit/fe9f03f23ddbba9ff23ff1f3d4ca5b7d8f6af0c7)), closes [#1156](https://github.com/laurigates/claude-plugins/issues/1156)

## [3.13.0](https://github.com/laurigates/claude-plugins/compare/testing-plugin-v3.12.2...testing-plugin-v3.13.0) (2026-04-19)


### Features

* make skills discoverable by Claude's auto-invocation ([#1090](https://github.com/laurigates/claude-plugins/issues/1090)) ([cded1da](https://github.com/laurigates/claude-plugins/commit/cded1da1ebaf350cba1285b58ecadbbaa0eb01f6))

## [3.12.2](https://github.com/laurigates/claude-plugins/compare/testing-plugin-v3.12.1...testing-plugin-v3.12.2) (2026-04-08)


### Bug Fixes

* **blueprint-plugin:** remove model field from skills and fix invocation syntax ([#1007](https://github.com/laurigates/claude-plugins/issues/1007)) ([42e1e5b](https://github.com/laurigates/claude-plugins/commit/42e1e5b6c73d43e5de4b27cdee16e316de44d4c0))

## [3.12.1](https://github.com/laurigates/claude-plugins/compare/testing-plugin-v3.12.0...testing-plugin-v3.12.1) (2026-03-25)


### Bug Fixes

* remove context: fork from all plugin skills to fix rate limit errors ([#981](https://github.com/laurigates/claude-plugins/issues/981)) ([56a90b1](https://github.com/laurigates/claude-plugins/commit/56a90b1464a9b1233a8bdb3d0716f1673bc70ad3))

## [3.12.0](https://github.com/laurigates/claude-plugins/compare/testing-plugin-v3.11.1...testing-plugin-v3.12.0) (2026-03-19)


### Features

* playwright CLI skill for token-efficient browser automation ([#963](https://github.com/laurigates/claude-plugins/issues/963)) ([73a9705](https://github.com/laurigates/claude-plugins/commit/73a970526524f8bacf28b406ae02938ce96f2ff7))

## [3.11.1](https://github.com/laurigates/claude-plugins/compare/testing-plugin-v3.11.0...testing-plugin-v3.11.1) (2026-03-10)


### Bug Fixes

* **skills:** use find -exec in context commands for missing file resilience ([#919](https://github.com/laurigates/claude-plugins/issues/919)) ([9520d25](https://github.com/laurigates/claude-plugins/commit/9520d250132a293833c3604ade47f5b547de28f1))

## [3.11.0](https://github.com/laurigates/claude-plugins/compare/testing-plugin-v3.10.1...testing-plugin-v3.11.0) (2026-03-09)


### Features

* **rules:** update rules for Claude Code 2.1.63-2.1.71 changes ([#917](https://github.com/laurigates/claude-plugins/issues/917)) ([20341e8](https://github.com/laurigates/claude-plugins/commit/20341e871fe7e91eb79d51aa02ad7bc9003a93e1))

## [3.10.1](https://github.com/laurigates/claude-plugins/compare/testing-plugin-v3.10.0...testing-plugin-v3.10.1) (2026-03-01)


### Bug Fixes

* replace test -f/-d with find in context commands ([#850](https://github.com/laurigates/claude-plugins/issues/850)) ([a236ac8](https://github.com/laurigates/claude-plugins/commit/a236ac80ab81ce37878268b2ad76f7ad6d4aa5fb))

## [3.10.0](https://github.com/laurigates/claude-plugins/compare/testing-plugin-v3.9.0...testing-plugin-v3.10.0) (2026-02-27)


### Features

* add `context: fork` guidance and apply to verbose skills ([#833](https://github.com/laurigates/claude-plugins/issues/833)) ([cced641](https://github.com/laurigates/claude-plugins/commit/cced641a953953b97f37528960782cacd75dbcab))
* **skills:** add context: fork to verbose autonomous skills ([cced641](https://github.com/laurigates/claude-plugins/commit/cced641a953953b97f37528960782cacd75dbcab))

## [3.9.0](https://github.com/laurigates/claude-plugins/compare/testing-plugin-v3.8.3...testing-plugin-v3.9.0) (2026-02-27)


### Features

* add metadata fields to skill definitions across all plugins ([#828](https://github.com/laurigates/claude-plugins/issues/828)) ([59b3d1f](https://github.com/laurigates/claude-plugins/commit/59b3d1fadd8fd888f95ced8b071fb66cf6f9c825))
* add skill invocation control via user-invocable and disable-model-invocation frontmatter ([59b3d1f](https://github.com/laurigates/claude-plugins/commit/59b3d1fadd8fd888f95ced8b071fb66cf6f9c825))

## [3.8.3](https://github.com/laurigates/claude-plugins/compare/testing-plugin-v3.8.2...testing-plugin-v3.8.3) (2026-02-26)


### Bug Fixes

* **scripts:** enhance context command linter with stderr safety checks and fix violations ([#819](https://github.com/laurigates/claude-plugins/issues/819)) ([2975b9b](https://github.com/laurigates/claude-plugins/commit/2975b9b0bf6698bdecf627e3d28bad06fde03cd1))

## [3.8.2](https://github.com/laurigates/claude-plugins/compare/testing-plugin-v3.8.1...testing-plugin-v3.8.2) (2026-02-25)


### Bug Fixes

* **skills:** add missing args field to 57 skills with argument-hint ([#812](https://github.com/laurigates/claude-plugins/issues/812)) ([f670423](https://github.com/laurigates/claude-plugins/commit/f670423777d3d0e4edf52a1594ad82efaa13793e)), closes [#805](https://github.com/laurigates/claude-plugins/issues/805)

## [3.8.1](https://github.com/laurigates/claude-plugins/compare/testing-plugin-v3.8.0...testing-plugin-v3.8.1) (2026-02-23)


### Bug Fixes

* remove 2&gt;/dev/null from context commands across all plugins ([#792](https://github.com/laurigates/claude-plugins/issues/792)) ([c72e67e](https://github.com/laurigates/claude-plugins/commit/c72e67ee37e809449f0e6282c48fac01363a59fd))

## [3.8.0](https://github.com/laurigates/claude-plugins/compare/testing-plugin-v3.7.0...testing-plugin-v3.8.0) (2026-02-18)


### Features

* introduce three-tier model palette (opus/sonnet/haiku) ([#709](https://github.com/laurigates/claude-plugins/issues/709)) ([2c1e9cc](https://github.com/laurigates/claude-plugins/commit/2c1e9ccff5d48c2b426beac5b3b38cd4576c79a0))

## [3.7.0](https://github.com/laurigates/claude-plugins/compare/testing-plugin-v3.6.1...testing-plugin-v3.7.0) (2026-02-16)


### Features

* **configure-plugin:** replace detect-secrets with gitleaks for secret scanning ([#668](https://github.com/laurigates/claude-plugins/issues/668)) ([3fc5bbc](https://github.com/laurigates/claude-plugins/commit/3fc5bbc2f8500f30160cc5dfeb5e3d1253ed0a54))

## [3.6.1](https://github.com/laurigates/claude-plugins/compare/testing-plugin-v3.6.0...testing-plugin-v3.6.1) (2026-02-14)


### Code Refactoring

* extract detailed content to REFERENCE.md files ([#605](https://github.com/laurigates/claude-plugins/issues/605)) ([7efbd83](https://github.com/laurigates/claude-plugins/commit/7efbd83b9a2b1ef67be702206396ba6d8102684d))

## [3.6.0](https://github.com/laurigates/claude-plugins/compare/testing-plugin-v3.5.3...testing-plugin-v3.6.0) (2026-02-13)


### Features

* add test-runner agent documentation ([#587](https://github.com/laurigates/claude-plugins/issues/587)) ([16b2721](https://github.com/laurigates/claude-plugins/commit/16b2721de3955f8bd597bb1f3b2ff84d7a0d2ae4))

## [3.5.3](https://github.com/laurigates/claude-plugins/compare/testing-plugin-v3.5.2...testing-plugin-v3.5.3) (2026-02-12)


### Bug Fixes

* standardize skill name fields to kebab-case across all plugins ([72c0f83](https://github.com/laurigates/claude-plugins/commit/72c0f837a1b07004850c5906a30d619a79098f69))

## [3.5.2](https://github.com/laurigates/claude-plugins/compare/testing-plugin-v3.5.1...testing-plugin-v3.5.2) (2026-02-09)


### Code Refactoring

* reframe negative guidance as positive guidance across skills ([7e755ee](https://github.com/laurigates/claude-plugins/commit/7e755ee1c32c39c124f3204a0d0a8d1d770e1573))

## [3.5.2](https://github.com/laurigates/claude-plugins/compare/testing-plugin-v3.5.1...testing-plugin-v3.5.2) (2026-02-08)


### Code Refactoring

* reframe negative guidance as positive guidance across skills ([7e755ee](https://github.com/laurigates/claude-plugins/commit/7e755ee1c32c39c124f3204a0d0a8d1d770e1573))

## [3.5.1](https://github.com/laurigates/claude-plugins/compare/testing-plugin-v3.5.0...testing-plugin-v3.5.1) (2026-02-08)


### Bug Fixes

* update skill review dates to trigger release sync ([#489](https://github.com/laurigates/claude-plugins/issues/489)) ([ca20d06](https://github.com/laurigates/claude-plugins/commit/ca20d0667baaa31dfa805c7dc775a1828c515223))

## [3.5.0](https://github.com/laurigates/claude-plugins/compare/testing-plugin-v3.4.0...testing-plugin-v3.5.0) (2026-02-05)


### Features

* add agentic optimizations and improve output formats ([3a7414c](https://github.com/laurigates/claude-plugins/commit/3a7414c82bbf1e2f6c507fdf16c6a2c57346b0fb))

## [3.4.0](https://github.com/laurigates/claude-plugins/compare/testing-plugin-v3.3.2...testing-plugin-v3.4.0) (2026-02-05)


### Features

* Add args and argument-hint parameters to commands ([6f7958e](https://github.com/laurigates/claude-plugins/commit/6f7958e78ba39b91e6d1e918935d58ae7ad376aa))


### Bug Fixes

* remove shell operators from context commands across all plugins ([#316](https://github.com/laurigates/claude-plugins/issues/316)) ([ecabe72](https://github.com/laurigates/claude-plugins/commit/ecabe72ebd100af1219f97012832d8ba500965b5))
* remove shell operators from context commands in multiple plugins ([#326](https://github.com/laurigates/claude-plugins/issues/326)) ([b028f73](https://github.com/laurigates/claude-plugins/commit/b028f7385f66f8f063a95874840c51e553694205))
* rename marketplace from 'lgates-claude-plugins' to 'laurigates-plugins' ([#195](https://github.com/laurigates/claude-plugins/issues/195)) ([4310935](https://github.com/laurigates/claude-plugins/commit/43109350d121f9c0749af86461daef9849eea133))
* replace ls -la with find in context commands to prevent false errors ([de8ce95](https://github.com/laurigates/claude-plugins/commit/de8ce954b4095b6c46e9326588b3fe632e87bffb))


### Code Refactoring

* **code-quality-plugin:** improve ast-grep skill discoverability and reduce size ([#189](https://github.com/laurigates/claude-plugins/issues/189)) ([11f6fa5](https://github.com/laurigates/claude-plugins/commit/11f6fa561c3a57204fb4388a04ecd8f3ffc19f5b))


### Documentation

* **rules, settings:** refactor to emphasize positive guidance patterns ([#360](https://github.com/laurigates/claude-plugins/issues/360)) ([a4ea8a8](https://github.com/laurigates/claude-plugins/commit/a4ea8a8990e2a40bb2331855db5fd68631c14d7e))

## [3.3.2](https://github.com/laurigates/claude-plugins/compare/testing-plugin-v3.3.1...testing-plugin-v3.3.2) (2026-02-05)


### Bug Fixes

* replace ls -la with find in context commands to prevent false errors ([de8ce95](https://github.com/laurigates/claude-plugins/commit/de8ce954b4095b6c46e9326588b3fe632e87bffb))

## [3.3.2](https://github.com/laurigates/claude-plugins/compare/testing-plugin-v3.3.1...testing-plugin-v3.3.2) (2026-02-05)


### Bug Fixes

* replace ls -la with find in context commands to prevent false errors ([de8ce95](https://github.com/laurigates/claude-plugins/commit/de8ce954b4095b6c46e9326588b3fe632e87bffb))

## [3.3.1](https://github.com/laurigates/claude-plugins/compare/testing-plugin-v3.3.0...testing-plugin-v3.3.1) (2026-02-04)


### Documentation

* **rules, settings:** refactor to emphasize positive guidance patterns ([#360](https://github.com/laurigates/claude-plugins/issues/360)) ([a4ea8a8](https://github.com/laurigates/claude-plugins/commit/a4ea8a8990e2a40bb2331855db5fd68631c14d7e))

## [3.3.0](https://github.com/laurigates/claude-plugins/compare/testing-plugin-v3.2.4...testing-plugin-v3.3.0) (2026-02-03)


### Features

* Add args and argument-hint parameters to commands ([6f7958e](https://github.com/laurigates/claude-plugins/commit/6f7958e78ba39b91e6d1e918935d58ae7ad376aa))

## [3.2.4](https://github.com/laurigates/claude-plugins/compare/testing-plugin-v3.2.3...testing-plugin-v3.2.4) (2026-02-03)


### Bug Fixes

* remove shell operators from context commands in multiple plugins ([#326](https://github.com/laurigates/claude-plugins/issues/326)) ([b028f73](https://github.com/laurigates/claude-plugins/commit/b028f7385f66f8f063a95874840c51e553694205))

## [3.2.3](https://github.com/laurigates/claude-plugins/compare/testing-plugin-v3.2.2...testing-plugin-v3.2.3) (2026-02-03)


### Bug Fixes

* remove shell operators from context commands across all plugins ([#316](https://github.com/laurigates/claude-plugins/issues/316)) ([ecabe72](https://github.com/laurigates/claude-plugins/commit/ecabe72ebd100af1219f97012832d8ba500965b5))

## [3.2.2](https://github.com/laurigates/claude-plugins/compare/testing-plugin-v3.2.1...testing-plugin-v3.2.2) (2026-01-25)


### Bug Fixes

* rename marketplace from 'lgates-claude-plugins' to 'laurigates-plugins' ([#195](https://github.com/laurigates/claude-plugins/issues/195)) ([4310935](https://github.com/laurigates/claude-plugins/commit/43109350d121f9c0749af86461daef9849eea133))

## [3.2.1](https://github.com/laurigates/claude-plugins/compare/testing-plugin-v3.2.0...testing-plugin-v3.2.1) (2026-01-24)


### Code Refactoring

* **code-quality-plugin:** improve ast-grep skill discoverability and reduce size ([#189](https://github.com/laurigates/claude-plugins/issues/189)) ([11f6fa5](https://github.com/laurigates/claude-plugins/commit/11f6fa561c3a57204fb4388a04ecd8f3ffc19f5b))

## [3.2.0](https://github.com/laurigates/claude-plugins/compare/testing-plugin-v3.1.0...testing-plugin-v3.2.0) (2026-01-23)


### Features

* add model specification to all skills and commands ([#131](https://github.com/laurigates/claude-plugins/issues/131)) ([81f2961](https://github.com/laurigates/claude-plugins/commit/81f296155b50864b8b1687b9eb18a9c2cbb08791))

## [3.1.0](https://github.com/laurigates/claude-plugins/compare/testing-plugin-v3.0.1...testing-plugin-v3.1.0) (2026-01-20)


### Features

* **testing-plugin:** add test:focus command for fail-fast single file testing ([#108](https://github.com/laurigates/claude-plugins/issues/108)) ([d57b07b](https://github.com/laurigates/claude-plugins/commit/d57b07bb249395fb99cae67be971672ef3c59a3b))

## [3.0.1](https://github.com/laurigates/claude-plugins/compare/testing-plugin-v3.0.0...testing-plugin-v3.0.1) (2026-01-09)


### Bug Fixes

* sync plugin.json versions to match release-please manifest ([1ac44e1](https://github.com/laurigates/claude-plugins/commit/1ac44e1240eed27eb3f829edaaac9bc863634d89))

## [3.0.0](https://github.com/laurigates/claude-plugins/compare/testing-plugin-v2.0.0...testing-plugin-v3.0.0) (2025-12-28)


### ⚠ BREAKING CHANGES

* **agent-patterns-plugin:** Rename @HANDOFF to @AGENT-HANDOFF-MARKER

### Code Refactoring

* **agent-patterns-plugin:** reorganize handoff markers system ([a0b06f8](https://github.com/laurigates/claude-plugins/commit/a0b06f85e3b3cb7a6ca7926d7940499a7460ef57))

## [2.0.0](https://github.com/laurigates/claude-plugins/compare/v1.0.0...v2.0.0) (2025-12-27)


### ⚠ BREAKING CHANGES

* **agent-patterns-plugin:** Rename @HANDOFF to @AGENT-HANDOFF-MARKER

### Code Refactoring

* **agent-patterns-plugin:** reorganize handoff markers system ([a0b06f8](https://github.com/laurigates/claude-plugins/commit/a0b06f85e3b3cb7a6ca7926d7940499a7460ef57))
