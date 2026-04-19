# Changelog

## [1.13.0](https://github.com/laurigates/claude-plugins/compare/code-quality-plugin-v1.12.0...code-quality-plugin-v1.13.0) (2026-04-19)


### Features

* make skills discoverable by Claude's auto-invocation ([#1090](https://github.com/laurigates/claude-plugins/issues/1090)) ([cded1da](https://github.com/laurigates/claude-plugins/commit/cded1da1ebaf350cba1285b58ecadbbaa0eb01f6))

## [1.12.0](https://github.com/laurigates/claude-plugins/compare/code-quality-plugin-v1.11.2...code-quality-plugin-v1.12.0) (2026-04-14)


### Features

* /code:error-swallowing skill for detecting syntactic error suppression ([#1030](https://github.com/laurigates/claude-plugins/issues/1030)) ([186e062](https://github.com/laurigates/claude-plugins/commit/186e062e25bb8df4264b438899bdfcbbaf7670e6))

## [1.11.2](https://github.com/laurigates/claude-plugins/compare/code-quality-plugin-v1.11.1...code-quality-plugin-v1.11.2) (2026-04-08)


### Bug Fixes

* **blueprint-plugin:** remove model field from skills and fix invocation syntax ([#1007](https://github.com/laurigates/claude-plugins/issues/1007)) ([42e1e5b](https://github.com/laurigates/claude-plugins/commit/42e1e5b6c73d43e5de4b27cdee16e316de44d4c0))

## [1.11.1](https://github.com/laurigates/claude-plugins/compare/code-quality-plugin-v1.11.0...code-quality-plugin-v1.11.1) (2026-03-25)


### Bug Fixes

* remove context: fork from all plugin skills to fix rate limit errors ([#981](https://github.com/laurigates/claude-plugins/issues/981)) ([56a90b1](https://github.com/laurigates/claude-plugins/commit/56a90b1464a9b1233a8bdb3d0716f1673bc70ad3))

## [1.11.0](https://github.com/laurigates/claude-plugins/compare/code-quality-plugin-v1.10.1...code-quality-plugin-v1.11.0) (2026-03-09)


### Features

* **rules:** update rules for Claude Code 2.1.63-2.1.71 changes ([#917](https://github.com/laurigates/claude-plugins/issues/917)) ([20341e8](https://github.com/laurigates/claude-plugins/commit/20341e871fe7e91eb79d51aa02ad7bc9003a93e1))

## [1.10.1](https://github.com/laurigates/claude-plugins/compare/code-quality-plugin-v1.10.0...code-quality-plugin-v1.10.1) (2026-03-01)


### Bug Fixes

* replace test -f/-d with find in context commands ([#850](https://github.com/laurigates/claude-plugins/issues/850)) ([a236ac8](https://github.com/laurigates/claude-plugins/commit/a236ac80ab81ce37878268b2ad76f7ad6d4aa5fb))

## [1.10.0](https://github.com/laurigates/claude-plugins/compare/code-quality-plugin-v1.9.0...code-quality-plugin-v1.10.0) (2026-02-27)


### Features

* add `context: fork` guidance and apply to verbose skills ([#833](https://github.com/laurigates/claude-plugins/issues/833)) ([cced641](https://github.com/laurigates/claude-plugins/commit/cced641a953953b97f37528960782cacd75dbcab))
* **skills:** add context: fork to verbose autonomous skills ([cced641](https://github.com/laurigates/claude-plugins/commit/cced641a953953b97f37528960782cacd75dbcab))

## [1.9.0](https://github.com/laurigates/claude-plugins/compare/code-quality-plugin-v1.8.1...code-quality-plugin-v1.9.0) (2026-02-27)


### Features

* add metadata fields to skill definitions across all plugins ([#828](https://github.com/laurigates/claude-plugins/issues/828)) ([59b3d1f](https://github.com/laurigates/claude-plugins/commit/59b3d1fadd8fd888f95ced8b071fb66cf6f9c825))
* add skill invocation control via user-invocable and disable-model-invocation frontmatter ([59b3d1f](https://github.com/laurigates/claude-plugins/commit/59b3d1fadd8fd888f95ced8b071fb66cf6f9c825))

## [1.8.1](https://github.com/laurigates/claude-plugins/compare/code-quality-plugin-v1.8.0...code-quality-plugin-v1.8.1) (2026-02-26)


### Bug Fixes

* **scripts:** enhance context command linter with stderr safety checks and fix violations ([#819](https://github.com/laurigates/claude-plugins/issues/819)) ([2975b9b](https://github.com/laurigates/claude-plugins/commit/2975b9b0bf6698bdecf627e3d28bad06fde03cd1))

## [1.8.0](https://github.com/laurigates/claude-plugins/compare/code-quality-plugin-v1.7.2...code-quality-plugin-v1.8.0) (2026-02-25)


### Features

* **python-plugin:** replace mypy with ty for type checking ([96a1aaa](https://github.com/laurigates/claude-plugins/commit/96a1aaa9c5f7e07725c72ce0a6f99f7fbf222d57))
* refocus code-refactor skill on functional programming principles ([#807](https://github.com/laurigates/claude-plugins/issues/807)) ([a9fa79b](https://github.com/laurigates/claude-plugins/commit/a9fa79b16aac2ecf014e8f74d5cbafaeb9df9f0f))
* replace mypy with ty for Python type checking ([#808](https://github.com/laurigates/claude-plugins/issues/808)) ([96a1aaa](https://github.com/laurigates/claude-plugins/commit/96a1aaa9c5f7e07725c72ce0a6f99f7fbf222d57))


### Code Refactoring

* **code-quality-plugin:** replace /refactor with FP-oriented /code:refactor ([a9fa79b](https://github.com/laurigates/claude-plugins/commit/a9fa79b16aac2ecf014e8f74d5cbafaeb9df9f0f))

## [1.7.2](https://github.com/laurigates/claude-plugins/compare/code-quality-plugin-v1.7.1...code-quality-plugin-v1.7.2) (2026-02-23)


### Bug Fixes

* remove 2&gt;/dev/null from context commands across all plugins ([#792](https://github.com/laurigates/claude-plugins/issues/792)) ([c72e67e](https://github.com/laurigates/claude-plugins/commit/c72e67ee37e809449f0e6282c48fac01363a59fd))

## [1.7.1](https://github.com/laurigates/claude-plugins/compare/code-quality-plugin-v1.7.0...code-quality-plugin-v1.7.1) (2026-02-23)


### Bug Fixes

* **project-plugin:** remove shell operators from context commands ([#790](https://github.com/laurigates/claude-plugins/issues/790)) ([99769b5](https://github.com/laurigates/claude-plugins/commit/99769b57f7c373a6cc280571561b06dd9f1a54ef))

## [1.7.0](https://github.com/laurigates/claude-plugins/compare/code-quality-plugin-v1.6.1...code-quality-plugin-v1.7.0) (2026-02-22)


### Features

* **code-quality-plugin:** add silent degradation detection skill ([#785](https://github.com/laurigates/claude-plugins/issues/785)) ([49d7cb1](https://github.com/laurigates/claude-plugins/commit/49d7cb15c2befe59d434619a306651deaf927311))

## [1.6.1](https://github.com/laurigates/claude-plugins/compare/code-quality-plugin-v1.6.0...code-quality-plugin-v1.6.1) (2026-02-20)


### Code Refactoring

* consolidate skill documentation and remove reference files ([#758](https://github.com/laurigates/claude-plugins/issues/758)) ([3d1e8cc](https://github.com/laurigates/claude-plugins/commit/3d1e8ccd9becba5faec5b1df1fa06f410eca7437))

## [1.6.0](https://github.com/laurigates/claude-plugins/compare/code-quality-plugin-v1.5.6...code-quality-plugin-v1.6.0) (2026-02-18)


### Features

* introduce three-tier model palette (opus/sonnet/haiku) ([#709](https://github.com/laurigates/claude-plugins/issues/709)) ([2c1e9cc](https://github.com/laurigates/claude-plugins/commit/2c1e9ccff5d48c2b426beac5b3b38cd4576c79a0))

## [1.5.6](https://github.com/laurigates/claude-plugins/compare/code-quality-plugin-v1.5.5...code-quality-plugin-v1.5.6) (2026-02-15)


### Bug Fixes

* remove pipe/ls operators from context commands and add CI linting ([#653](https://github.com/laurigates/claude-plugins/issues/653)) ([7a01eef](https://github.com/laurigates/claude-plugins/commit/7a01eef21495ed6243277fbaa88082b7ecabc793))

## [1.5.5](https://github.com/laurigates/claude-plugins/compare/code-quality-plugin-v1.5.4...code-quality-plugin-v1.5.5) (2026-02-14)


### Code Refactoring

* extract detailed content to REFERENCE.md files ([#605](https://github.com/laurigates/claude-plugins/issues/605)) ([7efbd83](https://github.com/laurigates/claude-plugins/commit/7efbd83b9a2b1ef67be702206396ba6d8102684d))

## [1.5.4](https://github.com/laurigates/claude-plugins/compare/code-quality-plugin-v1.5.3...code-quality-plugin-v1.5.4) (2026-02-12)


### Bug Fixes

* standardize skill name fields to kebab-case across all plugins ([72c0f83](https://github.com/laurigates/claude-plugins/commit/72c0f837a1b07004850c5906a30d619a79098f69))

## [1.5.3](https://github.com/laurigates/claude-plugins/compare/code-quality-plugin-v1.5.2...code-quality-plugin-v1.5.3) (2026-02-08)


### Code Refactoring

* reframe negative guidance as positive guidance across skills ([7e755ee](https://github.com/laurigates/claude-plugins/commit/7e755ee1c32c39c124f3204a0d0a8d1d770e1573))

## [1.5.2](https://github.com/laurigates/claude-plugins/compare/code-quality-plugin-v1.5.1...code-quality-plugin-v1.5.2) (2026-02-08)


### Bug Fixes

* update skill review dates to trigger release sync ([#489](https://github.com/laurigates/claude-plugins/issues/489)) ([ca20d06](https://github.com/laurigates/claude-plugins/commit/ca20d0667baaa31dfa805c7dc775a1828c515223))

## [1.5.1](https://github.com/laurigates/claude-plugins/compare/code-quality-plugin-v1.5.0...code-quality-plugin-v1.5.1) (2026-02-06)


### Bug Fixes

* **frontmatter:** resolve 83 validation errors across 75 files ([#434](https://github.com/laurigates/claude-plugins/issues/434)) ([5beb75e](https://github.com/laurigates/claude-plugins/commit/5beb75ed4b2cb0431d060bd7102903495c03c6c5))

## [1.5.0](https://github.com/laurigates/claude-plugins/compare/code-quality-plugin-v1.4.0...code-quality-plugin-v1.5.0) (2026-02-06)


### Features

* **code-quality-plugin:** add dry-consolidation skill ([47f7218](https://github.com/laurigates/claude-plugins/commit/47f7218ae70a59ca24a0523461df5e94620194d8))

## [1.4.0](https://github.com/laurigates/claude-plugins/compare/code-quality-plugin-v1.3.7...code-quality-plugin-v1.4.0) (2026-02-05)


### Features

* add agentic optimizations and improve output formats ([3a7414c](https://github.com/laurigates/claude-plugins/commit/3a7414c82bbf1e2f6c507fdf16c6a2c57346b0fb))

## [1.3.7](https://github.com/laurigates/claude-plugins/compare/code-quality-plugin-v1.3.6...code-quality-plugin-v1.3.7) (2026-02-04)


### Bug Fixes

* **code-quality-plugin:** handle missing argument in refactor command ([c627bdb](https://github.com/laurigates/claude-plugins/commit/c627bdb774f3afb6d9120195813f47104eaa0ba0))

## [1.3.6](https://github.com/laurigates/claude-plugins/compare/code-quality-plugin-v1.3.5...code-quality-plugin-v1.3.6) (2026-02-04)


### Bug Fixes

* **code-quality-plugin:** handle missing argument in refactor command ([c627bdb](https://github.com/laurigates/claude-plugins/commit/c627bdb774f3afb6d9120195813f47104eaa0ba0))


### Documentation

* **rules, settings:** refactor to emphasize positive guidance patterns ([#360](https://github.com/laurigates/claude-plugins/issues/360)) ([a4ea8a8](https://github.com/laurigates/claude-plugins/commit/a4ea8a8990e2a40bb2331855db5fd68631c14d7e))

## [1.3.6](https://github.com/laurigates/claude-plugins/compare/code-quality-plugin-v1.3.5...code-quality-plugin-v1.3.6) (2026-02-04)


### Documentation

* **rules, settings:** refactor to emphasize positive guidance patterns ([#360](https://github.com/laurigates/claude-plugins/issues/360)) ([a4ea8a8](https://github.com/laurigates/claude-plugins/commit/a4ea8a8990e2a40bb2331855db5fd68631c14d7e))

## [1.3.5](https://github.com/laurigates/claude-plugins/compare/code-quality-plugin-v1.3.4...code-quality-plugin-v1.3.5) (2026-02-03)


### Bug Fixes

* **code-quality-plugin:** remove parameter substitution from context commands ([5171301](https://github.com/laurigates/claude-plugins/commit/5171301b8ee6168cc7241509057efa37fa709c9d))

## [1.3.4](https://github.com/laurigates/claude-plugins/compare/code-quality-plugin-v1.3.3...code-quality-plugin-v1.3.4) (2026-02-03)


### Bug Fixes

* remove shell operators from context commands in multiple plugins ([#326](https://github.com/laurigates/claude-plugins/issues/326)) ([b028f73](https://github.com/laurigates/claude-plugins/commit/b028f7385f66f8f063a95874840c51e553694205))

## [1.3.3](https://github.com/laurigates/claude-plugins/compare/code-quality-plugin-v1.3.2...code-quality-plugin-v1.3.3) (2026-02-03)


### Bug Fixes

* remove shell operators from context commands across all plugins ([#316](https://github.com/laurigates/claude-plugins/issues/316)) ([ecabe72](https://github.com/laurigates/claude-plugins/commit/ecabe72ebd100af1219f97012832d8ba500965b5))

## [1.3.2](https://github.com/laurigates/claude-plugins/compare/code-quality-plugin-v1.3.1...code-quality-plugin-v1.3.2) (2026-02-01)


### Bug Fixes

* enforce granular Bash permissions across all plugins ([#267](https://github.com/laurigates/claude-plugins/issues/267)) ([afeb507](https://github.com/laurigates/claude-plugins/commit/afeb50754838c2923807c8f2a248b3798fd4281c))

## [1.3.1](https://github.com/laurigates/claude-plugins/compare/code-quality-plugin-v1.3.0...code-quality-plugin-v1.3.1) (2026-01-25)


### Bug Fixes

* resolve claude-code-review workflow permission denials ([08b034c](https://github.com/laurigates/claude-plugins/commit/08b034c817430787e63d79234a92c622c415182f))

## [1.3.0](https://github.com/laurigates/claude-plugins/compare/code-quality-plugin-v1.2.1...code-quality-plugin-v1.3.0) (2026-01-25)


### Features

* **git-plugin,code-quality-plugin,project-plugin:** add supporting scripts to skills ([#206](https://github.com/laurigates/claude-plugins/issues/206)) ([0b33d50](https://github.com/laurigates/claude-plugins/commit/0b33d502e18584b264c7c4a99dddda54dc573d08))

## [1.2.1](https://github.com/laurigates/claude-plugins/compare/code-quality-plugin-v1.2.0...code-quality-plugin-v1.2.1) (2026-01-24)


### Bug Fixes

* rename marketplace from 'lgates-claude-plugins' to 'laurigates-plugins' ([#195](https://github.com/laurigates/claude-plugins/issues/195)) ([4310935](https://github.com/laurigates/claude-plugins/commit/43109350d121f9c0749af86461daef9849eea133))


### Code Refactoring

* **code-quality-plugin:** improve ast-grep skill discoverability and reduce size ([#189](https://github.com/laurigates/claude-plugins/issues/189)) ([11f6fa5](https://github.com/laurigates/claude-plugins/commit/11f6fa561c3a57204fb4388a04ecd8f3ffc19f5b))

## [1.2.0](https://github.com/laurigates/claude-plugins/compare/code-quality-plugin-v1.1.0...code-quality-plugin-v1.2.0) (2026-01-23)


### Features

* add model specification to all skills and commands ([#131](https://github.com/laurigates/claude-plugins/issues/131)) ([81f2961](https://github.com/laurigates/claude-plugins/commit/81f296155b50864b8b1687b9eb18a9c2cbb08791))

## [1.1.0](https://github.com/laurigates/claude-plugins/compare/code-quality-plugin-v1.0.0...code-quality-plugin-v1.1.0) (2026-01-09)


### Features

* **code-quality-plugin:** add documentation quality check command and skill ([#53](https://github.com/laurigates/claude-plugins/issues/53)) ([db5893b](https://github.com/laurigates/claude-plugins/commit/db5893baaa267168cc0343a84fd6a2557ad47327))
