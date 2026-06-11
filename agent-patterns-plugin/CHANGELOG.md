# Changelog

## [2.23.0](https://github.com/laurigates/claude-plugins/compare/agent-patterns-plugin-v2.22.3...agent-patterns-plugin-v2.23.0) (2026-06-11)


### Features

* cold-read-gate + workflow-verify-before-filing skills ([#1588](https://github.com/laurigates/claude-plugins/issues/1588)) ([cec93b3](https://github.com/laurigates/claude-plugins/commit/cec93b3e4024cb02d29c962e6e809f82bfa08d60))

## [2.22.3](https://github.com/laurigates/claude-plugins/compare/agent-patterns-plugin-v2.22.2...agent-patterns-plugin-v2.22.3) (2026-06-08)


### Documentation

* **rules:** sync hook/agent/plugin rules for changelog 2.1.138→2.1.159 ([#1537](https://github.com/laurigates/claude-plugins/issues/1537)) ([f282a48](https://github.com/laurigates/claude-plugins/commit/f282a4813a01de59f94ef185a7bfdbe8adfffb06))

## [2.22.2](https://github.com/laurigates/claude-plugins/compare/agent-patterns-plugin-v2.22.1...agent-patterns-plugin-v2.22.2) (2026-06-07)


### Documentation

* refresh stale plugin-relationships diagram and guard it ([#1523](https://github.com/laurigates/claude-plugins/issues/1523)) ([#1533](https://github.com/laurigates/claude-plugins/issues/1533)) ([924025e](https://github.com/laurigates/claude-plugins/commit/924025eb378c1519b044fb65bbbf7cec922dbbb8))

## [2.22.1](https://github.com/laurigates/claude-plugins/compare/agent-patterns-plugin-v2.22.0...agent-patterns-plugin-v2.22.1) (2026-06-06)


### Bug Fixes

* **agent-patterns:** guard worktree agents against cwd-reset leaking git writes into main repo ([#1480](https://github.com/laurigates/claude-plugins/issues/1480)) ([#1520](https://github.com/laurigates/claude-plugins/issues/1520)) ([156c334](https://github.com/laurigates/claude-plugins/commit/156c3342e0db2a4b24f4665e17c8adce04eb1e99))

## [2.22.0](https://github.com/laurigates/claude-plugins/compare/agent-patterns-plugin-v2.21.6...agent-patterns-plugin-v2.22.0) (2026-06-06)


### Features

* **agent-patterns-plugin:** salvage worktree WIP when an isolated agent exits before StructuredOutput ([#1517](https://github.com/laurigates/claude-plugins/issues/1517)) ([a40fdd8](https://github.com/laurigates/claude-plugins/commit/a40fdd804cc71e973346f494e5075c9a1eb1d9ba))


### Documentation

* **agent-patterns-plugin:** advise conservative concurrency and rate-limit backoff in parallel-agent-dispatch ([#1518](https://github.com/laurigates/claude-plugins/issues/1518)) ([716c859](https://github.com/laurigates/claude-plugins/commit/716c85952a27ea11d691483ba02497f0d66dc9ad)), closes [#1490](https://github.com/laurigates/claude-plugins/issues/1490)

## [2.21.6](https://github.com/laurigates/claude-plugins/compare/agent-patterns-plugin-v2.21.5...agent-patterns-plugin-v2.21.6) (2026-06-04)


### Bug Fixes

* resolve actionable open issues ([#1424](https://github.com/laurigates/claude-plugins/issues/1424), [#1425](https://github.com/laurigates/claude-plugins/issues/1425), [#1463](https://github.com/laurigates/claude-plugins/issues/1463)) ([#1500](https://github.com/laurigates/claude-plugins/issues/1500)) ([81afcee](https://github.com/laurigates/claude-plugins/commit/81afceeb292fed2feac4a0580f92501564c95866))

## [2.21.5](https://github.com/laurigates/claude-plugins/compare/agent-patterns-plugin-v2.21.4...agent-patterns-plugin-v2.21.5) (2026-06-01)


### Bug Fixes

* **agent-patterns-plugin:** mandate loud-failure contract for dispatched agents ([#1471](https://github.com/laurigates/claude-plugins/issues/1471)) ([1e43509](https://github.com/laurigates/claude-plugins/commit/1e435092f166760fdbae7ac81d276688de64fb6b))

## [2.21.4](https://github.com/laurigates/claude-plugins/compare/agent-patterns-plugin-v2.21.3...agent-patterns-plugin-v2.21.4) (2026-05-31)


### Documentation

* **agent-patterns-plugin:** document killed-agent worktree recovery ([#1465](https://github.com/laurigates/claude-plugins/issues/1465)) ([e8e82c3](https://github.com/laurigates/claude-plugins/commit/e8e82c34acc2ce3f54b8e87f04a21d0fcd3f52f8))

## [2.21.3](https://github.com/laurigates/claude-plugins/compare/agent-patterns-plugin-v2.21.2...agent-patterns-plugin-v2.21.3) (2026-05-24)


### Code Refactoring

* **hooks-plugin:** merge claude-hooks-configuration into hooks-configuration ([#1384](https://github.com/laurigates/claude-plugins/issues/1384)) ([4ca1afd](https://github.com/laurigates/claude-plugins/commit/4ca1afdcd5af605b1c8e52d2a6ae55d44c83305d))

## [2.21.2](https://github.com/laurigates/claude-plugins/compare/agent-patterns-plugin-v2.21.1...agent-patterns-plugin-v2.21.2) (2026-05-19)


### Bug Fixes

* **git-plugin:** detect transient worktree-isolation leaks in coworker check ([#1343](https://github.com/laurigates/claude-plugins/issues/1343)) ([7e7cb0c](https://github.com/laurigates/claude-plugins/commit/7e7cb0c9f002dc07237db45afd467f9c3610e672))

## [2.21.1](https://github.com/laurigates/claude-plugins/compare/agent-patterns-plugin-v2.21.0...agent-patterns-plugin-v2.21.1) (2026-05-19)


### Code Refactoring

* **agent-patterns-plugin:** extract parallel-agent-dispatch reference material to REFERENCE.md ([b6a695b](https://github.com/laurigates/claude-plugins/commit/b6a695b6763fde14b998e5c5466df82bfaabc773)), closes [#1326](https://github.com/laurigates/claude-plugins/issues/1326)

## [2.21.0](https://github.com/laurigates/claude-plugins/compare/agent-patterns-plugin-v2.20.2...agent-patterns-plugin-v2.21.0) (2026-05-14)


### Features

* **agent-patterns-plugin:** add verify-before-plan skill ([#1315](https://github.com/laurigates/claude-plugins/issues/1315)) ([46e3678](https://github.com/laurigates/claude-plugins/commit/46e3678438ee77095d9eac82c60a570af8b20a6a))

## [2.20.2](https://github.com/laurigates/claude-plugins/compare/agent-patterns-plugin-v2.20.1...agent-patterns-plugin-v2.20.2) (2026-05-14)


### Documentation

* **agent-patterns-plugin:** document pre-commit stalls, rate-limit cascade, and agent self-verification in parallel-dispatch ([#1317](https://github.com/laurigates/claude-plugins/issues/1317)) ([7319709](https://github.com/laurigates/claude-plugins/commit/73197091ea6ff9d25ba3fd34a8ad0a2e292fe1c3))

## [2.20.1](https://github.com/laurigates/claude-plugins/compare/agent-patterns-plugin-v2.20.0...agent-patterns-plugin-v2.20.1) (2026-05-14)


### Code Refactoring

* **agent-patterns-plugin:** tighten skill descriptions for listing budget ([7a5504b](https://github.com/laurigates/claude-plugins/commit/7a5504bc1b33ae1a7460513405b23e96e10bfe65))

## [2.20.0](https://github.com/laurigates/claude-plugins/compare/agent-patterns-plugin-v2.19.0...agent-patterns-plugin-v2.20.0) (2026-05-09)


### Features

* **agent-patterns-plugin:** add meta-promote skill for cross-scope rule promotion ([#1291](https://github.com/laurigates/claude-plugins/issues/1291)) ([25fee42](https://github.com/laurigates/claude-plugins/commit/25fee4221c7e1f09d85c3a0ef1c50965ae98f585))

## [2.19.0](https://github.com/laurigates/claude-plugins/compare/agent-patterns-plugin-v2.18.2...agent-patterns-plugin-v2.19.0) (2026-05-09)


### Features

* **plugins:** add check_skill_size() lint and trim 4 oversized SKILL.md bodies ([#1284](https://github.com/laurigates/claude-plugins/issues/1284)) ([20c97c9](https://github.com/laurigates/claude-plugins/commit/20c97c93337d52e739ab3619a6d6c473a89903b6))

## [2.18.2](https://github.com/laurigates/claude-plugins/compare/agent-patterns-plugin-v2.18.1...agent-patterns-plugin-v2.18.2) (2026-05-09)


### Documentation

* trim oversized SKILL.md descriptions across 41 plugins ([#1265](https://github.com/laurigates/claude-plugins/issues/1265)) ([e13d9f4](https://github.com/laurigates/claude-plugins/commit/e13d9f46a010559082c6d5eb61b0cb891843bf97))

## [2.18.1](https://github.com/laurigates/claude-plugins/compare/agent-patterns-plugin-v2.18.0...agent-patterns-plugin-v2.18.1) (2026-05-06)


### Documentation

* **agent-patterns-plugin:** document sub-agent constraint when spawning teams ([#1247](https://github.com/laurigates/claude-plugins/issues/1247)) ([bc49bde](https://github.com/laurigates/claude-plugins/commit/bc49bde048adce60b28966144b4cc90129906107))

## [2.18.0](https://github.com/laurigates/claude-plugins/compare/agent-patterns-plugin-v2.17.2...agent-patterns-plugin-v2.18.0) (2026-05-04)


### Features

* **rules:** re-enable model: parameter for skills at the extremes ([#1232](https://github.com/laurigates/claude-plugins/issues/1232)) ([5abba3a](https://github.com/laurigates/claude-plugins/commit/5abba3aa13a9b7574e6a7aadd1a9dd7ca4dea812))

## [2.17.2](https://github.com/laurigates/claude-plugins/compare/agent-patterns-plugin-v2.17.1...agent-patterns-plugin-v2.17.2) (2026-04-25)


### Bug Fixes

* **skills:** convert When to Use sections to required table format ([#1192](https://github.com/laurigates/claude-plugins/issues/1192)) ([4a52cb4](https://github.com/laurigates/claude-plugins/commit/4a52cb4f5cbc459e5df78d361891a91bbe1496ec))

## [2.17.1](https://github.com/laurigates/claude-plugins/compare/agent-patterns-plugin-v2.17.0...agent-patterns-plugin-v2.17.1) (2026-04-25)


### Documentation

* **agent-patterns-plugin:** standardise When to Use tables ([#1184](https://github.com/laurigates/claude-plugins/issues/1184)) ([f117dfc](https://github.com/laurigates/claude-plugins/commit/f117dfc807ba57955eccd1b19b474ee59fff3bf2)), closes [#1156](https://github.com/laurigates/claude-plugins/issues/1156)

## [2.17.0](https://github.com/laurigates/claude-plugins/compare/agent-patterns-plugin-v2.16.0...agent-patterns-plugin-v2.17.0) (2026-04-25)


### Features

* **agent-patterns-plugin:** add wave-based-dispatch skill for sequential WO chains ([#1152](https://github.com/laurigates/claude-plugins/issues/1152)) ([76bb8c7](https://github.com/laurigates/claude-plugins/commit/76bb8c7a46c4280afa2ce9cbbd412372bae30202)), closes [#1128](https://github.com/laurigates/claude-plugins/issues/1128)


### Documentation

* **agent-patterns-plugin:** codify verbatim-patch + agent-authors-prose ([#1150](https://github.com/laurigates/claude-plugins/issues/1150)) ([2b5da94](https://github.com/laurigates/claude-plugins/commit/2b5da94bc6f5cd3d952ed5d55797b6face6b61d9))
* **agent-patterns-plugin:** warn about worktree-isolated Edit/Write path resolution ([#1151](https://github.com/laurigates/claude-plugins/issues/1151)) ([e21d4dd](https://github.com/laurigates/claude-plugins/commit/e21d4dd729cd09155cfb427d9d30bb1eb80a3489)), closes [#1091](https://github.com/laurigates/claude-plugins/issues/1091)

## [2.16.0](https://github.com/laurigates/claude-plugins/compare/agent-patterns-plugin-v2.15.0...agent-patterns-plugin-v2.16.0) (2026-04-24)


### Features

* **agent-patterns-plugin:** refine parallel-agent-dispatch and add exclusive-lock-dispatch ([#1131](https://github.com/laurigates/claude-plugins/issues/1131)) ([d243b9a](https://github.com/laurigates/claude-plugins/commit/d243b9ab404e468f24bb637256251e17ad934370))

## [2.15.0](https://github.com/laurigates/claude-plugins/compare/agent-patterns-plugin-v2.14.0...agent-patterns-plugin-v2.15.0) (2026-04-21)


### Features

* **agent-patterns-plugin:** add parallel-agent-dispatch skill ([#1101](https://github.com/laurigates/claude-plugins/issues/1101)) ([e6841b6](https://github.com/laurigates/claude-plugins/commit/e6841b6ca1f0d069ec4f843863dd66e33c54eb40))

## [2.14.0](https://github.com/laurigates/claude-plugins/compare/agent-patterns-plugin-v2.13.0...agent-patterns-plugin-v2.14.0) (2026-04-19)


### Features

* make skills discoverable by Claude's auto-invocation ([#1090](https://github.com/laurigates/claude-plugins/issues/1090)) ([cded1da](https://github.com/laurigates/claude-plugins/commit/cded1da1ebaf350cba1285b58ecadbbaa0eb01f6))

## [2.13.0](https://github.com/laurigates/claude-plugins/compare/agent-patterns-plugin-v2.12.2...agent-patterns-plugin-v2.13.0) (2026-04-18)


### Features

* **agent-patterns-plugin:** add preflight checklist, refactor case study, and out-of-scope protocol ([#1082](https://github.com/laurigates/claude-plugins/issues/1082)) ([88c52b2](https://github.com/laurigates/claude-plugins/commit/88c52b27c0afd294a970a30b07590e56be2d0700))

## [2.12.2](https://github.com/laurigates/claude-plugins/compare/agent-patterns-plugin-v2.12.1...agent-patterns-plugin-v2.12.2) (2026-04-17)


### Documentation

* update Claude Opus model references to 4.7 ([#1052](https://github.com/laurigates/claude-plugins/issues/1052)) ([9ffadc5](https://github.com/laurigates/claude-plugins/commit/9ffadc553de069f47efebd4d2c54ff89e47649fd))

## [2.12.1](https://github.com/laurigates/claude-plugins/compare/agent-patterns-plugin-v2.12.0...agent-patterns-plugin-v2.12.1) (2026-04-08)


### Bug Fixes

* **blueprint-plugin:** remove model field from skills and fix invocation syntax ([#1007](https://github.com/laurigates/claude-plugins/issues/1007)) ([42e1e5b](https://github.com/laurigates/claude-plugins/commit/42e1e5b6c73d43e5de4b27cdee16e316de44d4c0))

## [2.12.0](https://github.com/laurigates/claude-plugins/compare/agent-patterns-plugin-v2.11.0...agent-patterns-plugin-v2.12.0) (2026-03-09)


### Features

* **rules:** update rules for Claude Code 2.1.63-2.1.71 changes ([#917](https://github.com/laurigates/claude-plugins/issues/917)) ([20341e8](https://github.com/laurigates/claude-plugins/commit/20341e871fe7e91eb79d51aa02ad7bc9003a93e1))

## [2.11.0](https://github.com/laurigates/claude-plugins/compare/agent-patterns-plugin-v2.10.0...agent-patterns-plugin-v2.11.0) (2026-03-08)


### Features

* **agent-patterns-plugin:** add plugin-settings skill ([#897](https://github.com/laurigates/claude-plugins/issues/897)) ([c42e574](https://github.com/laurigates/claude-plugins/commit/c42e574b8f525b79bdd15ceb3fb2b1d75a1e347e))

## [2.10.0](https://github.com/laurigates/claude-plugins/compare/agent-patterns-plugin-v2.9.0...agent-patterns-plugin-v2.10.0) (2026-03-05)


### Features

* standardize shell script conventions and add linting ([#892](https://github.com/laurigates/claude-plugins/issues/892)) ([0eba700](https://github.com/laurigates/claude-plugins/commit/0eba7009728418bdef6355bd91fc9ee50c6982a8))

## [2.9.0](https://github.com/laurigates/claude-plugins/compare/agent-patterns-plugin-v2.8.1...agent-patterns-plugin-v2.9.0) (2026-03-03)


### Features

* **agent-patterns-plugin:** add agent-teams skill ([#868](https://github.com/laurigates/claude-plugins/issues/868)) ([9af253e](https://github.com/laurigates/claude-plugins/commit/9af253e36f189a0f9550cfa5f19e38f9435d27cd)), closes [#860](https://github.com/laurigates/claude-plugins/issues/860)

## [2.8.1](https://github.com/laurigates/claude-plugins/compare/agent-patterns-plugin-v2.8.0...agent-patterns-plugin-v2.8.1) (2026-03-02)


### Documentation

* **rules:** update rules and skills for Claude Code 2.1.50-2.1.63 ([#859](https://github.com/laurigates/claude-plugins/issues/859)) ([6c66021](https://github.com/laurigates/claude-plugins/commit/6c66021fefa205abfc4f575229e3bbb9cdc6263a))

## [2.8.0](https://github.com/laurigates/claude-plugins/compare/agent-patterns-plugin-v2.7.2...agent-patterns-plugin-v2.8.0) (2026-02-27)


### Features

* add metadata fields to skill definitions across all plugins ([#828](https://github.com/laurigates/claude-plugins/issues/828)) ([59b3d1f](https://github.com/laurigates/claude-plugins/commit/59b3d1fadd8fd888f95ced8b071fb66cf6f9c825))
* add skill invocation control via user-invocable and disable-model-invocation frontmatter ([59b3d1f](https://github.com/laurigates/claude-plugins/commit/59b3d1fadd8fd888f95ced8b071fb66cf6f9c825))

## [2.7.2](https://github.com/laurigates/claude-plugins/compare/agent-patterns-plugin-v2.7.1...agent-patterns-plugin-v2.7.2) (2026-02-26)


### Documentation

* **hooks-plugin:** document Claude Code 2.1.50 hook system enhancements ([#813](https://github.com/laurigates/claude-plugins/issues/813)) ([92f1b1d](https://github.com/laurigates/claude-plugins/commit/92f1b1dda1ba03918f283f9961c7a161dd3fdf70)), closes [#798](https://github.com/laurigates/claude-plugins/issues/798)

## [2.7.1](https://github.com/laurigates/claude-plugins/compare/agent-patterns-plugin-v2.7.0...agent-patterns-plugin-v2.7.1) (2026-02-25)


### Bug Fixes

* **skills:** add missing args field to 57 skills with argument-hint ([#812](https://github.com/laurigates/claude-plugins/issues/812)) ([f670423](https://github.com/laurigates/claude-plugins/commit/f670423777d3d0e4edf52a1594ad82efaa13793e)), closes [#805](https://github.com/laurigates/claude-plugins/issues/805)

## [2.7.0](https://github.com/laurigates/claude-plugins/compare/agent-patterns-plugin-v2.6.2...agent-patterns-plugin-v2.7.0) (2026-02-18)


### Features

* introduce three-tier model palette (opus/sonnet/haiku) ([#709](https://github.com/laurigates/claude-plugins/issues/709)) ([2c1e9cc](https://github.com/laurigates/claude-plugins/commit/2c1e9ccff5d48c2b426beac5b3b38cd4576c79a0))

## [2.6.2](https://github.com/laurigates/claude-plugins/compare/agent-patterns-plugin-v2.6.1...agent-patterns-plugin-v2.6.2) (2026-02-15)


### Bug Fixes

* **agent-patterns-plugin:** use systemMessage for PreCompact hook output ([c887829](https://github.com/laurigates/claude-plugins/commit/c887829f229fdb60e54763f32b56cabf07890b58))
* refactor pre-compact primer hook output format to systemMessage ([#641](https://github.com/laurigates/claude-plugins/issues/641)) ([c887829](https://github.com/laurigates/claude-plugins/commit/c887829f229fdb60e54763f32b56cabf07890b58))

## [2.6.1](https://github.com/laurigates/claude-plugins/compare/agent-patterns-plugin-v2.6.0...agent-patterns-plugin-v2.6.1) (2026-02-12)


### Bug Fixes

* standardize skill name fields to kebab-case across all plugins ([72c0f83](https://github.com/laurigates/claude-plugins/commit/72c0f837a1b07004850c5906a30d619a79098f69))

## [2.6.0](https://github.com/laurigates/claude-plugins/compare/agent-patterns-plugin-v2.5.6...agent-patterns-plugin-v2.6.0) (2026-02-11)


### Features

* add required quality sections to refactored skills ([#544](https://github.com/laurigates/claude-plugins/issues/544)) ([342af54](https://github.com/laurigates/claude-plugins/commit/342af54af0f81fa50d239d06b32b353ddb7335fc))

## [2.5.6](https://github.com/laurigates/claude-plugins/compare/agent-patterns-plugin-v2.5.5...agent-patterns-plugin-v2.5.6) (2026-02-08)


### Bug Fixes

* update skill review dates to trigger release sync ([#489](https://github.com/laurigates/claude-plugins/issues/489)) ([ca20d06](https://github.com/laurigates/claude-plugins/commit/ca20d0667baaa31dfa805c7dc775a1828c515223))

## [2.5.5](https://github.com/laurigates/claude-plugins/compare/agent-patterns-plugin-v2.5.4...agent-patterns-plugin-v2.5.5) (2026-02-06)


### Bug Fixes

* **frontmatter:** resolve 83 validation errors across 75 files ([#434](https://github.com/laurigates/claude-plugins/issues/434)) ([5beb75e](https://github.com/laurigates/claude-plugins/commit/5beb75ed4b2cb0431d060bd7102903495c03c6c5))

## [2.5.5](https://github.com/laurigates/claude-plugins/compare/agent-patterns-plugin-v2.5.4...agent-patterns-plugin-v2.5.5) (2026-02-06)


### Bug Fixes

* **frontmatter:** resolve 83 validation errors across 75 files ([#434](https://github.com/laurigates/claude-plugins/issues/434)) ([5beb75e](https://github.com/laurigates/claude-plugins/commit/5beb75ed4b2cb0431d060bd7102903495c03c6c5))

## [2.5.4](https://github.com/laurigates/claude-plugins/compare/agent-patterns-plugin-v2.5.3...agent-patterns-plugin-v2.5.4) (2026-02-03)


### Bug Fixes

* remove shell operators from context commands in multiple plugins ([#326](https://github.com/laurigates/claude-plugins/issues/326)) ([b028f73](https://github.com/laurigates/claude-plugins/commit/b028f7385f66f8f063a95874840c51e553694205))

## [2.5.3](https://github.com/laurigates/claude-plugins/compare/agent-patterns-plugin-v2.5.2...agent-patterns-plugin-v2.5.3) (2026-02-02)


### Bug Fixes

* **agent-patterns-plugin:** block git writes for parallel agents to prevent conflicts ([#299](https://github.com/laurigates/claude-plugins/issues/299)) ([a2c2ce0](https://github.com/laurigates/claude-plugins/commit/a2c2ce07d67ead9b30470b398777be355672281b))

## [2.5.2](https://github.com/laurigates/claude-plugins/compare/agent-patterns-plugin-v2.5.1...agent-patterns-plugin-v2.5.2) (2026-02-01)


### Bug Fixes

* **agent-patterns-plugin:** make orchestrator enforcement opt-in instead of opt-out ([f607b7c](https://github.com/laurigates/claude-plugins/commit/f607b7c8141f6d11bef906f5f11b434284083677))

## [2.5.1](https://github.com/laurigates/claude-plugins/compare/agent-patterns-plugin-v2.5.0...agent-patterns-plugin-v2.5.1) (2026-02-01)


### Bug Fixes

* enforce granular Bash permissions across all plugins ([#267](https://github.com/laurigates/claude-plugins/issues/267)) ([afeb507](https://github.com/laurigates/claude-plugins/commit/afeb50754838c2923807c8f2a248b3798fd4281c))

## [2.5.0](https://github.com/laurigates/claude-plugins/compare/agent-patterns-plugin-v2.4.0...agent-patterns-plugin-v2.5.0) (2026-01-26)


### Features

* **agent-patterns-plugin:** add agentic-patterns.com as source skill ([#229](https://github.com/laurigates/claude-plugins/issues/229)) ([cbac971](https://github.com/laurigates/claude-plugins/commit/cbac97130222c63afb11dd3f7e2b90f057734fc3))

## [2.4.0](https://github.com/laurigates/claude-plugins/compare/agent-patterns-plugin-v2.3.0...agent-patterns-plugin-v2.4.0) (2026-01-23)


### Features

* add model specification to all skills and commands ([#131](https://github.com/laurigates/claude-plugins/issues/131)) ([81f2961](https://github.com/laurigates/claude-plugins/commit/81f296155b50864b8b1687b9eb18a9c2cbb08791))

## [2.3.0](https://github.com/laurigates/claude-plugins/compare/agent-patterns-plugin-v2.2.0...agent-patterns-plugin-v2.3.0) (2026-01-21)


### Features

* **agent-patterns-plugin:** add delegation-first skill for automatic task delegation ([76bb2ce](https://github.com/laurigates/claude-plugins/commit/76bb2ce4d5ea444183908c75db18979ce2851acf))

## [2.2.0](https://github.com/laurigates/claude-plugins/compare/agent-patterns-plugin-v2.1.0...agent-patterns-plugin-v2.2.0) (2026-01-20)


### Features

* implement Claude Code 2.1.7 changelog review updates (issue [#78](https://github.com/laurigates/claude-plugins/issues/78)) ([#112](https://github.com/laurigates/claude-plugins/issues/112)) ([e28d8de](https://github.com/laurigates/claude-plugins/commit/e28d8deec41d3e5070861a3f1c37e9c43f452cb4))

## [2.1.0](https://github.com/laurigates/claude-plugins/compare/agent-patterns-plugin-v2.0.1...agent-patterns-plugin-v2.1.0) (2026-01-15)


### Features

* **agent-patterns-plugin:** add claude-hooks-configuration skill ([#70](https://github.com/laurigates/claude-plugins/issues/70)) ([d97307a](https://github.com/laurigates/claude-plugins/commit/d97307ac33773792ee9e702916abefa87d2ffc7d))

## [2.0.1](https://github.com/laurigates/claude-plugins/compare/agent-patterns-plugin-v2.0.0...agent-patterns-plugin-v2.0.1) (2026-01-09)


### Bug Fixes

* sync plugin.json versions to match release-please manifest ([1ac44e1](https://github.com/laurigates/claude-plugins/commit/1ac44e1240eed27eb3f829edaaac9bc863634d89))

## [2.0.1](https://github.com/laurigates/claude-plugins/compare/agent-patterns-plugin-v2.0.0...agent-patterns-plugin-v2.0.1) (2026-01-09)


### Bug Fixes

* sync plugin.json versions to match release-please manifest ([1ac44e1](https://github.com/laurigates/claude-plugins/commit/1ac44e1240eed27eb3f829edaaac9bc863634d89))

## [2.0.0](https://github.com/laurigates/claude-plugins/compare/agent-patterns-plugin-v1.0.0...agent-patterns-plugin-v2.0.0) (2025-12-28)


### ⚠ BREAKING CHANGES

* **agent-patterns-plugin:** Rename @HANDOFF to @AGENT-HANDOFF-MARKER

### Code Refactoring

* **agent-patterns-plugin:** reorganize handoff markers system ([a0b06f8](https://github.com/laurigates/claude-plugins/commit/a0b06f85e3b3cb7a6ca7926d7940499a7460ef57))
