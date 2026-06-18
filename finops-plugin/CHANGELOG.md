# Changelog

## [1.4.0](https://github.com/laurigates/claude-plugins/compare/finops-plugin-v1.3.7...finops-plugin-v1.4.0) (2026-06-18)


### Features

* **scripts:** context-command execution harness + sweep 122 fragile Context commands ([#1690](https://github.com/laurigates/claude-plugins/issues/1690)) ([609342f](https://github.com/laurigates/claude-plugins/commit/609342f2c5b6b5f2ee555f83dbac1f5f3dd1f93d))

## [1.3.7](https://github.com/laurigates/claude-plugins/compare/finops-plugin-v1.3.6...finops-plugin-v1.3.7) (2026-06-13)


### Bug Fixes

* **skills:** rename 45 skill.md files to canonical SKILL.md ([#1608](https://github.com/laurigates/claude-plugins/issues/1608)) ([786b701](https://github.com/laurigates/claude-plugins/commit/786b701ee78134e31251f8c69dc58c34e4ccbb14))

## [1.3.6](https://github.com/laurigates/claude-plugins/compare/finops-plugin-v1.3.5...finops-plugin-v1.3.6) (2026-06-10)


### Code Refactoring

* **finops-plugin:** extract github-actions-finops procedure to scripts + regression test ([#1566](https://github.com/laurigates/claude-plugins/issues/1566)) ([bca4a36](https://github.com/laurigates/claude-plugins/commit/bca4a36ba81cd285014c703082ed8e62503b3bf8))

## [1.3.5](https://github.com/laurigates/claude-plugins/compare/finops-plugin-v1.3.4...finops-plugin-v1.3.5) (2026-05-14)


### Code Refactoring

* **finops-plugin:** tighten skill descriptions for listing budget ([ec026e0](https://github.com/laurigates/claude-plugins/commit/ec026e015fb9e154299bc955dcc426973ab6c39d))

## [1.3.4](https://github.com/laurigates/claude-plugins/compare/finops-plugin-v1.3.3...finops-plugin-v1.3.4) (2026-05-09)


### Documentation

* trim oversized SKILL.md descriptions across 41 plugins ([#1265](https://github.com/laurigates/claude-plugins/issues/1265)) ([e13d9f4](https://github.com/laurigates/claude-plugins/commit/e13d9f46a010559082c6d5eb61b0cb891843bf97))

## [1.3.3](https://github.com/laurigates/claude-plugins/compare/finops-plugin-v1.3.2...finops-plugin-v1.3.3) (2026-04-25)


### Documentation

* **finops-plugin:** standardise When to Use tables ([#1180](https://github.com/laurigates/claude-plugins/issues/1180)) ([41c8630](https://github.com/laurigates/claude-plugins/commit/41c8630a9c414d08f39074682a3017eaeeeba1f9)), closes [#1156](https://github.com/laurigates/claude-plugins/issues/1156)

## [1.3.2](https://github.com/laurigates/claude-plugins/compare/finops-plugin-v1.3.1...finops-plugin-v1.3.2) (2026-04-08)


### Bug Fixes

* **blueprint-plugin:** remove model field from skills and fix invocation syntax ([#1007](https://github.com/laurigates/claude-plugins/issues/1007)) ([42e1e5b](https://github.com/laurigates/claude-plugins/commit/42e1e5b6c73d43e5de4b27cdee16e316de44d4c0))

## [1.3.1](https://github.com/laurigates/claude-plugins/compare/finops-plugin-v1.3.0...finops-plugin-v1.3.1) (2026-03-09)


### Bug Fixes

* **finops-plugin,git-plugin:** replace gh repo view with git remote in context commands ([#913](https://github.com/laurigates/claude-plugins/issues/913)) ([f4cf31a](https://github.com/laurigates/claude-plugins/commit/f4cf31aebdc00d6a6d7ca911db3cf1534b13ce75))

## [1.3.0](https://github.com/laurigates/claude-plugins/compare/finops-plugin-v1.2.0...finops-plugin-v1.3.0) (2026-03-05)


### Features

* **finops-plugin:** extract inline bash into standalone scripts ([#889](https://github.com/laurigates/claude-plugins/issues/889)) ([74bab2c](https://github.com/laurigates/claude-plugins/commit/74bab2c438005c0a8dd249b9a96a56a4ad8f4283))

## [1.2.0](https://github.com/laurigates/claude-plugins/compare/finops-plugin-v1.1.0...finops-plugin-v1.2.0) (2026-02-27)


### Features

* add metadata fields to skill definitions across all plugins ([#828](https://github.com/laurigates/claude-plugins/issues/828)) ([59b3d1f](https://github.com/laurigates/claude-plugins/commit/59b3d1fadd8fd888f95ced8b071fb66cf6f9c825))
* add skill invocation control via user-invocable and disable-model-invocation frontmatter ([59b3d1f](https://github.com/laurigates/claude-plugins/commit/59b3d1fadd8fd888f95ced8b071fb66cf6f9c825))


### Bug Fixes

* remove 2&gt;/dev/null from context commands across all plugins ([#792](https://github.com/laurigates/claude-plugins/issues/792)) ([c72e67e](https://github.com/laurigates/claude-plugins/commit/c72e67ee37e809449f0e6282c48fac01363a59fd))
* remove pipe/ls operators from context commands and add CI linting ([#653](https://github.com/laurigates/claude-plugins/issues/653)) ([7a01eef](https://github.com/laurigates/claude-plugins/commit/7a01eef21495ed6243277fbaa88082b7ecabc793))
* remove shell operators from context commands across all plugins ([#316](https://github.com/laurigates/claude-plugins/issues/316)) ([ecabe72](https://github.com/laurigates/claude-plugins/commit/ecabe72ebd100af1219f97012832d8ba500965b5))
* update skill review dates to trigger release sync ([#489](https://github.com/laurigates/claude-plugins/issues/489)) ([ca20d06](https://github.com/laurigates/claude-plugins/commit/ca20d0667baaa31dfa805c7dc775a1828c515223))


### Documentation

* **rules, settings:** refactor to emphasize positive guidance patterns ([#360](https://github.com/laurigates/claude-plugins/issues/360)) ([a4ea8a8](https://github.com/laurigates/claude-plugins/commit/a4ea8a8990e2a40bb2331855db5fd68631c14d7e))

## [1.1.0](https://github.com/laurigates/claude-plugins/compare/finops-plugin-v1.0.5...finops-plugin-v1.1.0) (2026-02-27)


### Features

* add metadata fields to skill definitions across all plugins ([#828](https://github.com/laurigates/claude-plugins/issues/828)) ([59b3d1f](https://github.com/laurigates/claude-plugins/commit/59b3d1fadd8fd888f95ced8b071fb66cf6f9c825))
* add skill invocation control via user-invocable and disable-model-invocation frontmatter ([59b3d1f](https://github.com/laurigates/claude-plugins/commit/59b3d1fadd8fd888f95ced8b071fb66cf6f9c825))

## [1.0.5](https://github.com/laurigates/claude-plugins/compare/finops-plugin-v1.0.4...finops-plugin-v1.0.5) (2026-02-23)


### Bug Fixes

* remove 2&gt;/dev/null from context commands across all plugins ([#792](https://github.com/laurigates/claude-plugins/issues/792)) ([c72e67e](https://github.com/laurigates/claude-plugins/commit/c72e67ee37e809449f0e6282c48fac01363a59fd))

## [1.0.4](https://github.com/laurigates/claude-plugins/compare/finops-plugin-v1.0.3...finops-plugin-v1.0.4) (2026-02-15)


### Bug Fixes

* remove pipe/ls operators from context commands and add CI linting ([#653](https://github.com/laurigates/claude-plugins/issues/653)) ([7a01eef](https://github.com/laurigates/claude-plugins/commit/7a01eef21495ed6243277fbaa88082b7ecabc793))

## [1.0.3](https://github.com/laurigates/claude-plugins/compare/finops-plugin-v1.0.2...finops-plugin-v1.0.3) (2026-02-08)


### Bug Fixes

* update skill review dates to trigger release sync ([#489](https://github.com/laurigates/claude-plugins/issues/489)) ([ca20d06](https://github.com/laurigates/claude-plugins/commit/ca20d0667baaa31dfa805c7dc775a1828c515223))

## [1.0.2](https://github.com/laurigates/claude-plugins/compare/finops-plugin-v1.0.1...finops-plugin-v1.0.2) (2026-02-04)


### Documentation

* **rules, settings:** refactor to emphasize positive guidance patterns ([#360](https://github.com/laurigates/claude-plugins/issues/360)) ([a4ea8a8](https://github.com/laurigates/claude-plugins/commit/a4ea8a8990e2a40bb2331855db5fd68631c14d7e))

## [1.0.1](https://github.com/laurigates/claude-plugins/compare/finops-plugin-v1.0.0...finops-plugin-v1.0.1) (2026-02-03)


### Bug Fixes

* remove shell operators from context commands across all plugins ([#316](https://github.com/laurigates/claude-plugins/issues/316)) ([ecabe72](https://github.com/laurigates/claude-plugins/commit/ecabe72ebd100af1219f97012832d8ba500965b5))

## 1.0.0 (2026-01-30)


### Features

* **finops-plugin:** add GitHub Actions FinOps plugin ([34f2e0e](https://github.com/laurigates/claude-plugins/commit/34f2e0ea552595d71d38e1cc0e6c90d0be33ecdb))
