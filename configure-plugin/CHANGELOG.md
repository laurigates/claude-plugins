# Changelog

## [1.14.3](https://github.com/laurigates/claude-plugins/compare/configure-plugin-v1.14.2...configure-plugin-v1.14.3) (2026-03-10)


### Bug Fixes

* **skills:** use find -exec in context commands for missing file resilience ([#919](https://github.com/laurigates/claude-plugins/issues/919)) ([9520d25](https://github.com/laurigates/claude-plugins/commit/9520d250132a293833c3604ade47f5b547de28f1))

## [1.14.2](https://github.com/laurigates/claude-plugins/compare/configure-plugin-v1.14.1...configure-plugin-v1.14.2) (2026-03-05)


### Bug Fixes

* **configure-plugin:** suppress grep errors when .project-standards.yaml is missing ([be9add9](https://github.com/laurigates/claude-plugins/commit/be9add9530ffa161543a0c8c266746b6ffbabdd5))

## [1.14.1](https://github.com/laurigates/claude-plugins/compare/configure-plugin-v1.14.0...configure-plugin-v1.14.1) (2026-03-04)


### Bug Fixes

* haiku model incompatibility with AskUserQuestion tool ([#881](https://github.com/laurigates/claude-plugins/issues/881)) ([c09e400](https://github.com/laurigates/claude-plugins/commit/c09e40031e2eef7fa78640ee1d8327a0f18bbe64))

## [1.14.0](https://github.com/laurigates/claude-plugins/compare/configure-plugin-v1.13.0...configure-plugin-v1.14.0) (2026-03-04)


### Features

* **configure:** add renovate workflow checks and caller template ([#870](https://github.com/laurigates/claude-plugins/issues/870)) ([91146d7](https://github.com/laurigates/claude-plugins/commit/91146d7ff2c5703fddb31bcb0851128a1cc2741f))

## [1.13.0](https://github.com/laurigates/claude-plugins/compare/configure-plugin-v1.12.2...configure-plugin-v1.13.0) (2026-03-04)


### Features

* **configure-plugin:** add Claude auto-fix workflow template ([#872](https://github.com/laurigates/claude-plugins/issues/872)) ([3b983eb](https://github.com/laurigates/claude-plugins/commit/3b983ebd78f34f680a66733700385b8e5f8af96a))

## [1.12.2](https://github.com/laurigates/claude-plugins/compare/configure-plugin-v1.12.1...configure-plugin-v1.12.2) (2026-03-02)


### Documentation

* **rules:** update rules and skills for Claude Code 2.1.50-2.1.63 ([#859](https://github.com/laurigates/claude-plugins/issues/859)) ([6c66021](https://github.com/laurigates/claude-plugins/commit/6c66021fefa205abfc4f575229e3bbb9cdc6263a))

## [1.12.1](https://github.com/laurigates/claude-plugins/compare/configure-plugin-v1.12.0...configure-plugin-v1.12.1) (2026-03-01)


### Bug Fixes

* replace test -f/-d with find in context commands ([#850](https://github.com/laurigates/claude-plugins/issues/850)) ([a236ac8](https://github.com/laurigates/claude-plugins/commit/a236ac80ab81ce37878268b2ad76f7ad6d4aa5fb))

## [1.12.0](https://github.com/laurigates/claude-plugins/compare/configure-plugin-v1.11.3...configure-plugin-v1.12.0) (2026-02-27)


### Features

* add metadata fields to skill definitions across all plugins ([#828](https://github.com/laurigates/claude-plugins/issues/828)) ([59b3d1f](https://github.com/laurigates/claude-plugins/commit/59b3d1fadd8fd888f95ced8b071fb66cf6f9c825))
* add skill invocation control via user-invocable and disable-model-invocation frontmatter ([59b3d1f](https://github.com/laurigates/claude-plugins/commit/59b3d1fadd8fd888f95ced8b071fb66cf6f9c825))

## [1.11.3](https://github.com/laurigates/claude-plugins/compare/configure-plugin-v1.11.2...configure-plugin-v1.11.3) (2026-02-26)


### Bug Fixes

* **scripts:** enhance context command linter with stderr safety checks and fix violations ([#819](https://github.com/laurigates/claude-plugins/issues/819)) ([2975b9b](https://github.com/laurigates/claude-plugins/commit/2975b9b0bf6698bdecf627e3d28bad06fde03cd1))

## [1.11.2](https://github.com/laurigates/claude-plugins/compare/configure-plugin-v1.11.1...configure-plugin-v1.11.2) (2026-02-25)


### Bug Fixes

* **configure-plugin:** extract go-feature-flag SKILL.md to under 500 lines ([#810](https://github.com/laurigates/claude-plugins/issues/810)) ([80ba44f](https://github.com/laurigates/claude-plugins/commit/80ba44f6f932cca6a307353ae7e082a8c9484cb9)), closes [#802](https://github.com/laurigates/claude-plugins/issues/802)
* **skills:** add missing args field to 57 skills with argument-hint ([#812](https://github.com/laurigates/claude-plugins/issues/812)) ([f670423](https://github.com/laurigates/claude-plugins/commit/f670423777d3d0e4edf52a1594ad82efaa13793e)), closes [#805](https://github.com/laurigates/claude-plugins/issues/805)

## [1.11.1](https://github.com/laurigates/claude-plugins/compare/configure-plugin-v1.11.0...configure-plugin-v1.11.1) (2026-02-25)


### Bug Fixes

* replace git remote get-url with git remote -v for verbose output ([#804](https://github.com/laurigates/claude-plugins/issues/804)) ([e39407a](https://github.com/laurigates/claude-plugins/commit/e39407a366d2d0ba431df0f456074b847073eea8))
* **skills:** replace git remote get-url origin with git remote -v in context commands ([e39407a](https://github.com/laurigates/claude-plugins/commit/e39407a366d2d0ba431df0f456074b847073eea8))

## [1.11.0](https://github.com/laurigates/claude-plugins/compare/configure-plugin-v1.10.1...configure-plugin-v1.11.0) (2026-02-25)


### Features

* **configure-plugin:** add configure-web-session skill for Claude Code on the web ([#801](https://github.com/laurigates/claude-plugins/issues/801)) ([9f1f0fd](https://github.com/laurigates/claude-plugins/commit/9f1f0fd3ea4587fe6642199046f79d037f5a9431))

## [1.10.1](https://github.com/laurigates/claude-plugins/compare/configure-plugin-v1.10.0...configure-plugin-v1.10.1) (2026-02-23)


### Bug Fixes

* remove 2&gt;/dev/null from context commands across all plugins ([#792](https://github.com/laurigates/claude-plugins/issues/792)) ([c72e67e](https://github.com/laurigates/claude-plugins/commit/c72e67ee37e809449f0e6282c48fac01363a59fd))

## [1.10.0](https://github.com/laurigates/claude-plugins/compare/configure-plugin-v1.9.0...configure-plugin-v1.10.0) (2026-02-21)


### Features

* **configure-plugin:** add config-sync skill for cross-repo tooling propagation ([#775](https://github.com/laurigates/claude-plugins/issues/775)) ([9cc1502](https://github.com/laurigates/claude-plugins/commit/9cc1502aeef2fa90c6909881d2a745c337148c85))

## [1.9.0](https://github.com/laurigates/claude-plugins/compare/configure-plugin-v1.8.0...configure-plugin-v1.9.0) (2026-02-18)


### Features

* introduce three-tier model palette (opus/sonnet/haiku) ([#709](https://github.com/laurigates/claude-plugins/issues/709)) ([2c1e9cc](https://github.com/laurigates/claude-plugins/commit/2c1e9ccff5d48c2b426beac5b3b38cd4576c79a0))

## [1.8.0](https://github.com/laurigates/claude-plugins/compare/configure-plugin-v1.7.3...configure-plugin-v1.8.0) (2026-02-16)


### Features

* **configure-plugin:** replace detect-secrets with gitleaks for secret scanning ([#668](https://github.com/laurigates/claude-plugins/issues/668)) ([3fc5bbc](https://github.com/laurigates/claude-plugins/commit/3fc5bbc2f8500f30160cc5dfeb5e3d1253ed0a54))

## [1.8.0](https://github.com/laurigates/claude-plugins/compare/configure-plugin-v1.7.3...configure-plugin-v1.8.0) (2026-02-16)


### Features

* **configure-plugin:** replace detect-secrets with gitleaks for secret scanning ([#668](https://github.com/laurigates/claude-plugins/issues/668)) ([3fc5bbc](https://github.com/laurigates/claude-plugins/commit/3fc5bbc2f8500f30160cc5dfeb5e3d1253ed0a54))

## [1.7.3](https://github.com/laurigates/claude-plugins/compare/configure-plugin-v1.7.2...configure-plugin-v1.7.3) (2026-02-15)


### Bug Fixes

* remove pipe/ls operators from context commands and add CI linting ([#653](https://github.com/laurigates/claude-plugins/issues/653)) ([7a01eef](https://github.com/laurigates/claude-plugins/commit/7a01eef21495ed6243277fbaa88082b7ecabc793))

## [1.7.2](https://github.com/laurigates/claude-plugins/compare/configure-plugin-v1.7.1...configure-plugin-v1.7.2) (2026-02-15)


### Bug Fixes

* replace broken context command patterns in skill files ([#644](https://github.com/laurigates/claude-plugins/issues/644)) ([440ba34](https://github.com/laurigates/claude-plugins/commit/440ba347bcc73a0512f74975cfd6b4af9fe8566e))

## [1.7.1](https://github.com/laurigates/claude-plugins/compare/configure-plugin-v1.7.0...configure-plugin-v1.7.1) (2026-02-13)


### Documentation

* improve skill documentation, standards, and context patterns ([#599](https://github.com/laurigates/claude-plugins/issues/599)) ([4a351dc](https://github.com/laurigates/claude-plugins/commit/4a351dcfac7229dd26586cdf7c8cbd51fec451d2))
* **skills:** improve documentation, standards, and context patterns ([4a351dc](https://github.com/laurigates/claude-plugins/commit/4a351dcfac7229dd26586cdf7c8cbd51fec451d2)), closes [#596](https://github.com/laurigates/claude-plugins/issues/596)

## [1.7.0](https://github.com/laurigates/claude-plugins/compare/configure-plugin-v1.6.6...configure-plugin-v1.7.0) (2026-02-11)


### Features

* add required quality sections to refactored skills ([#544](https://github.com/laurigates/claude-plugins/issues/544)) ([342af54](https://github.com/laurigates/claude-plugins/commit/342af54af0f81fa50d239d06b32b353ddb7335fc))

## [1.7.0](https://github.com/laurigates/claude-plugins/compare/configure-plugin-v1.6.6...configure-plugin-v1.7.0) (2026-02-11)


### Features

* add required quality sections to refactored skills ([#544](https://github.com/laurigates/claude-plugins/issues/544)) ([342af54](https://github.com/laurigates/claude-plugins/commit/342af54af0f81fa50d239d06b32b353ddb7335fc))

## [1.7.0](https://github.com/laurigates/claude-plugins/compare/configure-plugin-v1.6.6...configure-plugin-v1.7.0) (2026-02-11)


### Features

* add required quality sections to refactored skills ([#544](https://github.com/laurigates/claude-plugins/issues/544)) ([342af54](https://github.com/laurigates/claude-plugins/commit/342af54af0f81fa50d239d06b32b353ddb7335fc))

## [1.6.6](https://github.com/laurigates/claude-plugins/compare/configure-plugin-v1.6.5...configure-plugin-v1.6.6) (2026-02-09)


### Bug Fixes

* **configure-plugin:** add cclsp server configuration to configure-mcp skill ([c9bfcd0](https://github.com/laurigates/claude-plugins/commit/c9bfcd0fc81a75206ec593ccbf7c1b01df8e4df3))

## [1.6.5](https://github.com/laurigates/claude-plugins/compare/configure-plugin-v1.6.4...configure-plugin-v1.6.5) (2026-02-08)


### Code Refactoring

* reframe negative guidance as positive guidance across skills ([7e755ee](https://github.com/laurigates/claude-plugins/commit/7e755ee1c32c39c124f3204a0d0a8d1d770e1573))

## [1.6.4](https://github.com/laurigates/claude-plugins/compare/configure-plugin-v1.6.3...configure-plugin-v1.6.4) (2026-02-08)


### Bug Fixes

* update skill review dates to trigger release sync ([#489](https://github.com/laurigates/claude-plugins/issues/489)) ([ca20d06](https://github.com/laurigates/claude-plugins/commit/ca20d0667baaa31dfa805c7dc775a1828c515223))

## [1.6.3](https://github.com/laurigates/claude-plugins/compare/configure-plugin-v1.6.2...configure-plugin-v1.6.3) (2026-02-06)


### Bug Fixes

* **frontmatter:** resolve 83 validation errors across 75 files ([#434](https://github.com/laurigates/claude-plugins/issues/434)) ([5beb75e](https://github.com/laurigates/claude-plugins/commit/5beb75ed4b2cb0431d060bd7102903495c03c6c5))

## [1.6.3](https://github.com/laurigates/claude-plugins/compare/configure-plugin-v1.6.2...configure-plugin-v1.6.3) (2026-02-06)


### Bug Fixes

* **frontmatter:** resolve 83 validation errors across 75 files ([#434](https://github.com/laurigates/claude-plugins/issues/434)) ([5beb75e](https://github.com/laurigates/claude-plugins/commit/5beb75ed4b2cb0431d060bd7102903495c03c6c5))

## [1.6.2](https://github.com/laurigates/claude-plugins/compare/configure-plugin-v1.6.1...configure-plugin-v1.6.2) (2026-02-05)


### Bug Fixes

* replace ls -la with find in context commands to prevent false errors ([de8ce95](https://github.com/laurigates/claude-plugins/commit/de8ce954b4095b6c46e9326588b3fe632e87bffb))

## [1.6.2](https://github.com/laurigates/claude-plugins/compare/configure-plugin-v1.6.1...configure-plugin-v1.6.2) (2026-02-05)


### Bug Fixes

* replace ls -la with find in context commands to prevent false errors ([de8ce95](https://github.com/laurigates/claude-plugins/commit/de8ce954b4095b6c46e9326588b3fe632e87bffb))

## [1.6.1](https://github.com/laurigates/claude-plugins/compare/configure-plugin-v1.6.0...configure-plugin-v1.6.1) (2026-02-04)


### Documentation

* **rules, settings:** refactor to emphasize positive guidance patterns ([#360](https://github.com/laurigates/claude-plugins/issues/360)) ([a4ea8a8](https://github.com/laurigates/claude-plugins/commit/a4ea8a8990e2a40bb2331855db5fd68631c14d7e))

## [1.6.0](https://github.com/laurigates/claude-plugins/compare/configure-plugin-v1.5.1...configure-plugin-v1.6.0) (2026-02-03)


### Features

* **configure-plugin:** add ArgoCD Image Updater auto-merge workflow ([8624928](https://github.com/laurigates/claude-plugins/commit/86249282d89555fe4b90c08a56f3be2bcf098220))

## [1.5.1](https://github.com/laurigates/claude-plugins/compare/configure-plugin-v1.5.0...configure-plugin-v1.5.1) (2026-02-03)


### Bug Fixes

* remove shell operators from context commands across all plugins ([#316](https://github.com/laurigates/claude-plugins/issues/316)) ([ecabe72](https://github.com/laurigates/claude-plugins/commit/ecabe72ebd100af1219f97012832d8ba500965b5))

## [1.5.0](https://github.com/laurigates/claude-plugins/compare/configure-plugin-v1.4.2...configure-plugin-v1.5.0) (2026-02-03)


### Features

* **configure-plugin:** add reusable-workflows installer command ([#310](https://github.com/laurigates/claude-plugins/issues/310)) ([839a63b](https://github.com/laurigates/claude-plugins/commit/839a63b30f3a27cf862fcff86adcb0d6f4492e6d))


### Bug Fixes

* **configure-plugin:** remove shell operators from context commands ([18baf15](https://github.com/laurigates/claude-plugins/commit/18baf158a12f821e3f73a7b03c29e4d4b39f527c))

## [1.4.2](https://github.com/laurigates/claude-plugins/compare/configure-plugin-v1.4.1...configure-plugin-v1.4.2) (2026-01-25)


### Bug Fixes

* rename marketplace from 'lgates-claude-plugins' to 'laurigates-plugins' ([#195](https://github.com/laurigates/claude-plugins/issues/195)) ([4310935](https://github.com/laurigates/claude-plugins/commit/43109350d121f9c0749af86461daef9849eea133))

## [1.4.2](https://github.com/laurigates/claude-plugins/compare/configure-plugin-v1.4.1...configure-plugin-v1.4.2) (2026-01-25)


### Bug Fixes

* rename marketplace from 'lgates-claude-plugins' to 'laurigates-plugins' ([#195](https://github.com/laurigates/claude-plugins/issues/195)) ([4310935](https://github.com/laurigates/claude-plugins/commit/43109350d121f9c0749af86461daef9849eea133))

## [1.4.1](https://github.com/laurigates/claude-plugins/compare/configure-plugin-v1.4.0...configure-plugin-v1.4.1) (2026-01-23)


### Bug Fixes

* **configure-plugin:** use CLAUDE_CODE_OAUTH_TOKEN in configure:claude-plugins command ([54f43a9](https://github.com/laurigates/claude-plugins/commit/54f43a9962532e3b87e88237111e5dba3f8adbc2))

## [1.4.0](https://github.com/laurigates/claude-plugins/compare/configure-plugin-v1.3.0...configure-plugin-v1.4.0) (2026-01-23)


### Features

* add model specification to all skills and commands ([#131](https://github.com/laurigates/claude-plugins/issues/131)) ([81f2961](https://github.com/laurigates/claude-plugins/commit/81f296155b50864b8b1687b9eb18a9c2cbb08791))
* **configure-plugin:** add /configure:claude-plugins command ([#158](https://github.com/laurigates/claude-plugins/issues/158)) ([e932de3](https://github.com/laurigates/claude-plugins/commit/e932de30983525ade0609ec85a331d183c28af54))

## [1.3.0](https://github.com/laurigates/claude-plugins/compare/configure-plugin-v1.2.0...configure-plugin-v1.3.0) (2026-01-21)


### Features

* implement Claude Code 2.1.7 changelog review updates (issue [#78](https://github.com/laurigates/claude-plugins/issues/78)) ([#112](https://github.com/laurigates/claude-plugins/issues/112)) ([e28d8de](https://github.com/laurigates/claude-plugins/commit/e28d8deec41d3e5070861a3f1c37e9c43f452cb4))

## [1.2.0](https://github.com/laurigates/claude-plugins/compare/configure-plugin-v1.1.1...configure-plugin-v1.2.0) (2026-01-19)


### Features

* **container:** add OCI container labels support for GHCR integration ([#104](https://github.com/laurigates/claude-plugins/issues/104)) ([6fb88b2](https://github.com/laurigates/claude-plugins/commit/6fb88b278571ac76a11a40ae55d648b6f4320c1a))

## [1.1.1](https://github.com/laurigates/claude-plugins/compare/configure-plugin-v1.1.0...configure-plugin-v1.1.1) (2026-01-09)


### Bug Fixes

* sync plugin.json versions to match release-please manifest ([1ac44e1](https://github.com/laurigates/claude-plugins/commit/1ac44e1240eed27eb3f829edaaac9bc863634d89))

## [1.1.0](https://github.com/laurigates/claude-plugins/compare/configure-plugin-v1.0.0...configure-plugin-v1.1.0) (2025-12-28)


### Features

* add justfile support to configure and tools plugins ([781bebf](https://github.com/laurigates/claude-plugins/commit/781bebfab3673c02ea3c704048cd22b9923b0890))
* **configure-plugin:** add interactive component selection command ([3ec62df](https://github.com/laurigates/claude-plugins/commit/3ec62df60e93713b70838522aca62938a2049bcd))
* **configure-plugin:** add memory profiling configure command ([7c664b5](https://github.com/laurigates/claude-plugins/commit/7c664b59557e6a730342f294219fef0f31a0a23d))
* **configure-plugin:** add README.md configure command ([d2243ce](https://github.com/laurigates/claude-plugins/commit/d2243ce318a23c4e410f6103692c11a26dffab2c))
