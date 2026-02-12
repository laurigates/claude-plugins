# Changelog

## [2.13.2](https://github.com/laurigates/claude-plugins/compare/git-plugin-v2.13.1...git-plugin-v2.13.2) (2026-02-12)


### Documentation

* **git-plugin:** remove exclusive git permissions claims from git-ops agent ([0f92846](https://github.com/laurigates/claude-plugins/commit/0f928466543e7a302c11ff9d51ae481c8bf887eb))

## [2.13.1](https://github.com/laurigates/claude-plugins/compare/git-plugin-v2.13.0...git-plugin-v2.13.1) (2026-02-12)


### Bug Fixes

* standardize skill name fields to kebab-case across all plugins ([72c0f83](https://github.com/laurigates/claude-plugins/commit/72c0f837a1b07004850c5906a30d619a79098f69))

## [2.13.0](https://github.com/laurigates/claude-plugins/compare/git-plugin-v2.12.4...git-plugin-v2.13.0) (2026-02-10)


### Features

* **git-plugin:** use ./worktrees/ directory for agent worktree workflows ([a97db86](https://github.com/laurigates/claude-plugins/commit/a97db8613d879db4c06cefc6f94edcfca95f9043))

### Migration Notes

**git-worktree-agent-workflow**: Worktree paths have changed from `../project-wt-issue-N` to `./worktrees/issue-N`. If you're using the worktree skill from v2.11.0-v2.12.4, existing worktrees will need to be recreated with the new path structure. This eliminates the need for `additionalDirectories` configuration. See the [skill documentation](git-plugin/skills/git-worktree-agent-workflow/SKILL.md) for details.

## [2.12.4](https://github.com/laurigates/claude-plugins/compare/git-plugin-v2.12.3...git-plugin-v2.12.4) (2026-02-08)


### Code Refactoring

* reframe negative guidance as positive guidance across skills ([7e755ee](https://github.com/laurigates/claude-plugins/commit/7e755ee1c32c39c124f3204a0d0a8d1d770e1573))

## [2.12.3](https://github.com/laurigates/claude-plugins/compare/git-plugin-v2.12.2...git-plugin-v2.12.3) (2026-02-07)


### Bug Fixes

* **frontmatter:** resolve 83 validation errors across 75 files ([#434](https://github.com/laurigates/claude-plugins/issues/434)) ([5beb75e](https://github.com/laurigates/claude-plugins/commit/5beb75ed4b2cb0431d060bd7102903495c03c6c5))

## [2.12.3](https://github.com/laurigates/claude-plugins/compare/git-plugin-v2.12.2...git-plugin-v2.12.3) (2026-02-07)


### Bug Fixes

* **frontmatter:** resolve 83 validation errors across 75 files ([#434](https://github.com/laurigates/claude-plugins/issues/434)) ([5beb75e](https://github.com/laurigates/claude-plugins/commit/5beb75ed4b2cb0431d060bd7102903495c03c6c5))

## [2.12.3](https://github.com/laurigates/claude-plugins/compare/git-plugin-v2.12.2...git-plugin-v2.12.3) (2026-02-06)


### Bug Fixes

* **frontmatter:** resolve 83 validation errors across 75 files ([#434](https://github.com/laurigates/claude-plugins/issues/434)) ([5beb75e](https://github.com/laurigates/claude-plugins/commit/5beb75ed4b2cb0431d060bd7102903495c03c6c5))

## [2.12.2](https://github.com/laurigates/claude-plugins/compare/git-plugin-v2.12.1...git-plugin-v2.12.2) (2026-02-06)


### Bug Fixes

* **git-ops:** enable git write permissions and clarify configuration ([#430](https://github.com/laurigates/claude-plugins/issues/430)) ([3448890](https://github.com/laurigates/claude-plugins/commit/3448890b00d1feb40a4d6e86ae5850d4cdb97b90))

## [2.12.1](https://github.com/laurigates/claude-plugins/compare/git-plugin-v2.12.0...git-plugin-v2.12.1) (2026-02-06)


### Documentation

* **git-plugin:** document PR check watching workflow ([24116de](https://github.com/laurigates/claude-plugins/commit/24116de12541b7af7677d5e1ed195628bf4599eb))
* improve skill documentation with decision guides and references ([#426](https://github.com/laurigates/claude-plugins/issues/426)) ([24116de](https://github.com/laurigates/claude-plugins/commit/24116de12541b7af7677d5e1ed195628bf4599eb))

## [2.12.0](https://github.com/laurigates/claude-plugins/compare/git-plugin-v2.11.3...git-plugin-v2.12.0) (2026-02-05)


### Features

* **git-plugin,code-quality-plugin,project-plugin:** add supporting scripts to skills ([#206](https://github.com/laurigates/claude-plugins/issues/206)) ([0b33d50](https://github.com/laurigates/claude-plugins/commit/0b33d502e18584b264c7c4a99dddda54dc573d08))
* **git-plugin:** add git-branch-naming skill ([#244](https://github.com/laurigates/claude-plugins/issues/244)) ([c9e60cc](https://github.com/laurigates/claude-plugins/commit/c9e60ccba19099545064a18ec85c37e2950cd375))
* **git-plugin:** add git-log-documentation skill and /git:derive-docs command ([#187](https://github.com/laurigates/claude-plugins/issues/187)) ([9cc4a0f](https://github.com/laurigates/claude-plugins/commit/9cc4a0fd22656d2316f179260f70089d69a2fbff))
* **git-plugin:** add git-worktree-agent-workflow skill ([#298](https://github.com/laurigates/claude-plugins/issues/298)) ([f225ee9](https://github.com/laurigates/claude-plugins/commit/f225ee9c301a978b008eea2c7a4340f4a4e8e3e3))
* **git-plugin:** add github-issue-writing and github-pr-title skills ([#246](https://github.com/laurigates/claude-plugins/issues/246)) ([9590acb](https://github.com/laurigates/claude-plugins/commit/9590acb7c36819c5735a7cdbf974617627594e94))
* **git-plugin:** add pr-feedback command for reviewing and addressing PR comments ([e343b9c](https://github.com/laurigates/claude-plugins/commit/e343b9cb2c2c71732fb97a50087af70be0de1e84))
* **git-plugin:** auto-create PR from main without local branch checkout ([#175](https://github.com/laurigates/claude-plugins/issues/175)) ([ca7a7bb](https://github.com/laurigates/claude-plugins/commit/ca7a7bb7d337dfebd3d5a2a3094896af3453399e))


### Bug Fixes

* **agent-patterns-plugin:** block git writes for parallel agents to prevent conflicts ([#299](https://github.com/laurigates/claude-plugins/issues/299)) ([a2c2ce0](https://github.com/laurigates/claude-plugins/commit/a2c2ce07d67ead9b30470b398777be355672281b))
* enforce granular Bash permissions across all plugins ([#267](https://github.com/laurigates/claude-plugins/issues/267)) ([afeb507](https://github.com/laurigates/claude-plugins/commit/afeb50754838c2923807c8f2a248b3798fd4281c))
* **git-plugin:** add guidance to avoid unnecessary -C flag ([#263](https://github.com/laurigates/claude-plugins/issues/263)) ([35b8950](https://github.com/laurigates/claude-plugins/commit/35b8950b992be58ebd7eb4503f1603219a3df8ef))
* **git-plugin:** remove backticks from status codes to prevent parsing bug ([373023c](https://github.com/laurigates/claude-plugins/commit/373023ce8a292211890240612785e41641563c4d))
* remove shell operators from context commands across all plugins ([#316](https://github.com/laurigates/claude-plugins/issues/316)) ([ecabe72](https://github.com/laurigates/claude-plugins/commit/ecabe72ebd100af1219f97012832d8ba500965b5))
* remove shell operators from context commands in multiple plugins ([#326](https://github.com/laurigates/claude-plugins/issues/326)) ([b028f73](https://github.com/laurigates/claude-plugins/commit/b028f7385f66f8f063a95874840c51e553694205))
* rename marketplace from 'lgates-claude-plugins' to 'laurigates-plugins' ([#195](https://github.com/laurigates/claude-plugins/issues/195)) ([4310935](https://github.com/laurigates/claude-plugins/commit/43109350d121f9c0749af86461daef9849eea133))

## [2.11.3](https://github.com/laurigates/claude-plugins/compare/git-plugin-v2.11.2...git-plugin-v2.11.3) (2026-02-05)


### Bug Fixes

* **git-plugin:** remove backticks from status codes to prevent parsing bug ([373023c](https://github.com/laurigates/claude-plugins/commit/373023ce8a292211890240612785e41641563c4d))

## [2.11.2](https://github.com/laurigates/claude-plugins/compare/git-plugin-v2.11.1...git-plugin-v2.11.2) (2026-02-03)


### Bug Fixes

* remove shell operators from context commands in multiple plugins ([#326](https://github.com/laurigates/claude-plugins/issues/326)) ([b028f73](https://github.com/laurigates/claude-plugins/commit/b028f7385f66f8f063a95874840c51e553694205))

## [2.11.1](https://github.com/laurigates/claude-plugins/compare/git-plugin-v2.11.0...git-plugin-v2.11.1) (2026-02-03)


### Bug Fixes

* remove shell operators from context commands across all plugins ([#316](https://github.com/laurigates/claude-plugins/issues/316)) ([ecabe72](https://github.com/laurigates/claude-plugins/commit/ecabe72ebd100af1219f97012832d8ba500965b5))

## [2.11.0](https://github.com/laurigates/claude-plugins/compare/git-plugin-v2.10.2...git-plugin-v2.11.0) (2026-02-02)


### Features

* **git-plugin:** add git-worktree-agent-workflow skill ([#298](https://github.com/laurigates/claude-plugins/issues/298)) ([f225ee9](https://github.com/laurigates/claude-plugins/commit/f225ee9c301a978b008eea2c7a4340f4a4e8e3e3))


### Bug Fixes

* **agent-patterns-plugin:** block git writes for parallel agents to prevent conflicts ([#299](https://github.com/laurigates/claude-plugins/issues/299)) ([a2c2ce0](https://github.com/laurigates/claude-plugins/commit/a2c2ce07d67ead9b30470b398777be355672281b))

## [2.11.0](https://github.com/laurigates/claude-plugins/compare/git-plugin-v2.10.2...git-plugin-v2.11.0) (2026-02-02)


### Features

* **git-plugin:** add git-worktree-agent-workflow skill ([#298](https://github.com/laurigates/claude-plugins/issues/298)) ([f225ee9](https://github.com/laurigates/claude-plugins/commit/f225ee9c301a978b008eea2c7a4340f4a4e8e3e3))


### Bug Fixes

* **agent-patterns-plugin:** block git writes for parallel agents to prevent conflicts ([#299](https://github.com/laurigates/claude-plugins/issues/299)) ([a2c2ce0](https://github.com/laurigates/claude-plugins/commit/a2c2ce07d67ead9b30470b398777be355672281b))

## [2.10.2](https://github.com/laurigates/claude-plugins/compare/git-plugin-v2.10.1...git-plugin-v2.10.2) (2026-02-01)


### Bug Fixes

* enforce granular Bash permissions across all plugins ([#267](https://github.com/laurigates/claude-plugins/issues/267)) ([afeb507](https://github.com/laurigates/claude-plugins/commit/afeb50754838c2923807c8f2a248b3798fd4281c))

## [2.10.2](https://github.com/laurigates/claude-plugins/compare/git-plugin-v2.10.1...git-plugin-v2.10.2) (2026-02-01)


### Bug Fixes

* enforce granular Bash permissions across all plugins ([#267](https://github.com/laurigates/claude-plugins/issues/267)) ([afeb507](https://github.com/laurigates/claude-plugins/commit/afeb50754838c2923807c8f2a248b3798fd4281c))

## [2.10.1](https://github.com/laurigates/claude-plugins/compare/git-plugin-v2.10.0...git-plugin-v2.10.1) (2026-02-01)


### Bug Fixes

* **git-plugin:** add guidance to avoid unnecessary -C flag ([#263](https://github.com/laurigates/claude-plugins/issues/263)) ([35b8950](https://github.com/laurigates/claude-plugins/commit/35b8950b992be58ebd7eb4503f1603219a3df8ef))

## [2.10.0](https://github.com/laurigates/claude-plugins/compare/git-plugin-v2.9.0...git-plugin-v2.10.0) (2026-01-30)


### Features

* **git-plugin:** add pr-feedback command for reviewing and addressing PR comments ([e343b9c](https://github.com/laurigates/claude-plugins/commit/e343b9cb2c2c71732fb97a50087af70be0de1e84))

## [2.9.0](https://github.com/laurigates/claude-plugins/compare/git-plugin-v2.8.0...git-plugin-v2.9.0) (2026-01-30)


### Features

* **git-plugin:** add github-issue-writing and github-pr-title skills ([#246](https://github.com/laurigates/claude-plugins/issues/246)) ([9590acb](https://github.com/laurigates/claude-plugins/commit/9590acb7c36819c5735a7cdbf974617627594e94))

## [2.8.0](https://github.com/laurigates/claude-plugins/compare/git-plugin-v2.7.0...git-plugin-v2.8.0) (2026-01-30)


### Features

* **git-plugin:** add git-branch-naming skill ([#244](https://github.com/laurigates/claude-plugins/issues/244)) ([c9e60cc](https://github.com/laurigates/claude-plugins/commit/c9e60ccba19099545064a18ec85c37e2950cd375))

## [2.7.0](https://github.com/laurigates/claude-plugins/compare/git-plugin-v2.6.0...git-plugin-v2.7.0) (2026-01-24)


### Features

* **git-plugin,code-quality-plugin,project-plugin:** add supporting scripts to skills ([#206](https://github.com/laurigates/claude-plugins/issues/206)) ([0b33d50](https://github.com/laurigates/claude-plugins/commit/0b33d502e18584b264c7c4a99dddda54dc573d08))


### Bug Fixes

* rename marketplace from 'lgates-claude-plugins' to 'laurigates-plugins' ([#195](https://github.com/laurigates/claude-plugins/issues/195)) ([4310935](https://github.com/laurigates/claude-plugins/commit/43109350d121f9c0749af86461daef9849eea133))

## [2.6.0](https://github.com/laurigates/claude-plugins/compare/git-plugin-v2.5.0...git-plugin-v2.6.0) (2026-01-24)


### Features

* **git-plugin:** add git-log-documentation skill and /git:derive-docs command ([#187](https://github.com/laurigates/claude-plugins/issues/187)) ([9cc4a0f](https://github.com/laurigates/claude-plugins/commit/9cc4a0fd22656d2316f179260f70089d69a2fbff))

## [2.5.0](https://github.com/laurigates/claude-plugins/compare/git-plugin-v2.4.0...git-plugin-v2.5.0) (2026-01-23)


### Features

* **git-plugin:** auto-create PR from main without local branch checkout ([#175](https://github.com/laurigates/claude-plugins/issues/175)) ([ca7a7bb](https://github.com/laurigates/claude-plugins/commit/ca7a7bb7d337dfebd3d5a2a3094896af3453399e))

## [2.4.0](https://github.com/laurigates/claude-plugins/compare/git-plugin-v2.3.0...git-plugin-v2.4.0) (2026-01-23)


### Features

* add model specification to all skills and commands ([#131](https://github.com/laurigates/claude-plugins/issues/131)) ([81f2961](https://github.com/laurigates/claude-plugins/commit/81f296155b50864b8b1687b9eb18a9c2cbb08791))

## [2.3.0](https://github.com/laurigates/claude-plugins/compare/git-plugin-v2.2.1...git-plugin-v2.3.0) (2026-01-21)


### Features

* **git-plugin:** add layered composable git workflow skills ([dd0b909](https://github.com/laurigates/claude-plugins/commit/dd0b909a907dabe8eae4b97da42db490fc4d30cc))

## [2.2.1](https://github.com/laurigates/claude-plugins/compare/git-plugin-v2.2.0...git-plugin-v2.2.1) (2026-01-18)


### Bug Fixes

* **git-plugin:** remove jq expressions with pipes from context commands ([#99](https://github.com/laurigates/claude-plugins/issues/99)) ([e96a37c](https://github.com/laurigates/claude-plugins/commit/e96a37c27f2d6dac0da5a2ceeba0f9a26dcf5a20))

## [2.2.0](https://github.com/laurigates/claude-plugins/compare/git-plugin-v2.1.1...git-plugin-v2.2.0) (2026-01-17)


### Features

* **git-plugin:** add advanced rebase patterns section ([#91](https://github.com/laurigates/claude-plugins/issues/91)) ([798c65e](https://github.com/laurigates/claude-plugins/commit/798c65e6b4c713e60c7032e36a9d392b51ca3700))

## [2.1.1](https://github.com/laurigates/claude-plugins/compare/git-plugin-v2.1.0...git-plugin-v2.1.1) (2026-01-17)


### Bug Fixes

* **git-plugin:** remove piped commands from context sections ([#89](https://github.com/laurigates/claude-plugins/issues/89)) ([f5215e9](https://github.com/laurigates/claude-plugins/commit/f5215e9bea6ffd1a5fb12b485c1b55e0cebf620c))

## [2.1.0](https://github.com/laurigates/claude-plugins/compare/git-plugin-v2.0.0...git-plugin-v2.1.0) (2026-01-16)


### Features

* **git-plugin:** add gh-workflow-monitoring skill ([97bee1b](https://github.com/laurigates/claude-plugins/commit/97bee1ba517e0c021e00183be5ffe35521f7e138))

## [2.0.0](https://github.com/laurigates/claude-plugins/compare/git-plugin-v1.3.0...git-plugin-v2.0.0) (2026-01-16)


### ⚠ BREAKING CHANGES

* **git-plugin:** /git:issues is removed, use /git:issue instead

### Features

* **git-plugin:** add agentic optimizations with granular permissions ([e5e3ddb](https://github.com/laurigates/claude-plugins/commit/e5e3ddb6b74c64fdf3b1644d9eeb19e6220f73e6))
* **git-plugin:** unify /git:issue and /git:issues into single command ([c3b00ec](https://github.com/laurigates/claude-plugins/commit/c3b00ec7b5ab73f9452f5eb63652a9004da02cd4))

## [1.3.0](https://github.com/laurigates/claude-plugins/compare/git-plugin-v1.2.0...git-plugin-v1.3.0) (2026-01-15)


### Features

* **git-plugin:** add automatic GitHub issue detection for commits ([#82](https://github.com/laurigates/claude-plugins/issues/82)) ([09be6fb](https://github.com/laurigates/claude-plugins/commit/09be6fb0d1428825f596d6319103abb06d0c3fad))

## [1.2.0](https://github.com/laurigates/claude-plugins/compare/git-plugin-v1.1.2...git-plugin-v1.2.0) (2026-01-09)


### Features

* **git-plugin:** add release-please-pr-workflow skill ([376af27](https://github.com/laurigates/claude-plugins/commit/376af27cec41dac0769f9eaab182ba809355cd96))

## [1.1.2](https://github.com/laurigates/claude-plugins/compare/git-plugin-v1.1.1...git-plugin-v1.1.2) (2026-01-09)


### Bug Fixes

* **git-plugin:** handle missing git remote in command context ([#50](https://github.com/laurigates/claude-plugins/issues/50)) ([3ea701f](https://github.com/laurigates/claude-plugins/commit/3ea701f60537146e92808c63dfd90db8be2c7ae9))

## [1.1.2](https://github.com/laurigates/claude-plugins/compare/git-plugin-v1.1.1...git-plugin-v1.1.2) (2026-01-09)


### Bug Fixes

* **git-plugin:** handle missing git remote in command context ([#50](https://github.com/laurigates/claude-plugins/issues/50)) ([3ea701f](https://github.com/laurigates/claude-plugins/commit/3ea701f60537146e92808c63dfd90db8be2c7ae9))

## [1.1.1](https://github.com/laurigates/claude-plugins/compare/git-plugin-v1.1.0...git-plugin-v1.1.1) (2025-12-28)


### Bug Fixes

* use JSON updater format for extra-files in release-please config ([ec1fac9](https://github.com/laurigates/claude-plugins/commit/ec1fac989e0028874e409dd808c95adff19c6edc))
* use package-relative paths for extra-files in release-please ([e1c9dcf](https://github.com/laurigates/claude-plugins/commit/e1c9dcf9828178b8b74cf3bc8e92778f144c5a5c))

## [1.1.0](https://github.com/laurigates/claude-plugins/compare/git-plugin-v1.0.0...git-plugin-v1.1.0) (2025-12-28)


### Features

* **git-plugin:** add label discovery and application to PR workflows ([8438ea3](https://github.com/laurigates/claude-plugins/commit/8438ea359271cc3bb62bc9874233f6f8ca705110))
* **git-plugin:** add release-please-configuration skill ([7c31670](https://github.com/laurigates/claude-plugins/commit/7c3167081b6f4fc64cd42bbdd822023363a23e9f))
