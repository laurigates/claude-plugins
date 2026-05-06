# Changelog

## [1.7.5](https://github.com/laurigates/claude-plugins/compare/github-actions-plugin-v1.7.4...github-actions-plugin-v1.7.5) (2026-05-06)


### Bug Fixes

* **plugins:** quote args/argument-hint values to fix skill autocomplete ([#1254](https://github.com/laurigates/claude-plugins/issues/1254)) ([1874cff](https://github.com/laurigates/claude-plugins/commit/1874cfff8b724819bea6d9604b654cadf10b8038))

## [1.7.4](https://github.com/laurigates/claude-plugins/compare/github-actions-plugin-v1.7.3...github-actions-plugin-v1.7.4) (2026-04-25)


### Bug Fixes

* **skills:** convert When to Use sections to required table format ([#1192](https://github.com/laurigates/claude-plugins/issues/1192)) ([4a52cb4](https://github.com/laurigates/claude-plugins/commit/4a52cb4f5cbc459e5df78d361891a91bbe1496ec))

## [1.7.3](https://github.com/laurigates/claude-plugins/compare/github-actions-plugin-v1.7.2...github-actions-plugin-v1.7.3) (2026-04-25)


### Documentation

* **github-actions-plugin:** standardise When to Use tables ([#1174](https://github.com/laurigates/claude-plugins/issues/1174)) ([74973e1](https://github.com/laurigates/claude-plugins/commit/74973e101f2921bfe3463e553acf15853f08b31c)), closes [#1156](https://github.com/laurigates/claude-plugins/issues/1156)

## [1.7.2](https://github.com/laurigates/claude-plugins/compare/github-actions-plugin-v1.7.1...github-actions-plugin-v1.7.2) (2026-04-25)


### Documentation

* **git-plugin,github-actions-plugin:** add When to Use tables to 3 skills ([#1144](https://github.com/laurigates/claude-plugins/issues/1144)) ([aa5a803](https://github.com/laurigates/claude-plugins/commit/aa5a8032ba06b299fb0dfa18d5e65c6b4d3ee851))

## [1.7.1](https://github.com/laurigates/claude-plugins/compare/github-actions-plugin-v1.7.0...github-actions-plugin-v1.7.1) (2026-04-24)


### Bug Fixes

* **feedback-plugin,git-plugin,github-actions-plugin:** remove gh list from context ([#1123](https://github.com/laurigates/claude-plugins/issues/1123)) ([8ad0b71](https://github.com/laurigates/claude-plugins/commit/8ad0b7140028a749dd61027f80eb0c75bb6f8bfb))

## [1.7.0](https://github.com/laurigates/claude-plugins/compare/github-actions-plugin-v1.6.1...github-actions-plugin-v1.7.0) (2026-04-19)


### Features

* make skills discoverable by Claude's auto-invocation ([#1090](https://github.com/laurigates/claude-plugins/issues/1090)) ([cded1da](https://github.com/laurigates/claude-plugins/commit/cded1da1ebaf350cba1285b58ecadbbaa0eb01f6))

## [1.6.1](https://github.com/laurigates/claude-plugins/compare/github-actions-plugin-v1.6.0...github-actions-plugin-v1.6.1) (2026-04-08)


### Bug Fixes

* **blueprint-plugin:** remove model field from skills and fix invocation syntax ([#1007](https://github.com/laurigates/claude-plugins/issues/1007)) ([42e1e5b](https://github.com/laurigates/claude-plugins/commit/42e1e5b6c73d43e5de4b27cdee16e316de44d4c0))

## [1.6.0](https://github.com/laurigates/claude-plugins/compare/github-actions-plugin-v1.5.0...github-actions-plugin-v1.6.0) (2026-03-07)


### Features

* **github-actions-plugin:** add reusable CI auto-fix workflow skill ([#895](https://github.com/laurigates/claude-plugins/issues/895)) ([8b34b53](https://github.com/laurigates/claude-plugins/commit/8b34b53eb97ab599a7d58780ea26bf70d9cece13))

## [1.5.0](https://github.com/laurigates/claude-plugins/compare/github-actions-plugin-v1.4.4...github-actions-plugin-v1.5.0) (2026-02-27)


### Features

* add metadata fields to skill definitions across all plugins ([#828](https://github.com/laurigates/claude-plugins/issues/828)) ([59b3d1f](https://github.com/laurigates/claude-plugins/commit/59b3d1fadd8fd888f95ced8b071fb66cf6f9c825))
* add skill invocation control via user-invocable and disable-model-invocation frontmatter ([59b3d1f](https://github.com/laurigates/claude-plugins/commit/59b3d1fadd8fd888f95ced8b071fb66cf6f9c825))

## [1.4.4](https://github.com/laurigates/claude-plugins/compare/github-actions-plugin-v1.4.3...github-actions-plugin-v1.4.4) (2026-02-25)


### Bug Fixes

* **skills:** add missing args field to 57 skills with argument-hint ([#812](https://github.com/laurigates/claude-plugins/issues/812)) ([f670423](https://github.com/laurigates/claude-plugins/commit/f670423777d3d0e4edf52a1594ad82efaa13793e)), closes [#805](https://github.com/laurigates/claude-plugins/issues/805)

## [1.4.3](https://github.com/laurigates/claude-plugins/compare/github-actions-plugin-v1.4.2...github-actions-plugin-v1.4.3) (2026-02-23)


### Bug Fixes

* remove 2&gt;/dev/null from context commands across all plugins ([#792](https://github.com/laurigates/claude-plugins/issues/792)) ([c72e67e](https://github.com/laurigates/claude-plugins/commit/c72e67ee37e809449f0e6282c48fac01363a59fd))

## [1.4.2](https://github.com/laurigates/claude-plugins/compare/github-actions-plugin-v1.4.1...github-actions-plugin-v1.4.2) (2026-02-20)


### Code Refactoring

* consolidate skill documentation and remove reference files ([#758](https://github.com/laurigates/claude-plugins/issues/758)) ([3d1e8cc](https://github.com/laurigates/claude-plugins/commit/3d1e8ccd9becba5faec5b1df1fa06f410eca7437))

## [1.4.1](https://github.com/laurigates/claude-plugins/compare/github-actions-plugin-v1.4.0...github-actions-plugin-v1.4.1) (2026-02-19)


### Documentation

* **ci:** add issue descriptions for lint errors and max-turns config ([#764](https://github.com/laurigates/claude-plugins/issues/764)) ([eba261f](https://github.com/laurigates/claude-plugins/commit/eba261fa6be4134a025ad55c3ef76825b9662301))

## [1.4.0](https://github.com/laurigates/claude-plugins/compare/github-actions-plugin-v1.3.0...github-actions-plugin-v1.4.0) (2026-02-18)


### Features

* **github-actions-plugin:** add workflow auto-fix for CI failures ([#751](https://github.com/laurigates/claude-plugins/issues/751)) ([27f1773](https://github.com/laurigates/claude-plugins/commit/27f1773022cf52f64873b13ed1e8321c5c9c1a0b))

## [1.3.0](https://github.com/laurigates/claude-plugins/compare/github-actions-plugin-v1.2.0...github-actions-plugin-v1.3.0) (2026-02-18)


### Features

* introduce three-tier model palette (opus/sonnet/haiku) ([#709](https://github.com/laurigates/claude-plugins/issues/709)) ([2c1e9cc](https://github.com/laurigates/claude-plugins/commit/2c1e9ccff5d48c2b426beac5b3b38cd4576c79a0))

## [1.2.0](https://github.com/laurigates/claude-plugins/compare/github-actions-plugin-v1.1.4...github-actions-plugin-v1.2.0) (2026-02-17)


### Features

* **configure-plugin:** replace detect-secrets with gitleaks for secret scanning ([#668](https://github.com/laurigates/claude-plugins/issues/668)) ([3fc5bbc](https://github.com/laurigates/claude-plugins/commit/3fc5bbc2f8500f30160cc5dfeb5e3d1253ed0a54))


### Bug Fixes

* remove pipe/ls operators from context commands and add CI linting ([#653](https://github.com/laurigates/claude-plugins/issues/653)) ([7a01eef](https://github.com/laurigates/claude-plugins/commit/7a01eef21495ed6243277fbaa88082b7ecabc793))

## [1.2.0](https://github.com/laurigates/claude-plugins/compare/github-actions-plugin-v1.1.4...github-actions-plugin-v1.2.0) (2026-02-16)


### Features

* **configure-plugin:** replace detect-secrets with gitleaks for secret scanning ([#668](https://github.com/laurigates/claude-plugins/issues/668)) ([3fc5bbc](https://github.com/laurigates/claude-plugins/commit/3fc5bbc2f8500f30160cc5dfeb5e3d1253ed0a54))


### Bug Fixes

* remove pipe/ls operators from context commands and add CI linting ([#653](https://github.com/laurigates/claude-plugins/issues/653)) ([7a01eef](https://github.com/laurigates/claude-plugins/commit/7a01eef21495ed6243277fbaa88082b7ecabc793))

## [1.1.5](https://github.com/laurigates/claude-plugins/compare/github-actions-plugin-v1.1.4...github-actions-plugin-v1.1.5) (2026-02-15)


### Bug Fixes

* remove pipe/ls operators from context commands and add CI linting ([#653](https://github.com/laurigates/claude-plugins/issues/653)) ([7a01eef](https://github.com/laurigates/claude-plugins/commit/7a01eef21495ed6243277fbaa88082b7ecabc793))

## [1.1.4](https://github.com/laurigates/claude-plugins/compare/github-actions-plugin-v1.1.3...github-actions-plugin-v1.1.4) (2026-02-14)


### Code Refactoring

* extract detailed content to REFERENCE.md files ([#605](https://github.com/laurigates/claude-plugins/issues/605)) ([7efbd83](https://github.com/laurigates/claude-plugins/commit/7efbd83b9a2b1ef67be702206396ba6d8102684d))

## [1.1.3](https://github.com/laurigates/claude-plugins/compare/github-actions-plugin-v1.1.2...github-actions-plugin-v1.1.3) (2026-02-13)


### Code Refactoring

* **github-actions-plugin:** remove redundant workflow-dev-zen skill ([#603](https://github.com/laurigates/claude-plugins/issues/603)) ([7b3abc3](https://github.com/laurigates/claude-plugins/commit/7b3abc398fe9de4877f4d51845e86a3f3ec55f53))

## [1.1.2](https://github.com/laurigates/claude-plugins/compare/github-actions-plugin-v1.1.1...github-actions-plugin-v1.1.2) (2026-02-12)


### Bug Fixes

* standardize skill name fields to kebab-case across all plugins ([72c0f83](https://github.com/laurigates/claude-plugins/commit/72c0f837a1b07004850c5906a30d619a79098f69))

## [1.1.1](https://github.com/laurigates/claude-plugins/compare/github-actions-plugin-v1.1.0...github-actions-plugin-v1.1.1) (2026-02-06)


### Bug Fixes

* **frontmatter:** resolve 83 validation errors across 75 files ([#434](https://github.com/laurigates/claude-plugins/issues/434)) ([5beb75e](https://github.com/laurigates/claude-plugins/commit/5beb75ed4b2cb0431d060bd7102903495c03c6c5))

## [1.1.0](https://github.com/laurigates/claude-plugins/compare/github-actions-plugin-v1.0.1...github-actions-plugin-v1.1.0) (2026-01-23)


### Features

* add model specification to all skills and commands ([#131](https://github.com/laurigates/claude-plugins/issues/131)) ([81f2961](https://github.com/laurigates/claude-plugins/commit/81f296155b50864b8b1687b9eb18a9c2cbb08791))

## [1.0.1](https://github.com/laurigates/claude-plugins/compare/github-actions-plugin-v1.0.0...github-actions-plugin-v1.0.1) (2025-12-28)


### Bug Fixes

* **github-actions-plugin:** condense verbose skill descriptions ([07d3fa5](https://github.com/laurigates/claude-plugins/commit/07d3fa55daa88cb85061f32455862ccf4529609d))

## [1.0.1](https://github.com/laurigates/claude-plugins/compare/github-actions-plugin-v1.0.0...github-actions-plugin-v1.0.1) (2025-12-28)


### Bug Fixes

* **github-actions-plugin:** condense verbose skill descriptions ([07d3fa5](https://github.com/laurigates/claude-plugins/commit/07d3fa55daa88cb85061f32455862ccf4529609d))
