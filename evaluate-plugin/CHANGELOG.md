# Changelog

## [1.14.5](https://github.com/laurigates/claude-plugins/compare/evaluate-plugin-v1.14.4...evaluate-plugin-v1.14.5) (2026-09-03)


### Bug Fixes

* **evaluate-plugin:** make context-engineering ordering test deterministic ([#2577](https://github.com/laurigates/claude-plugins/issues/2577)) ([478bd01](https://github.com/laurigates/claude-plugins/commit/478bd01638eb4cd5aedf04ceea25768cdc31473f)), closes [#2563](https://github.com/laurigates/claude-plugins/issues/2563)

## [1.14.4](https://github.com/laurigates/claude-plugins/compare/evaluate-plugin-v1.14.3...evaluate-plugin-v1.14.4) (2026-09-03)


### Bug Fixes

* **ci:** restore four scheduled-audit signals that were reporting nothing, or nonsense ([#2576](https://github.com/laurigates/claude-plugins/issues/2576)) ([de4337c](https://github.com/laurigates/claude-plugins/commit/de4337c7776ba7531cbe923fe016df78ef9b7e8c))

## [1.14.3](https://github.com/laurigates/claude-plugins/compare/evaluate-plugin-v1.14.2...evaluate-plugin-v1.14.3) (2026-09-02)


### Bug Fixes

* **plugins:** adapt rules, skills, agents, and guards for Claude Fable 5.1 ([#2561](https://github.com/laurigates/claude-plugins/issues/2561)) ([b9e1101](https://github.com/laurigates/claude-plugins/commit/b9e11016b20c42b0ff95c5fef57e98584a4e7c07))

## [1.14.2](https://github.com/laurigates/claude-plugins/compare/evaluate-plugin-v1.14.1...evaluate-plugin-v1.14.2) (2026-09-02)


### Bug Fixes

* **evaluate-plugin:** guard the duplicate-basename test's mktemp sandboxes ([30fb6e7](https://github.com/laurigates/claude-plugins/commit/30fb6e78a7465a5b88c69797cec320909a73347a)), closes [#2550](https://github.com/laurigates/claude-plugins/issues/2550)

## [1.14.1](https://github.com/laurigates/claude-plugins/compare/evaluate-plugin-v1.14.0...evaluate-plugin-v1.14.1) (2026-09-01)


### Code Refactoring

* **evaluate-plugin:** split evaluate-improve's apply machinery into references/ ([#2552](https://github.com/laurigates/claude-plugins/issues/2552)) ([e9491c0](https://github.com/laurigates/claude-plugins/commit/e9491c0d4d2e4a2d3f33e39ea2e10c7dc951731c))

## [1.14.0](https://github.com/laurigates/claude-plugins/compare/evaluate-plugin-v1.13.1...evaluate-plugin-v1.14.0) (2026-08-31)


### Features

* **evaluate-plugin:** sum the always-loaded surface across repos (--also) ([#2550](https://github.com/laurigates/claude-plugins/issues/2550)) ([149b132](https://github.com/laurigates/claude-plugins/commit/149b1322545ee69ad925cffc601511a22459b8bc))

## [1.13.1](https://github.com/laurigates/claude-plugins/compare/evaluate-plugin-v1.13.0...evaluate-plugin-v1.13.1) (2026-08-22)


### Documentation

* fix catalog drift after [#2450](https://github.com/laurigates/claude-plugins/issues/2450) and gate it in check-docs-index ([f5e000c](https://github.com/laurigates/claude-plugins/commit/f5e000c8e8532edc0ec0456b594bae753a9e447c)), closes [#2453](https://github.com/laurigates/claude-plugins/issues/2453)

## [1.13.0](https://github.com/laurigates/claude-plugins/compare/evaluate-plugin-v1.12.0...evaluate-plugin-v1.13.0) (2026-08-14)


### Features

* **evaluate-plugin:** trigger the Tier-2 golden-set sweep on a cadence ([#2390](https://github.com/laurigates/claude-plugins/issues/2390)) ([d451409](https://github.com/laurigates/claude-plugins/commit/d45140985ab38b626a3385a338c5852f3c207f73)), closes [#2182](https://github.com/laurigates/claude-plugins/issues/2182)

## [1.12.0](https://github.com/laurigates/claude-plugins/compare/evaluate-plugin-v1.11.0...evaluate-plugin-v1.12.0) (2026-07-27)


### Features

* **evaluate-plugin:** add /evaluate:context-engineering audit skill ([e55b686](https://github.com/laurigates/claude-plugins/commit/e55b68639ab31f34728a62fdddf66a2390558c44))


### Documentation

* **benchmarks:** publish the 2026-07 context-engineering findings ([47002ab](https://github.com/laurigates/claude-plugins/commit/47002abb6a066d8d1a90ea896f6bbc42b2c9ffff))

## [1.11.0](https://github.com/laurigates/claude-plugins/compare/evaluate-plugin-v1.10.0...evaluate-plugin-v1.11.0) (2026-07-05)


### Features

* **repo:** roll out context: fork to single-subagent skills ([#1971](https://github.com/laurigates/claude-plugins/issues/1971)) ([2dfa3a2](https://github.com/laurigates/claude-plugins/commit/2dfa3a239656c688ad55e9b12bd2857bfad63a9b))

## [1.10.0](https://github.com/laurigates/claude-plugins/compare/evaluate-plugin-v1.9.1...evaluate-plugin-v1.10.0) (2026-06-23)


### Features

* **evaluate-plugin:** add source-cases delta-verify gate to evaluate-improve ([#1781](https://github.com/laurigates/claude-plugins/issues/1781)) ([c601880](https://github.com/laurigates/claude-plugins/commit/c6018803b079a68d133519ae24ca53b155fa7367))

## [1.9.1](https://github.com/laurigates/claude-plugins/compare/evaluate-plugin-v1.9.0...evaluate-plugin-v1.9.1) (2026-06-20)


### Bug Fixes

* **hooks-plugin:** guard test/hook mktemp -d sandboxes against shared-checkout git leak ([#1719](https://github.com/laurigates/claude-plugins/issues/1719)) ([448b212](https://github.com/laurigates/claude-plugins/commit/448b2127a7240136dffd721ad1309c2375cc0814))

## [1.9.0](https://github.com/laurigates/claude-plugins/compare/evaluate-plugin-v1.8.0...evaluate-plugin-v1.9.0) (2026-06-18)


### Features

* **scripts:** context-command execution harness + sweep 122 fragile Context commands ([#1690](https://github.com/laurigates/claude-plugins/issues/1690)) ([609342f](https://github.com/laurigates/claude-plugins/commit/609342f2c5b6b5f2ee555f83dbac1f5f3dd1f93d))

## [1.8.0](https://github.com/laurigates/claude-plugins/compare/evaluate-plugin-v1.7.0...evaluate-plugin-v1.8.0) (2026-06-13)


### Features

* **evaluate-plugin:** weak-model skill validation — legibility + matrix gates + fixtures ([#1625](https://github.com/laurigates/claude-plugins/issues/1625)) ([ce4e27a](https://github.com/laurigates/claude-plugins/commit/ce4e27ad21737d660f07636cb5838d3aa3f0c7c4))

## [1.7.0](https://github.com/laurigates/claude-plugins/compare/evaluate-plugin-v1.6.0...evaluate-plugin-v1.7.0) (2026-06-12)


### Features

* **evaluate-plugin:** adopt RHO verify and best-of-N patterns ([#1593](https://github.com/laurigates/claude-plugins/issues/1593)) ([777755c](https://github.com/laurigates/claude-plugins/commit/777755c64326ab5f55422a0cb5ec5ef69bd11a13))

## [1.6.0](https://github.com/laurigates/claude-plugins/compare/evaluate-plugin-v1.5.0...evaluate-plugin-v1.6.0) (2026-05-30)


### Features

* **evaluate-plugin:** add cross-model skill evaluation framework ([#1459](https://github.com/laurigates/claude-plugins/issues/1459)) ([df6cb21](https://github.com/laurigates/claude-plugins/commit/df6cb21b570e6e19628958f112727c8cd0bd27ab))

## [1.5.0](https://github.com/laurigates/claude-plugins/compare/evaluate-plugin-v1.4.3...evaluate-plugin-v1.5.0) (2026-05-24)


### Features

* **hooks-plugin:** add SessionStart drift-nudge architecture ([#1401](https://github.com/laurigates/claude-plugins/issues/1401)) ([47815e2](https://github.com/laurigates/claude-plugins/commit/47815e2035923e9c714142597cd6ed4ad43e9f7e))

## [1.4.3](https://github.com/laurigates/claude-plugins/compare/evaluate-plugin-v1.4.2...evaluate-plugin-v1.4.3) (2026-05-14)


### Code Refactoring

* **evaluate-plugin:** tighten skill descriptions for listing budget ([8ebbf3a](https://github.com/laurigates/claude-plugins/commit/8ebbf3a651e7a38c9dbf2b9197c3747104d9fcd8))

## [1.4.2](https://github.com/laurigates/claude-plugins/compare/evaluate-plugin-v1.4.1...evaluate-plugin-v1.4.2) (2026-05-09)


### Documentation

* trim oversized SKILL.md descriptions across 41 plugins ([#1265](https://github.com/laurigates/claude-plugins/issues/1265)) ([e13d9f4](https://github.com/laurigates/claude-plugins/commit/e13d9f46a010559082c6d5eb61b0cb891843bf97))

## [1.4.1](https://github.com/laurigates/claude-plugins/compare/evaluate-plugin-v1.4.0...evaluate-plugin-v1.4.1) (2026-05-07)


### Bug Fixes

* **agents:** bake tool-selection rules into agent definitions ([#1262](https://github.com/laurigates/claude-plugins/issues/1262)) ([a9b128a](https://github.com/laurigates/claude-plugins/commit/a9b128af9238f2c20cc3c4efb92ec86c06a39752))

## [1.4.0](https://github.com/laurigates/claude-plugins/compare/evaluate-plugin-v1.3.4...evaluate-plugin-v1.4.0) (2026-04-19)


### Features

* make skills discoverable by Claude's auto-invocation ([#1090](https://github.com/laurigates/claude-plugins/issues/1090)) ([cded1da](https://github.com/laurigates/claude-plugins/commit/cded1da1ebaf350cba1285b58ecadbbaa0eb01f6))

## [1.3.4](https://github.com/laurigates/claude-plugins/compare/evaluate-plugin-v1.3.3...evaluate-plugin-v1.3.4) (2026-04-15)


### Documentation

* **plugins:** add flow diagrams for router and pipeline plugins ([#1034](https://github.com/laurigates/claude-plugins/issues/1034)) ([a5e0e08](https://github.com/laurigates/claude-plugins/commit/a5e0e087495f0e835c3ad7e5dcf5bf7f4e61ad02))

## [1.3.3](https://github.com/laurigates/claude-plugins/compare/evaluate-plugin-v1.3.2...evaluate-plugin-v1.3.3) (2026-04-12)


### Code Refactoring

* **evaluate-plugin:** extract evaluate skill inline commands to standalone scripts ([#1023](https://github.com/laurigates/claude-plugins/issues/1023)) ([bc0a3dc](https://github.com/laurigates/claude-plugins/commit/bc0a3dc238a611e5102101d507189424f251a225)), closes [#987](https://github.com/laurigates/claude-plugins/issues/987)
* **health-plugin:** extract health-plugins inline commands to standalone scripts ([#1022](https://github.com/laurigates/claude-plugins/issues/1022)) ([b18efb0](https://github.com/laurigates/claude-plugins/commit/b18efb01ca6f47591f054809dbf805e0daa5fcca)), closes [#984](https://github.com/laurigates/claude-plugins/issues/984)

## [1.3.2](https://github.com/laurigates/claude-plugins/compare/evaluate-plugin-v1.3.1...evaluate-plugin-v1.3.2) (2026-04-08)


### Bug Fixes

* **blueprint-plugin:** remove model field from skills and fix invocation syntax ([#1007](https://github.com/laurigates/claude-plugins/issues/1007)) ([42e1e5b](https://github.com/laurigates/claude-plugins/commit/42e1e5b6c73d43e5de4b27cdee16e316de44d4c0))

## [1.3.1](https://github.com/laurigates/claude-plugins/compare/evaluate-plugin-v1.3.0...evaluate-plugin-v1.3.1) (2026-03-25)


### Bug Fixes

* remove context: fork from all plugin skills to fix rate limit errors ([#981](https://github.com/laurigates/claude-plugins/issues/981)) ([56a90b1](https://github.com/laurigates/claude-plugins/commit/56a90b1464a9b1233a8bdb3d0716f1673bc70ad3))

## [1.3.0](https://github.com/laurigates/claude-plugins/compare/evaluate-plugin-v1.2.0...evaluate-plugin-v1.3.0) (2026-03-09)


### Features

* **rules:** update rules for Claude Code 2.1.63-2.1.71 changes ([#917](https://github.com/laurigates/claude-plugins/issues/917)) ([20341e8](https://github.com/laurigates/claude-plugins/commit/20341e871fe7e91eb79d51aa02ad7bc9003a93e1))

## [1.2.0](https://github.com/laurigates/claude-plugins/compare/evaluate-plugin-v1.1.0...evaluate-plugin-v1.2.0) (2026-03-04)


### Features

* evaluate-plugin for skill evaluation and benchmarking ([#871](https://github.com/laurigates/claude-plugins/issues/871)) ([22cf97a](https://github.com/laurigates/claude-plugins/commit/22cf97a513245928e2e5b2572758ea0e33e34b90))

## [1.1.0](https://github.com/laurigates/claude-plugins/compare/evaluate-plugin-v1.0.0...evaluate-plugin-v1.1.0) (2026-03-04)


### Features

* evaluate-plugin for skill evaluation and benchmarking ([#871](https://github.com/laurigates/claude-plugins/issues/871)) ([22cf97a](https://github.com/laurigates/claude-plugins/commit/22cf97a513245928e2e5b2572758ea0e33e34b90))

## Changelog
