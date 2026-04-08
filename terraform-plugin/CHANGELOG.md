# Changelog

## [1.7.1](https://github.com/laurigates/claude-plugins/compare/terraform-plugin-v1.7.0...terraform-plugin-v1.7.1) (2026-04-08)


### Bug Fixes

* **blueprint-plugin:** remove model field from skills and fix invocation syntax ([#1007](https://github.com/laurigates/claude-plugins/issues/1007)) ([42e1e5b](https://github.com/laurigates/claude-plugins/commit/42e1e5b6c73d43e5de4b27cdee16e316de44d4c0))

## [1.7.0](https://github.com/laurigates/claude-plugins/compare/terraform-plugin-v1.6.0...terraform-plugin-v1.7.0) (2026-03-09)


### Features

* **rules:** update rules for Claude Code 2.1.63-2.1.71 changes ([#917](https://github.com/laurigates/claude-plugins/issues/917)) ([20341e8](https://github.com/laurigates/claude-plugins/commit/20341e871fe7e91eb79d51aa02ad7bc9003a93e1))

## [1.6.0](https://github.com/laurigates/claude-plugins/compare/terraform-plugin-v1.5.0...terraform-plugin-v1.6.0) (2026-03-05)


### Features

* standardize shell script conventions and add linting ([#892](https://github.com/laurigates/claude-plugins/issues/892)) ([0eba700](https://github.com/laurigates/claude-plugins/commit/0eba7009728418bdef6355bd91fc9ee50c6982a8))

## [1.5.0](https://github.com/laurigates/claude-plugins/compare/terraform-plugin-v1.4.0...terraform-plugin-v1.5.0) (2026-02-27)


### Features

* add safety hooks for Terraform, Kubernetes, Git, and Blueprint plugins ([#835](https://github.com/laurigates/claude-plugins/issues/835)) ([d4d86a0](https://github.com/laurigates/claude-plugins/commit/d4d86a03b96d99642f341effb8f3999df5246c8b))
* **blueprint-plugin:** add PreCompact hook for derivation workflow context ([d4d86a0](https://github.com/laurigates/claude-plugins/commit/d4d86a03b96d99642f341effb8f3999df5246c8b))
* **kubernetes-plugin:** add kubectl dry-run injection hook ([d4d86a0](https://github.com/laurigates/claude-plugins/commit/d4d86a03b96d99642f341effb8f3999df5246c8b))
* **terraform-plugin:** add terraform apply gate hook ([d4d86a0](https://github.com/laurigates/claude-plugins/commit/d4d86a03b96d99642f341effb8f3999df5246c8b))

## [1.4.0](https://github.com/laurigates/claude-plugins/compare/terraform-plugin-v1.3.0...terraform-plugin-v1.4.0) (2026-02-27)


### Features

* add metadata fields to skill definitions across all plugins ([#828](https://github.com/laurigates/claude-plugins/issues/828)) ([59b3d1f](https://github.com/laurigates/claude-plugins/commit/59b3d1fadd8fd888f95ced8b071fb66cf6f9c825))
* add skill invocation control via user-invocable and disable-model-invocation frontmatter ([59b3d1f](https://github.com/laurigates/claude-plugins/commit/59b3d1fadd8fd888f95ced8b071fb66cf6f9c825))

## [1.3.0](https://github.com/laurigates/claude-plugins/compare/terraform-plugin-v1.2.3...terraform-plugin-v1.3.0) (2026-02-18)


### Features

* introduce three-tier model palette (opus/sonnet/haiku) ([#709](https://github.com/laurigates/claude-plugins/issues/709)) ([2c1e9cc](https://github.com/laurigates/claude-plugins/commit/2c1e9ccff5d48c2b426beac5b3b38cd4576c79a0))

## [1.2.3](https://github.com/laurigates/claude-plugins/compare/terraform-plugin-v1.2.2...terraform-plugin-v1.2.3) (2026-02-08)


### Bug Fixes

* update skill review dates to trigger release sync ([#489](https://github.com/laurigates/claude-plugins/issues/489)) ([ca20d06](https://github.com/laurigates/claude-plugins/commit/ca20d0667baaa31dfa805c7dc775a1828c515223))

## [1.2.2](https://github.com/laurigates/claude-plugins/compare/terraform-plugin-v1.2.1...terraform-plugin-v1.2.2) (2026-02-03)


### Bug Fixes

* **agent-patterns-plugin:** block git writes for parallel agents to prevent conflicts ([#299](https://github.com/laurigates/claude-plugins/issues/299)) ([a2c2ce0](https://github.com/laurigates/claude-plugins/commit/a2c2ce07d67ead9b30470b398777be355672281b))

## [1.2.2](https://github.com/laurigates/claude-plugins/compare/terraform-plugin-v1.2.1...terraform-plugin-v1.2.2) (2026-02-02)


### Bug Fixes

* **agent-patterns-plugin:** block git writes for parallel agents to prevent conflicts ([#299](https://github.com/laurigates/claude-plugins/issues/299)) ([a2c2ce0](https://github.com/laurigates/claude-plugins/commit/a2c2ce07d67ead9b30470b398777be355672281b))

## [1.2.1](https://github.com/laurigates/claude-plugins/compare/terraform-plugin-v1.2.0...terraform-plugin-v1.2.1) (2026-01-26)


### Bug Fixes

* rename marketplace from 'lgates-claude-plugins' to 'laurigates-plugins' ([#195](https://github.com/laurigates/claude-plugins/issues/195)) ([4310935](https://github.com/laurigates/claude-plugins/commit/43109350d121f9c0749af86461daef9849eea133))

## [1.2.1](https://github.com/laurigates/claude-plugins/compare/terraform-plugin-v1.2.0...terraform-plugin-v1.2.1) (2026-01-25)


### Bug Fixes

* rename marketplace from 'lgates-claude-plugins' to 'laurigates-plugins' ([#195](https://github.com/laurigates/claude-plugins/issues/195)) ([4310935](https://github.com/laurigates/claude-plugins/commit/43109350d121f9c0749af86461daef9849eea133))

## [1.2.1](https://github.com/laurigates/claude-plugins/compare/terraform-plugin-v1.2.0...terraform-plugin-v1.2.1) (2026-01-25)


### Bug Fixes

* rename marketplace from 'lgates-claude-plugins' to 'laurigates-plugins' ([#195](https://github.com/laurigates/claude-plugins/issues/195)) ([4310935](https://github.com/laurigates/claude-plugins/commit/43109350d121f9c0749af86461daef9849eea133))

## [1.2.0](https://github.com/laurigates/claude-plugins/compare/terraform-plugin-v1.1.0...terraform-plugin-v1.2.0) (2026-01-24)


### Features

* add model specification to all skills and commands ([#131](https://github.com/laurigates/claude-plugins/issues/131)) ([81f2961](https://github.com/laurigates/claude-plugins/commit/81f296155b50864b8b1687b9eb18a9c2cbb08791))

## [1.2.0](https://github.com/laurigates/claude-plugins/compare/terraform-plugin-v1.1.0...terraform-plugin-v1.2.0) (2026-01-23)


### Features

* add model specification to all skills and commands ([#131](https://github.com/laurigates/claude-plugins/issues/131)) ([81f2961](https://github.com/laurigates/claude-plugins/commit/81f296155b50864b8b1687b9eb18a9c2cbb08791))

## [1.2.0](https://github.com/laurigates/claude-plugins/compare/terraform-plugin-v1.1.0...terraform-plugin-v1.2.0) (2026-01-23)


### Features

* add model specification to all skills and commands ([#131](https://github.com/laurigates/claude-plugins/issues/131)) ([81f2961](https://github.com/laurigates/claude-plugins/commit/81f296155b50864b8b1687b9eb18a9c2cbb08791))

## [1.1.0](https://github.com/laurigates/claude-plugins/compare/terraform-plugin-v1.0.0...terraform-plugin-v1.1.0) (2026-01-20)


### Features

* **terraform-plugin:** add -chdir flag and agentic optimizations ([#115](https://github.com/laurigates/claude-plugins/issues/115)) ([ed5e25a](https://github.com/laurigates/claude-plugins/commit/ed5e25a14055bc080d56ab1ff99ea528a0e5ea2e))
