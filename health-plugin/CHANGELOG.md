# Changelog

## [1.13.0](https://github.com/laurigates/claude-plugins/compare/health-plugin-v1.12.0...health-plugin-v1.13.0) (2026-06-06)


### Features

* **health-plugin:** resolve nested .claude/ when workspace root lacks one ([#1519](https://github.com/laurigates/claude-plugins/issues/1519)) ([47d82e1](https://github.com/laurigates/claude-plugins/commit/47d82e1bdd19d06d7a4642052a4369884d4d60cb)), closes [#1483](https://github.com/laurigates/claude-plugins/issues/1483)

## [1.12.0](https://github.com/laurigates/claude-plugins/compare/health-plugin-v1.11.1...health-plugin-v1.12.0) (2026-06-03)


### Features

* exclude automation PRs + warn on chezmoi-managed registry fixes ([#1498](https://github.com/laurigates/claude-plugins/issues/1498)) ([e302078](https://github.com/laurigates/claude-plugins/commit/e302078be87370f810b38102a36f18a3e98fbf10))

## [1.11.1](https://github.com/laurigates/claude-plugins/compare/health-plugin-v1.11.0...health-plugin-v1.11.1) (2026-06-03)


### Bug Fixes

* resolve actionable open issues (perf + Context-probe robustness) ([#1496](https://github.com/laurigates/claude-plugins/issues/1496)) ([73429d4](https://github.com/laurigates/claude-plugins/commit/73429d4021969914dce60f0f09756759cc44e380))

## [1.11.0](https://github.com/laurigates/claude-plugins/compare/health-plugin-v1.10.1...health-plugin-v1.11.0) (2026-05-24)


### Features

* **hooks-plugin:** add SessionStart drift-nudge architecture ([#1401](https://github.com/laurigates/claude-plugins/issues/1401)) ([47815e2](https://github.com/laurigates/claude-plugins/commit/47815e2035923e9c714142597cd6ed4ad43e9f7e))

## [1.10.1](https://github.com/laurigates/claude-plugins/compare/health-plugin-v1.10.0...health-plugin-v1.10.1) (2026-05-19)


### Bug Fixes

* **health-plugin:** strip CRLF from jq output for Windows compatibility ([#1332](https://github.com/laurigates/claude-plugins/issues/1332)) ([d39b624](https://github.com/laurigates/claude-plugins/commit/d39b6244fa9f0a32a39f0da1f989580d7881d3e9))

## [1.10.0](https://github.com/laurigates/claude-plugins/compare/health-plugin-v1.9.3...health-plugin-v1.10.0) (2026-05-14)


### Features

* **health-plugin:** add --scope=runtime to audit ~/.claude.json bloat ([#1318](https://github.com/laurigates/claude-plugins/issues/1318)) ([0b6d36c](https://github.com/laurigates/claude-plugins/commit/0b6d36c8e20b3e28c4b51e854dd85015c71e0c44))

## [1.9.3](https://github.com/laurigates/claude-plugins/compare/health-plugin-v1.9.2...health-plugin-v1.9.3) (2026-05-14)


### Code Refactoring

* **health-plugin:** tighten skill descriptions for listing budget ([1905692](https://github.com/laurigates/claude-plugins/commit/19056926889d88a0ed4fdd2c3774383e5effb316))

## [1.9.2](https://github.com/laurigates/claude-plugins/compare/health-plugin-v1.9.1...health-plugin-v1.9.2) (2026-05-09)


### Bug Fixes

* **health-plugin:** match marketplace by source.repo, not local key ([#1288](https://github.com/laurigates/claude-plugins/issues/1288)) ([3dc40fb](https://github.com/laurigates/claude-plugins/commit/3dc40fbaf71fdff4969f8b7abad011ee734a624c))

## [1.9.1](https://github.com/laurigates/claude-plugins/compare/health-plugin-v1.9.0...health-plugin-v1.9.1) (2026-05-09)


### Documentation

* trim oversized SKILL.md descriptions across 41 plugins ([#1265](https://github.com/laurigates/claude-plugins/issues/1265)) ([e13d9f4](https://github.com/laurigates/claude-plugins/commit/e13d9f46a010559082c6d5eb61b0cb891843bf97))

## [1.9.0](https://github.com/laurigates/claude-plugins/compare/health-plugin-v1.8.0...health-plugin-v1.9.0) (2026-04-24)


### Features

* **health-plugin:** add skill-audit ([#1139](https://github.com/laurigates/claude-plugins/issues/1139)) ([79b68f1](https://github.com/laurigates/claude-plugins/commit/79b68f1b1cffea81fce29f64eb80d9ff7e236413))

## [1.8.0](https://github.com/laurigates/claude-plugins/compare/health-plugin-v1.7.0...health-plugin-v1.8.0) (2026-04-19)


### Features

* make skills discoverable by Claude's auto-invocation ([#1090](https://github.com/laurigates/claude-plugins/issues/1090)) ([cded1da](https://github.com/laurigates/claude-plugins/commit/cded1da1ebaf350cba1285b58ecadbbaa0eb01f6))

## [1.7.0](https://github.com/laurigates/claude-plugins/compare/health-plugin-v1.6.0...health-plugin-v1.7.0) (2026-04-16)


### Features

* **health-plugin:** refactor /health:check into scope-routed diagnostic command ([#1038](https://github.com/laurigates/claude-plugins/issues/1038)) ([4807628](https://github.com/laurigates/claude-plugins/commit/48076287178e243fb1b6589989730eba766ea241))

## [1.6.0](https://github.com/laurigates/claude-plugins/compare/health-plugin-v1.5.3...health-plugin-v1.6.0) (2026-04-15)


### Features

* **configure-plugin:** add /configure:repo driver, marketplace enrollment, stack-aware permissions ([#1036](https://github.com/laurigates/claude-plugins/issues/1036)) ([2952cea](https://github.com/laurigates/claude-plugins/commit/2952cea59db59c88a2c61d1d87da36598a3516a9))

## [1.5.3](https://github.com/laurigates/claude-plugins/compare/health-plugin-v1.5.2...health-plugin-v1.5.3) (2026-04-12)


### Code Refactoring

* **health-plugin:** extract health-plugins inline commands to standalone scripts ([#1022](https://github.com/laurigates/claude-plugins/issues/1022)) ([b18efb0](https://github.com/laurigates/claude-plugins/commit/b18efb01ca6f47591f054809dbf805e0daa5fcca)), closes [#984](https://github.com/laurigates/claude-plugins/issues/984)

## [1.5.2](https://github.com/laurigates/claude-plugins/compare/health-plugin-v1.5.1...health-plugin-v1.5.2) (2026-04-08)


### Bug Fixes

* **blueprint-plugin:** remove model field from skills and fix invocation syntax ([#1007](https://github.com/laurigates/claude-plugins/issues/1007)) ([42e1e5b](https://github.com/laurigates/claude-plugins/commit/42e1e5b6c73d43e5de4b27cdee16e316de44d4c0))

## [1.5.1](https://github.com/laurigates/claude-plugins/compare/health-plugin-v1.5.0...health-plugin-v1.5.1) (2026-03-30)


### Code Refactoring

* **health-plugin:** extract health-check inline commands to standalone scripts ([#988](https://github.com/laurigates/claude-plugins/issues/988)) ([66640b2](https://github.com/laurigates/claude-plugins/commit/66640b24993f12d039e8c7cea370abd0d2b12f86))

## [1.5.0](https://github.com/laurigates/claude-plugins/compare/health-plugin-v1.4.0...health-plugin-v1.5.0) (2026-03-19)


### Features

* sandbox security regression checks for home-dir and optional file access ([#957](https://github.com/laurigates/claude-plugins/issues/957)) ([b8f99e9](https://github.com/laurigates/claude-plugins/commit/b8f99e93513d1915db98a4aee32585245f3473a4))


### Bug Fixes

* **health-plugin:** remove context commands blocked by sandbox security ([b8f99e9](https://github.com/laurigates/claude-plugins/commit/b8f99e93513d1915db98a4aee32585245f3473a4))

## [1.4.0](https://github.com/laurigates/claude-plugins/compare/health-plugin-v1.3.2...health-plugin-v1.4.0) (2026-02-27)


### Features

* add metadata fields to skill definitions across all plugins ([#828](https://github.com/laurigates/claude-plugins/issues/828)) ([59b3d1f](https://github.com/laurigates/claude-plugins/commit/59b3d1fadd8fd888f95ced8b071fb66cf6f9c825))
* add skill invocation control via user-invocable and disable-model-invocation frontmatter ([59b3d1f](https://github.com/laurigates/claude-plugins/commit/59b3d1fadd8fd888f95ced8b071fb66cf6f9c825))

## [1.3.2](https://github.com/laurigates/claude-plugins/compare/health-plugin-v1.3.1...health-plugin-v1.3.2) (2026-02-25)


### Bug Fixes

* **skills:** add missing args field to 57 skills with argument-hint ([#812](https://github.com/laurigates/claude-plugins/issues/812)) ([f670423](https://github.com/laurigates/claude-plugins/commit/f670423777d3d0e4edf52a1594ad82efaa13793e)), closes [#805](https://github.com/laurigates/claude-plugins/issues/805)

## [1.3.1](https://github.com/laurigates/claude-plugins/compare/health-plugin-v1.3.0...health-plugin-v1.3.1) (2026-02-23)


### Bug Fixes

* remove 2&gt;/dev/null from context commands across all plugins ([#792](https://github.com/laurigates/claude-plugins/issues/792)) ([c72e67e](https://github.com/laurigates/claude-plugins/commit/c72e67ee37e809449f0e6282c48fac01363a59fd))

## [1.3.0](https://github.com/laurigates/claude-plugins/compare/health-plugin-v1.2.0...health-plugin-v1.3.0) (2026-02-18)


### Features

* introduce three-tier model palette (opus/sonnet/haiku) ([#709](https://github.com/laurigates/claude-plugins/issues/709)) ([2c1e9cc](https://github.com/laurigates/claude-plugins/commit/2c1e9ccff5d48c2b426beac5b3b38cd4576c79a0))

## [1.2.0](https://github.com/laurigates/claude-plugins/compare/health-plugin-v1.1.5...health-plugin-v1.2.0) (2026-02-16)


### Features

* **configure-plugin:** replace detect-secrets with gitleaks for secret scanning ([#668](https://github.com/laurigates/claude-plugins/issues/668)) ([3fc5bbc](https://github.com/laurigates/claude-plugins/commit/3fc5bbc2f8500f30160cc5dfeb5e3d1253ed0a54))

## [1.1.5](https://github.com/laurigates/claude-plugins/compare/health-plugin-v1.1.4...health-plugin-v1.1.5) (2026-02-12)


### Bug Fixes

* standardize skill name fields to kebab-case across all plugins ([72c0f83](https://github.com/laurigates/claude-plugins/commit/72c0f837a1b07004850c5906a30d619a79098f69))

## [1.1.4](https://github.com/laurigates/claude-plugins/compare/health-plugin-v1.1.3...health-plugin-v1.1.4) (2026-02-08)


### Bug Fixes

* update skill review dates to trigger release sync ([#489](https://github.com/laurigates/claude-plugins/issues/489)) ([ca20d06](https://github.com/laurigates/claude-plugins/commit/ca20d0667baaa31dfa805c7dc775a1828c515223))

## [1.1.3](https://github.com/laurigates/claude-plugins/compare/health-plugin-v1.1.2...health-plugin-v1.1.3) (2026-02-07)


### Bug Fixes

* **health-plugin:** replace jq context commands with test -f checks ([#480](https://github.com/laurigates/claude-plugins/issues/480)) ([24636d6](https://github.com/laurigates/claude-plugins/commit/24636d69acf1158cee151e647f126cf18c91661d))

## [1.1.2](https://github.com/laurigates/claude-plugins/compare/health-plugin-v1.1.1...health-plugin-v1.1.2) (2026-02-05)


### Bug Fixes

* **health-plugin:** remove blocked shell operators from context commands ([#409](https://github.com/laurigates/claude-plugins/issues/409)) ([3b85bbd](https://github.com/laurigates/claude-plugins/commit/3b85bbdbec166f6a5e30ab7afcf478a64be68546))

## [1.1.1](https://github.com/laurigates/claude-plugins/compare/health-plugin-v1.1.0...health-plugin-v1.1.1) (2026-02-05)


### Bug Fixes

* **health-plugin:** remove shell operators from context commands ([d908b24](https://github.com/laurigates/claude-plugins/commit/d908b24964e528901edd1d267043c62486c3be64))

## [1.1.0](https://github.com/laurigates/claude-plugins/compare/health-plugin-v1.0.0...health-plugin-v1.1.0) (2026-02-05)


### Features

* **health-plugin:** add /health:audit command for plugin relevance auditing ([#381](https://github.com/laurigates/claude-plugins/issues/381)) ([fa9bf80](https://github.com/laurigates/claude-plugins/commit/fa9bf8022c23bb03d2f4753989a4a00a6fbd7673))
