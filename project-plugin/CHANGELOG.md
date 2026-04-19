# Changelog

## [1.13.0](https://github.com/laurigates/claude-plugins/compare/project-plugin-v1.12.4...project-plugin-v1.13.0) (2026-04-19)


### Features

* make skills discoverable by Claude's auto-invocation ([#1090](https://github.com/laurigates/claude-plugins/issues/1090)) ([cded1da](https://github.com/laurigates/claude-plugins/commit/cded1da1ebaf350cba1285b58ecadbbaa0eb01f6))

## [1.12.4](https://github.com/laurigates/claude-plugins/compare/project-plugin-v1.12.3...project-plugin-v1.12.4) (2026-04-08)


### Bug Fixes

* **blueprint-plugin:** remove model field from skills and fix invocation syntax ([#1007](https://github.com/laurigates/claude-plugins/issues/1007)) ([42e1e5b](https://github.com/laurigates/claude-plugins/commit/42e1e5b6c73d43e5de4b27cdee16e316de44d4c0))

## [1.12.3](https://github.com/laurigates/claude-plugins/compare/project-plugin-v1.12.2...project-plugin-v1.12.3) (2026-03-25)


### Bug Fixes

* **git-plugin,project-plugin:** upgrade skills to opus to fix rate limit errors ([#978](https://github.com/laurigates/claude-plugins/issues/978)) ([a8fb9ba](https://github.com/laurigates/claude-plugins/commit/a8fb9baf492cbe79dd635b9bcc6f957c77ddcd82))

## [1.12.2](https://github.com/laurigates/claude-plugins/compare/project-plugin-v1.12.1...project-plugin-v1.12.2) (2026-03-24)


### Performance

* **git-plugin,project-plugin:** reduce skill token consumption by 54% ([#976](https://github.com/laurigates/claude-plugins/issues/976)) ([26b67d8](https://github.com/laurigates/claude-plugins/commit/26b67d8a5dac2a3ef8f85f9a6d7972ccb2cce89d))

## [1.12.1](https://github.com/laurigates/claude-plugins/compare/project-plugin-v1.12.0...project-plugin-v1.12.1) (2026-03-19)


### Bug Fixes

* **project-plugin:** reduce API rate limit hits in project-distill --all ([9f1a868](https://github.com/laurigates/claude-plugins/commit/9f1a868cdc18963f8dbe09748cdc7aec5425a926))


### Performance

* project-distill skill for batch API calls and efficiency ([#965](https://github.com/laurigates/claude-plugins/issues/965)) ([9f1a868](https://github.com/laurigates/claude-plugins/commit/9f1a868cdc18963f8dbe09748cdc7aec5425a926))

## [1.12.0](https://github.com/laurigates/claude-plugins/compare/project-plugin-v1.11.1...project-plugin-v1.12.0) (2026-03-05)


### Features

* standardize shell script conventions and add linting ([#892](https://github.com/laurigates/claude-plugins/issues/892)) ([0eba700](https://github.com/laurigates/claude-plugins/commit/0eba7009728418bdef6355bd91fc9ee50c6982a8))

## [1.11.1](https://github.com/laurigates/claude-plugins/compare/project-plugin-v1.11.0...project-plugin-v1.11.1) (2026-03-01)


### Bug Fixes

* replace test -f/-d with find in context commands ([#850](https://github.com/laurigates/claude-plugins/issues/850)) ([a236ac8](https://github.com/laurigates/claude-plugins/commit/a236ac80ab81ce37878268b2ad76f7ad6d4aa5fb))

## [1.11.0](https://github.com/laurigates/claude-plugins/compare/project-plugin-v1.10.2...project-plugin-v1.11.0) (2026-02-27)


### Features

* add metadata fields to skill definitions across all plugins ([#828](https://github.com/laurigates/claude-plugins/issues/828)) ([59b3d1f](https://github.com/laurigates/claude-plugins/commit/59b3d1fadd8fd888f95ced8b071fb66cf6f9c825))
* add skill invocation control via user-invocable and disable-model-invocation frontmatter ([59b3d1f](https://github.com/laurigates/claude-plugins/commit/59b3d1fadd8fd888f95ced8b071fb66cf6f9c825))

## [1.10.2](https://github.com/laurigates/claude-plugins/compare/project-plugin-v1.10.1...project-plugin-v1.10.2) (2026-02-26)


### Bug Fixes

* **scripts:** enhance context command linter with stderr safety checks and fix violations ([#819](https://github.com/laurigates/claude-plugins/issues/819)) ([2975b9b](https://github.com/laurigates/claude-plugins/commit/2975b9b0bf6698bdecf627e3d28bad06fde03cd1))

## [1.10.1](https://github.com/laurigates/claude-plugins/compare/project-plugin-v1.10.0...project-plugin-v1.10.1) (2026-02-25)


### Bug Fixes

* **skills:** add missing args field to 57 skills with argument-hint ([#812](https://github.com/laurigates/claude-plugins/issues/812)) ([f670423](https://github.com/laurigates/claude-plugins/commit/f670423777d3d0e4edf52a1594ad82efaa13793e)), closes [#805](https://github.com/laurigates/claude-plugins/issues/805)

## [1.10.0](https://github.com/laurigates/claude-plugins/compare/project-plugin-v1.9.5...project-plugin-v1.10.0) (2026-02-25)


### Features

* **python-plugin:** replace mypy with ty for type checking ([96a1aaa](https://github.com/laurigates/claude-plugins/commit/96a1aaa9c5f7e07725c72ce0a6f99f7fbf222d57))
* replace mypy with ty for Python type checking ([#808](https://github.com/laurigates/claude-plugins/issues/808)) ([96a1aaa](https://github.com/laurigates/claude-plugins/commit/96a1aaa9c5f7e07725c72ce0a6f99f7fbf222d57))

## [1.9.5](https://github.com/laurigates/claude-plugins/compare/project-plugin-v1.9.4...project-plugin-v1.9.5) (2026-02-23)


### Bug Fixes

* remove 2&gt;/dev/null from context commands across all plugins ([#792](https://github.com/laurigates/claude-plugins/issues/792)) ([c72e67e](https://github.com/laurigates/claude-plugins/commit/c72e67ee37e809449f0e6282c48fac01363a59fd))

## [1.9.4](https://github.com/laurigates/claude-plugins/compare/project-plugin-v1.9.3...project-plugin-v1.9.4) (2026-02-23)


### Bug Fixes

* **project-plugin:** remove shell operators from context commands ([#790](https://github.com/laurigates/claude-plugins/issues/790)) ([99769b5](https://github.com/laurigates/claude-plugins/commit/99769b57f7c373a6cc280571561b06dd9f1a54ef))

## [1.9.3](https://github.com/laurigates/claude-plugins/compare/project-plugin-v1.9.2...project-plugin-v1.9.3) (2026-02-23)


### Bug Fixes

* **project-plugin:** make project-distill work without git repo ([#788](https://github.com/laurigates/claude-plugins/issues/788)) ([53647bb](https://github.com/laurigates/claude-plugins/commit/53647bb10fb20e0d293c98c7c193a04e3da6164d))

## [1.9.2](https://github.com/laurigates/claude-plugins/compare/project-plugin-v1.9.1...project-plugin-v1.9.2) (2026-02-20)


### Bug Fixes

* **git-plugin:** Improve git command reliability in project-distill skill ([#765](https://github.com/laurigates/claude-plugins/issues/765)) ([96befca](https://github.com/laurigates/claude-plugins/commit/96befcaa949131b03a9d610cb9712a7eaa24c47f))
* **project-plugin:** use git log instead of HEAD~10 range in project-distill ([96befca](https://github.com/laurigates/claude-plugins/commit/96befcaa949131b03a9d610cb9712a7eaa24c47f))

## [1.9.1](https://github.com/laurigates/claude-plugins/compare/project-plugin-v1.9.0...project-plugin-v1.9.1) (2026-02-19)


### Bug Fixes

* **project-plugin:** remove redirect operators from context commands in project-distill ([aa6c87a](https://github.com/laurigates/claude-plugins/commit/aa6c87a4d0cf875e4adf32fd82261beaf9199dcd))

## [1.9.0](https://github.com/laurigates/claude-plugins/compare/project-plugin-v1.8.5...project-plugin-v1.9.0) (2026-02-18)


### Features

* introduce three-tier model palette (opus/sonnet/haiku) ([#709](https://github.com/laurigates/claude-plugins/issues/709)) ([2c1e9cc](https://github.com/laurigates/claude-plugins/commit/2c1e9ccff5d48c2b426beac5b3b38cd4576c79a0))

## [1.8.5](https://github.com/laurigates/claude-plugins/compare/project-plugin-v1.8.4...project-plugin-v1.8.5) (2026-02-15)


### Bug Fixes

* remove pipe/ls operators from context commands and add CI linting ([#653](https://github.com/laurigates/claude-plugins/issues/653)) ([7a01eef](https://github.com/laurigates/claude-plugins/commit/7a01eef21495ed6243277fbaa88082b7ecabc793))

## [1.8.4](https://github.com/laurigates/claude-plugins/compare/project-plugin-v1.8.3...project-plugin-v1.8.4) (2026-02-15)


### Bug Fixes

* replace broken context command patterns in skill files ([#644](https://github.com/laurigates/claude-plugins/issues/644)) ([440ba34](https://github.com/laurigates/claude-plugins/commit/440ba347bcc73a0512f74975cfd6b4af9fe8566e))

## [1.8.3](https://github.com/laurigates/claude-plugins/compare/project-plugin-v1.8.2...project-plugin-v1.8.3) (2026-02-14)


### Documentation

* **git-plugin:** add conventional commits standards ([#616](https://github.com/laurigates/claude-plugins/issues/616)) ([5b74389](https://github.com/laurigates/claude-plugins/commit/5b74389ecdf5223dd62368390ecd9b36ccb1596c))

## [1.8.2](https://github.com/laurigates/claude-plugins/compare/project-plugin-v1.8.1...project-plugin-v1.8.2) (2026-02-14)


### Code Refactoring

* restructure 11 skills to execution pattern ([#609](https://github.com/laurigates/claude-plugins/issues/609)) ([0aff44a](https://github.com/laurigates/claude-plugins/commit/0aff44ae5768e3cd3aedfed568137738fc298bbc))

## [1.8.1](https://github.com/laurigates/claude-plugins/compare/project-plugin-v1.8.0...project-plugin-v1.8.1) (2026-02-13)


### Documentation

* improve skill documentation, standards, and context patterns ([#599](https://github.com/laurigates/claude-plugins/issues/599)) ([4a351dc](https://github.com/laurigates/claude-plugins/commit/4a351dcfac7229dd26586cdf7c8cbd51fec451d2))
* **skills:** improve documentation, standards, and context patterns ([4a351dc](https://github.com/laurigates/claude-plugins/commit/4a351dcfac7229dd26586cdf7c8cbd51fec451d2)), closes [#596](https://github.com/laurigates/claude-plugins/issues/596)

## [1.8.0](https://github.com/laurigates/claude-plugins/compare/project-plugin-v1.7.0...project-plugin-v1.8.0) (2026-02-12)


### Features

* **blueprint-plugin:** add v3.0→v3.1 migration and remove work-overview references ([e9849b0](https://github.com/laurigates/claude-plugins/commit/e9849b0a0d3d434432d32e68fee3498696fb09c8))

## [1.7.0](https://github.com/laurigates/claude-plugins/compare/project-plugin-v1.6.2...project-plugin-v1.7.0) (2026-02-11)


### Features

* **project-plugin:** add /project:distill skill for session knowledge capture ([f2b9f7e](https://github.com/laurigates/claude-plugins/commit/f2b9f7e51cbaf7a7656e0dfd505bc75f6662ac29))


### Code Refactoring

* **project-plugin:** improve project-distill skill discoverability and robustness ([002a8c8](https://github.com/laurigates/claude-plugins/commit/002a8c8feb6e6ab0c943509689375aba95b15abd))

## [1.6.2](https://github.com/laurigates/claude-plugins/compare/project-plugin-v1.6.1...project-plugin-v1.6.2) (2026-02-08)


### Bug Fixes

* update skill review dates to trigger release sync ([#489](https://github.com/laurigates/claude-plugins/issues/489)) ([ca20d06](https://github.com/laurigates/claude-plugins/commit/ca20d0667baaa31dfa805c7dc775a1828c515223))

## [1.6.1](https://github.com/laurigates/claude-plugins/compare/project-plugin-v1.6.0...project-plugin-v1.6.1) (2026-02-05)


### Code Refactoring

* move plugin root scripts to scripts/ subdirectory ([d7344f8](https://github.com/laurigates/claude-plugins/commit/d7344f8f567ee5640aba182049f7aada5e8f4134))

## [1.6.0](https://github.com/laurigates/claude-plugins/compare/project-plugin-v1.5.2...project-plugin-v1.6.0) (2026-02-03)


### Features

* Add args and argument-hint parameters to commands ([6f7958e](https://github.com/laurigates/claude-plugins/commit/6f7958e78ba39b91e6d1e918935d58ae7ad376aa))

## [1.5.2](https://github.com/laurigates/claude-plugins/compare/project-plugin-v1.5.1...project-plugin-v1.5.2) (2026-02-01)


### Code Refactoring

* **blueprint-plugin:** remove deprecated generate-commands ([#292](https://github.com/laurigates/claude-plugins/issues/292)) ([438cb35](https://github.com/laurigates/claude-plugins/commit/438cb353127522bc1c96c499d4fcabbb71934969))

## [1.5.1](https://github.com/laurigates/claude-plugins/compare/project-plugin-v1.5.0...project-plugin-v1.5.1) (2026-02-01)


### Bug Fixes

* enforce granular Bash permissions across all plugins ([#267](https://github.com/laurigates/claude-plugins/issues/267)) ([afeb507](https://github.com/laurigates/claude-plugins/commit/afeb50754838c2923807c8f2a248b3798fd4281c))

## [1.5.0](https://github.com/laurigates/claude-plugins/compare/project-plugin-v1.4.0...project-plugin-v1.5.0) (2026-01-24)


### Features

* **git-plugin,code-quality-plugin,project-plugin:** add supporting scripts to skills ([#206](https://github.com/laurigates/claude-plugins/issues/206)) ([0b33d50](https://github.com/laurigates/claude-plugins/commit/0b33d502e18584b264c7c4a99dddda54dc573d08))

## [1.4.0](https://github.com/laurigates/claude-plugins/compare/project-plugin-v1.3.0...project-plugin-v1.4.0) (2026-01-23)


### Features

* add model specification to all skills and commands ([#131](https://github.com/laurigates/claude-plugins/issues/131)) ([81f2961](https://github.com/laurigates/claude-plugins/commit/81f296155b50864b8b1687b9eb18a9c2cbb08791))

## [1.3.0](https://github.com/laurigates/claude-plugins/compare/project-plugin-v1.2.1...project-plugin-v1.3.0) (2026-01-15)


### Features

* **changelog-plugin:** add automated Claude Code changelog tracking ([#74](https://github.com/laurigates/claude-plugins/issues/74)) ([0e24de9](https://github.com/laurigates/claude-plugins/commit/0e24de982762a515929e05e1f260ff4daf46278a))

## [1.2.1](https://github.com/laurigates/claude-plugins/compare/project-plugin-v1.2.0...project-plugin-v1.2.1) (2026-01-09)


### Bug Fixes

* sync plugin.json versions to match release-please manifest ([1ac44e1](https://github.com/laurigates/claude-plugins/commit/1ac44e1240eed27eb3f829edaaac9bc863634d89))

## [1.2.1](https://github.com/laurigates/claude-plugins/compare/project-plugin-v1.2.0...project-plugin-v1.2.1) (2026-01-09)


### Bug Fixes

* sync plugin.json versions to match release-please manifest ([1ac44e1](https://github.com/laurigates/claude-plugins/commit/1ac44e1240eed27eb3f829edaaac9bc863634d89))

## [1.2.0](https://github.com/laurigates/claude-plugins/compare/project-plugin-v1.1.0...project-plugin-v1.2.0) (2025-12-28)


### Features

* **blueprint:** add version tracking, modular rules, and CLAUDE.md management ([e6fd2c0](https://github.com/laurigates/claude-plugins/commit/e6fd2c01554c474044b88bafe95aef9d534b6b1a))
