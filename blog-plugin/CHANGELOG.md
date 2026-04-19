# Changelog

## [1.3.0](https://github.com/laurigates/claude-plugins/compare/blog-plugin-v1.2.2...blog-plugin-v1.3.0) (2026-04-19)


### Features

* make skills discoverable by Claude's auto-invocation ([#1090](https://github.com/laurigates/claude-plugins/issues/1090)) ([cded1da](https://github.com/laurigates/claude-plugins/commit/cded1da1ebaf350cba1285b58ecadbbaa0eb01f6))

## [1.2.2](https://github.com/laurigates/claude-plugins/compare/blog-plugin-v1.2.1...blog-plugin-v1.2.2) (2026-04-08)


### Bug Fixes

* **blueprint-plugin:** remove model field from skills and fix invocation syntax ([#1007](https://github.com/laurigates/claude-plugins/issues/1007)) ([42e1e5b](https://github.com/laurigates/claude-plugins/commit/42e1e5b6c73d43e5de4b27cdee16e316de44d4c0))

## [1.2.1](https://github.com/laurigates/claude-plugins/compare/blog-plugin-v1.2.0...blog-plugin-v1.2.1) (2026-03-04)


### Bug Fixes

* haiku model incompatibility with AskUserQuestion tool ([#881](https://github.com/laurigates/claude-plugins/issues/881)) ([c09e400](https://github.com/laurigates/claude-plugins/commit/c09e40031e2eef7fa78640ee1d8327a0f18bbe64))

## [1.2.0](https://github.com/laurigates/claude-plugins/compare/blog-plugin-v1.1.9...blog-plugin-v1.2.0) (2026-02-27)


### Features

* add metadata fields to skill definitions across all plugins ([#828](https://github.com/laurigates/claude-plugins/issues/828)) ([59b3d1f](https://github.com/laurigates/claude-plugins/commit/59b3d1fadd8fd888f95ced8b071fb66cf6f9c825))
* add skill invocation control via user-invocable and disable-model-invocation frontmatter ([59b3d1f](https://github.com/laurigates/claude-plugins/commit/59b3d1fadd8fd888f95ced8b071fb66cf6f9c825))

## [1.1.9](https://github.com/laurigates/claude-plugins/compare/blog-plugin-v1.1.8...blog-plugin-v1.1.9) (2026-02-25)


### Bug Fixes

* replace git remote get-url with git remote -v for verbose output ([#804](https://github.com/laurigates/claude-plugins/issues/804)) ([e39407a](https://github.com/laurigates/claude-plugins/commit/e39407a366d2d0ba431df0f456074b847073eea8))
* **skills:** replace git remote get-url origin with git remote -v in context commands ([e39407a](https://github.com/laurigates/claude-plugins/commit/e39407a366d2d0ba431df0f456074b847073eea8))

## [1.1.8](https://github.com/laurigates/claude-plugins/compare/blog-plugin-v1.1.7...blog-plugin-v1.1.8) (2026-02-23)


### Bug Fixes

* remove 2&gt;/dev/null from context commands across all plugins ([#792](https://github.com/laurigates/claude-plugins/issues/792)) ([c72e67e](https://github.com/laurigates/claude-plugins/commit/c72e67ee37e809449f0e6282c48fac01363a59fd))

## [1.1.7](https://github.com/laurigates/claude-plugins/compare/blog-plugin-v1.1.6...blog-plugin-v1.1.7) (2026-02-15)


### Bug Fixes

* replace broken context command patterns in skill files ([#644](https://github.com/laurigates/claude-plugins/issues/644)) ([440ba34](https://github.com/laurigates/claude-plugins/commit/440ba347bcc73a0512f74975cfd6b4af9fe8566e))

## [1.1.6](https://github.com/laurigates/claude-plugins/compare/blog-plugin-v1.1.5...blog-plugin-v1.1.6) (2026-02-14)


### Code Refactoring

* extract detailed content to REFERENCE.md files ([#605](https://github.com/laurigates/claude-plugins/issues/605)) ([7efbd83](https://github.com/laurigates/claude-plugins/commit/7efbd83b9a2b1ef67be702206396ba6d8102684d))

## [1.1.5](https://github.com/laurigates/claude-plugins/compare/blog-plugin-v1.1.4...blog-plugin-v1.1.5) (2026-02-14)


### Documentation

* **git-plugin:** add conventional commits standards ([#616](https://github.com/laurigates/claude-plugins/issues/616)) ([5b74389](https://github.com/laurigates/claude-plugins/commit/5b74389ecdf5223dd62368390ecd9b36ccb1596c))

## [1.1.4](https://github.com/laurigates/claude-plugins/compare/blog-plugin-v1.1.3...blog-plugin-v1.1.4) (2026-02-14)


### Code Refactoring

* restructure 11 skills to execution pattern ([#609](https://github.com/laurigates/claude-plugins/issues/609)) ([0aff44a](https://github.com/laurigates/claude-plugins/commit/0aff44ae5768e3cd3aedfed568137738fc298bbc))

## [1.1.3](https://github.com/laurigates/claude-plugins/compare/blog-plugin-v1.1.2...blog-plugin-v1.1.3) (2026-02-12)


### Bug Fixes

* standardize skill name fields to kebab-case across all plugins ([72c0f83](https://github.com/laurigates/claude-plugins/commit/72c0f837a1b07004850c5906a30d619a79098f69))

## [1.1.2](https://github.com/laurigates/claude-plugins/compare/blog-plugin-v1.1.1...blog-plugin-v1.1.2) (2026-02-08)


### Bug Fixes

* update skill review dates to trigger release sync ([#489](https://github.com/laurigates/claude-plugins/issues/489)) ([ca20d06](https://github.com/laurigates/claude-plugins/commit/ca20d0667baaa31dfa805c7dc775a1828c515223))

## [1.1.1](https://github.com/laurigates/claude-plugins/compare/blog-plugin-v1.1.0...blog-plugin-v1.1.1) (2026-02-01)


### Bug Fixes

* enforce granular Bash permissions across all plugins ([#267](https://github.com/laurigates/claude-plugins/issues/267)) ([afeb507](https://github.com/laurigates/claude-plugins/commit/afeb50754838c2923807c8f2a248b3798fd4281c))

## [1.1.0](https://github.com/laurigates/claude-plugins/compare/blog-plugin-v1.0.0...blog-plugin-v1.1.0) (2026-01-23)


### Features

* add model specification to all skills and commands ([#131](https://github.com/laurigates/claude-plugins/issues/131)) ([81f2961](https://github.com/laurigates/claude-plugins/commit/81f296155b50864b8b1687b9eb18a9c2cbb08791))
