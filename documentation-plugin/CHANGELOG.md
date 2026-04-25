# Changelog

## [1.8.1](https://github.com/laurigates/claude-plugins/compare/documentation-plugin-v1.8.0...documentation-plugin-v1.8.1) (2026-04-25)


### Documentation

* **documentation-plugin:** standardise When to Use tables ([#1187](https://github.com/laurigates/claude-plugins/issues/1187)) ([d4ad41c](https://github.com/laurigates/claude-plugins/commit/d4ad41cef796a0046480d98a85b1a13a90ac6f3a)), closes [#1156](https://github.com/laurigates/claude-plugins/issues/1156)

## [1.8.0](https://github.com/laurigates/claude-plugins/compare/documentation-plugin-v1.7.2...documentation-plugin-v1.8.0) (2026-04-19)


### Features

* make skills discoverable by Claude's auto-invocation ([#1090](https://github.com/laurigates/claude-plugins/issues/1090)) ([cded1da](https://github.com/laurigates/claude-plugins/commit/cded1da1ebaf350cba1285b58ecadbbaa0eb01f6))

## [1.7.2](https://github.com/laurigates/claude-plugins/compare/documentation-plugin-v1.7.1...documentation-plugin-v1.7.2) (2026-04-08)


### Bug Fixes

* **blueprint-plugin:** remove model field from skills and fix invocation syntax ([#1007](https://github.com/laurigates/claude-plugins/issues/1007)) ([42e1e5b](https://github.com/laurigates/claude-plugins/commit/42e1e5b6c73d43e5de4b27cdee16e316de44d4c0))

## [1.7.1](https://github.com/laurigates/claude-plugins/compare/documentation-plugin-v1.7.0...documentation-plugin-v1.7.1) (2026-03-25)


### Bug Fixes

* remove context: fork from all plugin skills to fix rate limit errors ([#981](https://github.com/laurigates/claude-plugins/issues/981)) ([56a90b1](https://github.com/laurigates/claude-plugins/commit/56a90b1464a9b1233a8bdb3d0716f1673bc70ad3))

## [1.7.0](https://github.com/laurigates/claude-plugins/compare/documentation-plugin-v1.6.1...documentation-plugin-v1.7.0) (2026-03-09)


### Features

* **rules:** update rules for Claude Code 2.1.63-2.1.71 changes ([#917](https://github.com/laurigates/claude-plugins/issues/917)) ([20341e8](https://github.com/laurigates/claude-plugins/commit/20341e871fe7e91eb79d51aa02ad7bc9003a93e1))

## [1.6.1](https://github.com/laurigates/claude-plugins/compare/documentation-plugin-v1.6.0...documentation-plugin-v1.6.1) (2026-03-01)


### Bug Fixes

* replace test -f/-d with find in context commands ([#850](https://github.com/laurigates/claude-plugins/issues/850)) ([a236ac8](https://github.com/laurigates/claude-plugins/commit/a236ac80ab81ce37878268b2ad76f7ad6d4aa5fb))

## [1.6.0](https://github.com/laurigates/claude-plugins/compare/documentation-plugin-v1.5.0...documentation-plugin-v1.6.0) (2026-02-27)


### Features

* add `context: fork` guidance and apply to verbose skills ([#833](https://github.com/laurigates/claude-plugins/issues/833)) ([cced641](https://github.com/laurigates/claude-plugins/commit/cced641a953953b97f37528960782cacd75dbcab))
* **skills:** add context: fork to verbose autonomous skills ([cced641](https://github.com/laurigates/claude-plugins/commit/cced641a953953b97f37528960782cacd75dbcab))

## [1.5.0](https://github.com/laurigates/claude-plugins/compare/documentation-plugin-v1.4.3...documentation-plugin-v1.5.0) (2026-02-27)


### Features

* add metadata fields to skill definitions across all plugins ([#828](https://github.com/laurigates/claude-plugins/issues/828)) ([59b3d1f](https://github.com/laurigates/claude-plugins/commit/59b3d1fadd8fd888f95ced8b071fb66cf6f9c825))
* add skill invocation control via user-invocable and disable-model-invocation frontmatter ([59b3d1f](https://github.com/laurigates/claude-plugins/commit/59b3d1fadd8fd888f95ced8b071fb66cf6f9c825))

## [1.4.3](https://github.com/laurigates/claude-plugins/compare/documentation-plugin-v1.4.2...documentation-plugin-v1.4.3) (2026-02-25)


### Bug Fixes

* **skills:** add missing args field to 57 skills with argument-hint ([#812](https://github.com/laurigates/claude-plugins/issues/812)) ([f670423](https://github.com/laurigates/claude-plugins/commit/f670423777d3d0e4edf52a1594ad82efaa13793e)), closes [#805](https://github.com/laurigates/claude-plugins/issues/805)

## [1.4.2](https://github.com/laurigates/claude-plugins/compare/documentation-plugin-v1.4.1...documentation-plugin-v1.4.2) (2026-02-23)


### Bug Fixes

* remove 2&gt;/dev/null from context commands across all plugins ([#792](https://github.com/laurigates/claude-plugins/issues/792)) ([c72e67e](https://github.com/laurigates/claude-plugins/commit/c72e67ee37e809449f0e6282c48fac01363a59fd))

## [1.4.1](https://github.com/laurigates/claude-plugins/compare/documentation-plugin-v1.4.0...documentation-plugin-v1.4.1) (2026-02-20)


### Code Refactoring

* consolidate skill documentation and remove reference files ([#758](https://github.com/laurigates/claude-plugins/issues/758)) ([3d1e8cc](https://github.com/laurigates/claude-plugins/commit/3d1e8ccd9becba5faec5b1df1fa06f410eca7437))

## [1.4.0](https://github.com/laurigates/claude-plugins/compare/documentation-plugin-v1.3.1...documentation-plugin-v1.4.0) (2026-02-18)


### Features

* introduce three-tier model palette (opus/sonnet/haiku) ([#709](https://github.com/laurigates/claude-plugins/issues/709)) ([2c1e9cc](https://github.com/laurigates/claude-plugins/commit/2c1e9ccff5d48c2b426beac5b3b38cd4576c79a0))

## [1.3.1](https://github.com/laurigates/claude-plugins/compare/documentation-plugin-v1.3.0...documentation-plugin-v1.3.1) (2026-02-15)


### Bug Fixes

* remove pipe/ls operators from context commands and add CI linting ([#653](https://github.com/laurigates/claude-plugins/issues/653)) ([7a01eef](https://github.com/laurigates/claude-plugins/commit/7a01eef21495ed6243277fbaa88082b7ecabc793))

## [1.3.0](https://github.com/laurigates/claude-plugins/compare/documentation-plugin-v1.2.2...documentation-plugin-v1.3.0) (2026-02-09)


### Features

* **blueprint-plugin,documentation-plugin:** adapt skills to Claude Code auto memory and [@import](https://github.com/import) features ([f18e27b](https://github.com/laurigates/claude-plugins/commit/f18e27bb0b2261e2a829659b919ee0f5f4fb1a4e))

## [1.2.2](https://github.com/laurigates/claude-plugins/compare/documentation-plugin-v1.2.1...documentation-plugin-v1.2.2) (2026-02-08)


### Bug Fixes

* update skill review dates to trigger release sync ([#489](https://github.com/laurigates/claude-plugins/issues/489)) ([ca20d06](https://github.com/laurigates/claude-plugins/commit/ca20d0667baaa31dfa805c7dc775a1828c515223))

## [1.2.1](https://github.com/laurigates/claude-plugins/compare/documentation-plugin-v1.2.0...documentation-plugin-v1.2.1) (2026-02-05)


### Bug Fixes

* replace ls -la with find in context commands to prevent false errors ([de8ce95](https://github.com/laurigates/claude-plugins/commit/de8ce954b4095b6c46e9326588b3fe632e87bffb))

## [1.2.0](https://github.com/laurigates/claude-plugins/compare/documentation-plugin-v1.1.2...documentation-plugin-v1.2.0) (2026-02-03)


### Features

* Add args and argument-hint parameters to commands ([6f7958e](https://github.com/laurigates/claude-plugins/commit/6f7958e78ba39b91e6d1e918935d58ae7ad376aa))

## [1.1.2](https://github.com/laurigates/claude-plugins/compare/documentation-plugin-v1.1.1...documentation-plugin-v1.1.2) (2026-02-03)


### Bug Fixes

* remove shell operators from context commands in multiple plugins ([#326](https://github.com/laurigates/claude-plugins/issues/326)) ([b028f73](https://github.com/laurigates/claude-plugins/commit/b028f7385f66f8f063a95874840c51e553694205))

## [1.1.2](https://github.com/laurigates/claude-plugins/compare/documentation-plugin-v1.1.1...documentation-plugin-v1.1.2) (2026-02-03)


### Bug Fixes

* remove shell operators from context commands in multiple plugins ([#326](https://github.com/laurigates/claude-plugins/issues/326)) ([b028f73](https://github.com/laurigates/claude-plugins/commit/b028f7385f66f8f063a95874840c51e553694205))

## [1.1.1](https://github.com/laurigates/claude-plugins/compare/documentation-plugin-v1.1.0...documentation-plugin-v1.1.1) (2026-01-25)


### Bug Fixes

* rename marketplace from 'lgates-claude-plugins' to 'laurigates-plugins' ([#195](https://github.com/laurigates/claude-plugins/issues/195)) ([4310935](https://github.com/laurigates/claude-plugins/commit/43109350d121f9c0749af86461daef9849eea133))

## [1.1.1](https://github.com/laurigates/claude-plugins/compare/documentation-plugin-v1.1.0...documentation-plugin-v1.1.1) (2026-01-25)


### Bug Fixes

* rename marketplace from 'lgates-claude-plugins' to 'laurigates-plugins' ([#195](https://github.com/laurigates/claude-plugins/issues/195)) ([4310935](https://github.com/laurigates/claude-plugins/commit/43109350d121f9c0749af86461daef9849eea133))

## [1.1.0](https://github.com/laurigates/claude-plugins/compare/documentation-plugin-v1.0.0...documentation-plugin-v1.1.0) (2026-01-22)


### Features

* add model specification to all skills and commands ([#131](https://github.com/laurigates/claude-plugins/issues/131)) ([81f2961](https://github.com/laurigates/claude-plugins/commit/81f296155b50864b8b1687b9eb18a9c2cbb08791))
