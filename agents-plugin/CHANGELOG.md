# Changelog

## [1.10.0](https://github.com/laurigates/claude-plugins/compare/agents-plugin-v1.9.2...agents-plugin-v1.10.0) (2026-05-04)


### Features

* **rules:** re-enable model: parameter for skills at the extremes ([#1232](https://github.com/laurigates/claude-plugins/issues/1232)) ([5abba3a](https://github.com/laurigates/claude-plugins/commit/5abba3aa13a9b7574e6a7aadd1a9dd7ca4dea812))

## [1.9.2](https://github.com/laurigates/claude-plugins/compare/agents-plugin-v1.9.1...agents-plugin-v1.9.2) (2026-04-25)


### Documentation

* **agents-plugin:** standardise When to Use tables ([#1185](https://github.com/laurigates/claude-plugins/issues/1185)) ([70164ae](https://github.com/laurigates/claude-plugins/commit/70164ae09afd469a255a87b20328cadc56c8524a)), closes [#1156](https://github.com/laurigates/claude-plugins/issues/1156)

## [1.9.1](https://github.com/laurigates/claude-plugins/compare/agents-plugin-v1.9.0...agents-plugin-v1.9.1) (2026-04-22)


### Bug Fixes

* **agents-plugin:** replace stale BashOutput tool reference with TaskOutput ([407e3b9](https://github.com/laurigates/claude-plugins/commit/407e3b994b74128eef281c721178a0e68c12435e))

## [1.9.0](https://github.com/laurigates/claude-plugins/compare/agents-plugin-v1.8.0...agents-plugin-v1.9.0) (2026-04-19)


### Features

* make skills discoverable by Claude's auto-invocation ([#1090](https://github.com/laurigates/claude-plugins/issues/1090)) ([cded1da](https://github.com/laurigates/claude-plugins/commit/cded1da1ebaf350cba1285b58ecadbbaa0eb01f6))

## [1.8.0](https://github.com/laurigates/claude-plugins/compare/agents-plugin-v1.7.3...agents-plugin-v1.8.0) (2026-04-18)


### Features

* **agent-patterns-plugin:** add preflight checklist, refactor case study, and out-of-scope protocol ([#1082](https://github.com/laurigates/claude-plugins/issues/1082)) ([88c52b2](https://github.com/laurigates/claude-plugins/commit/88c52b27c0afd294a970a30b07590e56be2d0700))

## [1.7.3](https://github.com/laurigates/claude-plugins/compare/agents-plugin-v1.7.2...agents-plugin-v1.7.3) (2026-04-15)


### Documentation

* **plugins:** add flow diagrams for router and pipeline plugins ([#1034](https://github.com/laurigates/claude-plugins/issues/1034)) ([a5e0e08](https://github.com/laurigates/claude-plugins/commit/a5e0e087495f0e835c3ad7e5dcf5bf7f4e61ad02))

## [1.7.2](https://github.com/laurigates/claude-plugins/compare/agents-plugin-v1.7.1...agents-plugin-v1.7.2) (2026-04-08)


### Bug Fixes

* **blueprint-plugin:** remove model field from skills and fix invocation syntax ([#1007](https://github.com/laurigates/claude-plugins/issues/1007)) ([42e1e5b](https://github.com/laurigates/claude-plugins/commit/42e1e5b6c73d43e5de4b27cdee16e316de44d4c0))

## [1.7.1](https://github.com/laurigates/claude-plugins/compare/agents-plugin-v1.7.0...agents-plugin-v1.7.1) (2026-03-25)


### Bug Fixes

* remove context: fork from all plugin skills to fix rate limit errors ([#981](https://github.com/laurigates/claude-plugins/issues/981)) ([56a90b1](https://github.com/laurigates/claude-plugins/commit/56a90b1464a9b1233a8bdb3d0716f1673bc70ad3))

## [1.7.0](https://github.com/laurigates/claude-plugins/compare/agents-plugin-v1.6.0...agents-plugin-v1.7.0) (2026-03-15)


### Features

* structured codebase attributes with severity-based agent routing ([#946](https://github.com/laurigates/claude-plugins/issues/946)) ([87f03c3](https://github.com/laurigates/claude-plugins/commit/87f03c324c774ba3b4ab8189b0d51fd33cc5e651))

## [1.6.0](https://github.com/laurigates/claude-plugins/compare/agents-plugin-v1.5.0...agents-plugin-v1.6.0) (2026-03-11)


### Features

* **agents-plugin:** add search-replace agent ([3158657](https://github.com/laurigates/claude-plugins/commit/31586572845a31dd8601e26f9855700ccf815308))
* search-replace agent for cross-platform text replacement ([#924](https://github.com/laurigates/claude-plugins/issues/924)) ([3158657](https://github.com/laurigates/claude-plugins/commit/31586572845a31dd8601e26f9855700ccf815308))

## [1.5.0](https://github.com/laurigates/claude-plugins/compare/agents-plugin-v1.4.0...agents-plugin-v1.5.0) (2026-03-09)


### Features

* **rules:** update rules for Claude Code 2.1.63-2.1.71 changes ([#917](https://github.com/laurigates/claude-plugins/issues/917)) ([20341e8](https://github.com/laurigates/claude-plugins/commit/20341e871fe7e91eb79d51aa02ad7bc9003a93e1))

## [1.4.0](https://github.com/laurigates/claude-plugins/compare/agents-plugin-v1.3.1...agents-plugin-v1.4.0) (2026-02-27)


### Features

* add `context: fork` guidance and apply to verbose skills ([#833](https://github.com/laurigates/claude-plugins/issues/833)) ([cced641](https://github.com/laurigates/claude-plugins/commit/cced641a953953b97f37528960782cacd75dbcab))
* **skills:** add context: fork to verbose autonomous skills ([cced641](https://github.com/laurigates/claude-plugins/commit/cced641a953953b97f37528960782cacd75dbcab))

## [1.3.1](https://github.com/laurigates/claude-plugins/compare/agents-plugin-v1.3.0...agents-plugin-v1.3.1) (2026-02-23)


### Bug Fixes

* remove 2&gt;/dev/null from context commands across all plugins ([#792](https://github.com/laurigates/claude-plugins/issues/792)) ([c72e67e](https://github.com/laurigates/claude-plugins/commit/c72e67ee37e809449f0e6282c48fac01363a59fd))

## [1.3.0](https://github.com/laurigates/claude-plugins/compare/agents-plugin-v1.2.0...agents-plugin-v1.3.0) (2026-02-18)


### Features

* introduce three-tier model palette (opus/sonnet/haiku) ([#709](https://github.com/laurigates/claude-plugins/issues/709)) ([2c1e9cc](https://github.com/laurigates/claude-plugins/commit/2c1e9ccff5d48c2b426beac5b3b38cd4576c79a0))

## [1.2.0](https://github.com/laurigates/claude-plugins/compare/agents-plugin-v1.1.5...agents-plugin-v1.2.0) (2026-02-16)


### Features

* **configure-plugin:** replace detect-secrets with gitleaks for secret scanning ([#668](https://github.com/laurigates/claude-plugins/issues/668)) ([3fc5bbc](https://github.com/laurigates/claude-plugins/commit/3fc5bbc2f8500f30160cc5dfeb5e3d1253ed0a54))

## [1.2.0](https://github.com/laurigates/claude-plugins/compare/agents-plugin-v1.1.5...agents-plugin-v1.2.0) (2026-02-16)


### Features

* **configure-plugin:** replace detect-secrets with gitleaks for secret scanning ([#668](https://github.com/laurigates/claude-plugins/issues/668)) ([3fc5bbc](https://github.com/laurigates/claude-plugins/commit/3fc5bbc2f8500f30160cc5dfeb5e3d1253ed0a54))

## [1.1.5](https://github.com/laurigates/claude-plugins/compare/agents-plugin-v1.1.4...agents-plugin-v1.1.5) (2026-02-08)


### Bug Fixes

* update skill review dates to trigger release sync ([#489](https://github.com/laurigates/claude-plugins/issues/489)) ([ca20d06](https://github.com/laurigates/claude-plugins/commit/ca20d0667baaa31dfa805c7dc775a1828c515223))

## [1.1.4](https://github.com/laurigates/claude-plugins/compare/agents-plugin-v1.1.3...agents-plugin-v1.1.4) (2026-02-06)


### Bug Fixes

* **frontmatter:** resolve 83 validation errors across 75 files ([#434](https://github.com/laurigates/claude-plugins/issues/434)) ([5beb75e](https://github.com/laurigates/claude-plugins/commit/5beb75ed4b2cb0431d060bd7102903495c03c6c5))

## [1.1.3](https://github.com/laurigates/claude-plugins/compare/agents-plugin-v1.1.2...agents-plugin-v1.1.3) (2026-02-04)


### Documentation

* **rules, settings:** refactor to emphasize positive guidance patterns ([#360](https://github.com/laurigates/claude-plugins/issues/360)) ([a4ea8a8](https://github.com/laurigates/claude-plugins/commit/a4ea8a8990e2a40bb2331855db5fd68631c14d7e))

## [1.1.3](https://github.com/laurigates/claude-plugins/compare/agents-plugin-v1.1.2...agents-plugin-v1.1.3) (2026-02-04)


### Documentation

* **rules, settings:** refactor to emphasize positive guidance patterns ([#360](https://github.com/laurigates/claude-plugins/issues/360)) ([a4ea8a8](https://github.com/laurigates/claude-plugins/commit/a4ea8a8990e2a40bb2331855db5fd68631c14d7e))

## [1.1.2](https://github.com/laurigates/claude-plugins/compare/agents-plugin-v1.1.1...agents-plugin-v1.1.2) (2026-02-03)


### Bug Fixes

* remove shell operators from context commands in multiple plugins ([#326](https://github.com/laurigates/claude-plugins/issues/326)) ([b028f73](https://github.com/laurigates/claude-plugins/commit/b028f7385f66f8f063a95874840c51e553694205))

## [1.1.1](https://github.com/laurigates/claude-plugins/compare/agents-plugin-v1.1.0...agents-plugin-v1.1.1) (2026-02-02)


### Bug Fixes

* **agent-patterns-plugin:** block git writes for parallel agents to prevent conflicts ([#299](https://github.com/laurigates/claude-plugins/issues/299)) ([a2c2ce0](https://github.com/laurigates/claude-plugins/commit/a2c2ce07d67ead9b30470b398777be355672281b))

## [1.1.0](https://github.com/laurigates/claude-plugins/compare/agents-plugin-v1.0.0...agents-plugin-v1.1.0) (2026-01-24)


### Features

* **agents-plugin:** add 9 specialized sub-agents for context isolation ([#204](https://github.com/laurigates/claude-plugins/issues/204)) ([5809817](https://github.com/laurigates/claude-plugins/commit/5809817cc7aec254fd45ffb07e493088347b7c9c))
