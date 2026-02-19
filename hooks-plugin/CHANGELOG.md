# Changelog

## [1.5.6](https://github.com/laurigates/claude-plugins/compare/hooks-plugin-v1.5.5...hooks-plugin-v1.5.6) (2026-02-18)


### Bug Fixes

* **hooks-plugin:** block git push -u on main to differently-named branch ([#746](https://github.com/laurigates/claude-plugins/issues/746)) ([25e3e49](https://github.com/laurigates/claude-plugins/commit/25e3e494e84f676503a52a5ed24e0eb62c467e09))

## [1.5.5](https://github.com/laurigates/claude-plugins/compare/hooks-plugin-v1.5.4...hooks-plugin-v1.5.5) (2026-02-17)


### Bug Fixes

* **hooks-plugin:** allow dotfile staging in bash-antipatterns check ([#703](https://github.com/laurigates/claude-plugins/issues/703)) ([ba387e2](https://github.com/laurigates/claude-plugins/commit/ba387e29f5dd7f122ee6c51af32fcc69f04b67ee)), closes [#595](https://github.com/laurigates/claude-plugins/issues/595)

## [1.5.4](https://github.com/laurigates/claude-plugins/compare/hooks-plugin-v1.5.3...hooks-plugin-v1.5.4) (2026-02-17)


### Bug Fixes

* **hooks-plugin:** exclude quoted strings and || from pipe count in bash-antipatterns hook ([31726b0](https://github.com/laurigates/claude-plugins/commit/31726b025b15cd9a0c2f4ce9a90fbc0c4636634b))
* pipe counting in bash-antipatterns to exclude quoted strings and operators ([#699](https://github.com/laurigates/claude-plugins/issues/699)) ([31726b0](https://github.com/laurigates/claude-plugins/commit/31726b025b15cd9a0c2f4ce9a90fbc0c4636634b))

## [1.5.3](https://github.com/laurigates/claude-plugins/compare/hooks-plugin-v1.5.2...hooks-plugin-v1.5.3) (2026-02-13)


### Bug Fixes

* **hooks-plugin:** exclude heredoc content from pipe count in bash-antipatterns hook ([#597](https://github.com/laurigates/claude-plugins/issues/597)) ([2045bc7](https://github.com/laurigates/claude-plugins/commit/2045bc7ea53deea6709409df066509cb642094de))

## [1.5.2](https://github.com/laurigates/claude-plugins/compare/hooks-plugin-v1.5.1...hooks-plugin-v1.5.2) (2026-02-13)


### Bug Fixes

* **hooks-plugin:** detect broad git staging commands (git add -A, git add .) ([c7f75b6](https://github.com/laurigates/claude-plugins/commit/c7f75b639dc2c59ad9191cb730e459eaf124ec1c))

## [1.5.1](https://github.com/laurigates/claude-plugins/compare/hooks-plugin-v1.5.0...hooks-plugin-v1.5.1) (2026-02-12)


### Bug Fixes

* standardize skill name fields to kebab-case across all plugins ([72c0f83](https://github.com/laurigates/claude-plugins/commit/72c0f837a1b07004850c5906a30d619a79098f69))

## [1.5.0](https://github.com/laurigates/claude-plugins/compare/hooks-plugin-v1.4.0...hooks-plugin-v1.5.0) (2026-02-11)


### Features

* add required quality sections to refactored skills ([#544](https://github.com/laurigates/claude-plugins/issues/544)) ([342af54](https://github.com/laurigates/claude-plugins/commit/342af54af0f81fa50d239d06b32b353ddb7335fc))

## [1.4.0](https://github.com/laurigates/claude-plugins/compare/hooks-plugin-v1.3.2...hooks-plugin-v1.4.0) (2026-02-07)


### Features

* **hooks-plugin:** add session-start-hook skill for Claude Code on the web ([#483](https://github.com/laurigates/claude-plugins/issues/483)) ([a9f6651](https://github.com/laurigates/claude-plugins/commit/a9f6651c2d432e7023f778d40aeeb8702e52fa5c))

## [1.3.2](https://github.com/laurigates/claude-plugins/compare/hooks-plugin-v1.3.1...hooks-plugin-v1.3.2) (2026-02-04)


### Bug Fixes

* **hooks-plugin:** update git chaining examples in bash-antipatterns hook ([3c375a0](https://github.com/laurigates/claude-plugins/commit/3c375a0b784114a5e2218db0a9782d402f01015b))

## [1.3.1](https://github.com/laurigates/claude-plugins/compare/hooks-plugin-v1.3.0...hooks-plugin-v1.3.1) (2026-02-01)


### Bug Fixes

* enforce granular Bash permissions across all plugins ([#267](https://github.com/laurigates/claude-plugins/issues/267)) ([afeb507](https://github.com/laurigates/claude-plugins/commit/afeb50754838c2923807c8f2a248b3798fd4281c))

## [1.3.0](https://github.com/laurigates/claude-plugins/compare/hooks-plugin-v1.2.0...hooks-plugin-v1.3.0) (2026-01-26)


### Features

* **hooks-plugin:** block git reset --hard in bash-antipatterns hook ([d8b770c](https://github.com/laurigates/claude-plugins/commit/d8b770cb3253f052ef8ad560fde1d7f2c06740a8))

## [1.2.0](https://github.com/laurigates/claude-plugins/compare/hooks-plugin-v1.1.0...hooks-plugin-v1.2.0) (2026-01-23)


### Features

* add model specification to all skills and commands ([#131](https://github.com/laurigates/claude-plugins/issues/131)) ([81f2961](https://github.com/laurigates/claude-plugins/commit/81f296155b50864b8b1687b9eb18a9c2cbb08791))

## [1.1.0](https://github.com/laurigates/claude-plugins/compare/hooks-plugin-v1.0.0...hooks-plugin-v1.1.0) (2026-01-21)


### Features

* **hooks-plugin:** add TaskOutput anti-pattern for task output file access ([#87](https://github.com/laurigates/claude-plugins/issues/87)) ([c4895b3](https://github.com/laurigates/claude-plugins/commit/c4895b3738955ad0c48c818030c79df967e7143d))
* **hooks-plugin:** detect chained git commands that cause lock race conditions ([#105](https://github.com/laurigates/claude-plugins/issues/105)) ([57488b6](https://github.com/laurigates/claude-plugins/commit/57488b6f9c826f9e3e79d21d21333144168db046))
* **hooks-plugin:** detect excessive pipe chains and test output parsing ([#103](https://github.com/laurigates/claude-plugins/issues/103)) ([d893d89](https://github.com/laurigates/claude-plugins/commit/d893d89f05a00ec2cfd996d364c38a3629107960))
* implement Claude Code 2.1.7 changelog review updates (issue [#78](https://github.com/laurigates/claude-plugins/issues/78)) ([#112](https://github.com/laurigates/claude-plugins/issues/112)) ([e28d8de](https://github.com/laurigates/claude-plugins/commit/e28d8deec41d3e5070861a3f1c37e9c43f452cb4))
