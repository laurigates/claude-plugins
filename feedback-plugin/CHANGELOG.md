# Changelog

## [1.6.8](https://github.com/laurigates/claude-plugins/compare/feedback-plugin-v1.6.7...feedback-plugin-v1.6.8) (2026-06-04)


### Bug Fixes

* resolve actionable open issues ([#1424](https://github.com/laurigates/claude-plugins/issues/1424), [#1425](https://github.com/laurigates/claude-plugins/issues/1425), [#1463](https://github.com/laurigates/claude-plugins/issues/1463)) ([#1500](https://github.com/laurigates/claude-plugins/issues/1500)) ([81afcee](https://github.com/laurigates/claude-plugins/commit/81afceeb292fed2feac4a0580f92501564c95866))

## [1.6.7](https://github.com/laurigates/claude-plugins/compare/feedback-plugin-v1.6.6...feedback-plugin-v1.6.7) (2026-05-25)


### Bug Fixes

* **feedback-plugin:** classify new BLOCKED-format hook events into specific signatures ([#1412](https://github.com/laurigates/claude-plugins/issues/1412)) ([48cc787](https://github.com/laurigates/claude-plugins/commit/48cc787f73ddf5b938f060e25978830c2783fe1f))

## [1.6.6](https://github.com/laurigates/claude-plugins/compare/feedback-plugin-v1.6.5...feedback-plugin-v1.6.6) (2026-05-22)


### Documentation

* **project-plugin:** document plan-mode flow in project-distill Step 4 ([#1364](https://github.com/laurigates/claude-plugins/issues/1364)) ([d345dfa](https://github.com/laurigates/claude-plugins/commit/d345dfaef5fe56617ebde5195fc4807fc704d8b2))

## [1.6.5](https://github.com/laurigates/claude-plugins/compare/feedback-plugin-v1.6.4...feedback-plugin-v1.6.5) (2026-05-14)


### Documentation

* **feedback-plugin:** codify dominance heuristic in feedback-session ([#1320](https://github.com/laurigates/claude-plugins/issues/1320)) ([f9fb8aa](https://github.com/laurigates/claude-plugins/commit/f9fb8aadcdbd1aecce3584521285cf1c4bdeaafd))

## [1.6.4](https://github.com/laurigates/claude-plugins/compare/feedback-plugin-v1.6.3...feedback-plugin-v1.6.4) (2026-05-14)


### Code Refactoring

* **feedback-plugin:** tighten skill descriptions for listing budget ([7e9f9a1](https://github.com/laurigates/claude-plugins/commit/7e9f9a16e6d5a20bbffa69e17bb8fc488b2ebc8d))

## [1.6.3](https://github.com/laurigates/claude-plugins/compare/feedback-plugin-v1.6.2...feedback-plugin-v1.6.3) (2026-05-09)


### Bug Fixes

* **feedback-plugin:** tolerate non-git cwd in feedback-session Context ([#1287](https://github.com/laurigates/claude-plugins/issues/1287)) ([a0a5b30](https://github.com/laurigates/claude-plugins/commit/a0a5b3052d446ed75b7c934d8db95f03fa7a4749))

## [1.6.2](https://github.com/laurigates/claude-plugins/compare/feedback-plugin-v1.6.1...feedback-plugin-v1.6.2) (2026-05-09)


### Documentation

* trim oversized SKILL.md descriptions across 41 plugins ([#1265](https://github.com/laurigates/claude-plugins/issues/1265)) ([e13d9f4](https://github.com/laurigates/claude-plugins/commit/e13d9f46a010559082c6d5eb61b0cb891843bf97))

## [1.6.1](https://github.com/laurigates/claude-plugins/compare/feedback-plugin-v1.6.0...feedback-plugin-v1.6.1) (2026-05-07)


### Bug Fixes

* **agents:** bake tool-selection rules into agent definitions ([#1262](https://github.com/laurigates/claude-plugins/issues/1262)) ([a9b128a](https://github.com/laurigates/claude-plugins/commit/a9b128af9238f2c20cc3c4efb92ec86c06a39752))

## [1.6.0](https://github.com/laurigates/claude-plugins/compare/feedback-plugin-v1.5.0...feedback-plugin-v1.6.0) (2026-05-04)


### Features

* **rules:** re-enable model: parameter for skills at the extremes ([#1232](https://github.com/laurigates/claude-plugins/issues/1232)) ([5abba3a](https://github.com/laurigates/claude-plugins/commit/5abba3aa13a9b7574e6a7aadd1a9dd7ca4dea812))

## [1.5.0](https://github.com/laurigates/claude-plugins/compare/feedback-plugin-v1.4.0...feedback-plugin-v1.5.0) (2026-04-28)


### Features

* **project-plugin:** document auto-mode policy for distill/feedback Step 4 ([#1196](https://github.com/laurigates/claude-plugins/issues/1196)) ([ef60a52](https://github.com/laurigates/claude-plugins/commit/ef60a524ef381121391808e6eedbbd0a21586563))


### Bug Fixes

* **feedback-plugin:** require human classification before plan-mode rule lands ([#1200](https://github.com/laurigates/claude-plugins/issues/1200)) ([454c947](https://github.com/laurigates/claude-plugins/commit/454c9471f6bcfc5a468ffd3eb3da017730e2b83e))

## [1.4.0](https://github.com/laurigates/claude-plugins/compare/feedback-plugin-v1.3.3...feedback-plugin-v1.4.0) (2026-04-25)


### Features

* **feedback-plugin:** auto-suggest plugin source repo when cwd has no remote ([#1145](https://github.com/laurigates/claude-plugins/issues/1145)) ([6c811c2](https://github.com/laurigates/claude-plugins/commit/6c811c2e4cc875ffb17620cc59ee6a639ff92f85))

## [1.3.3](https://github.com/laurigates/claude-plugins/compare/feedback-plugin-v1.3.2...feedback-plugin-v1.3.3) (2026-04-24)


### Bug Fixes

* **feedback-plugin,git-plugin,github-actions-plugin:** remove gh list from context ([#1123](https://github.com/laurigates/claude-plugins/issues/1123)) ([8ad0b71](https://github.com/laurigates/claude-plugins/commit/8ad0b7140028a749dd61027f80eb0c75bb6f8bfb))

## [1.3.2](https://github.com/laurigates/claude-plugins/compare/feedback-plugin-v1.3.1...feedback-plugin-v1.3.2) (2026-04-18)


### Bug Fixes

* **feedback-plugin:** resolve the four open friction-learner issues ([#1084](https://github.com/laurigates/claude-plugins/issues/1084)) ([7286bc0](https://github.com/laurigates/claude-plugins/commit/7286bc0740405597ea1b3ec45cd1ba12f10a9c91))

## [1.3.1](https://github.com/laurigates/claude-plugins/compare/feedback-plugin-v1.3.0...feedback-plugin-v1.3.1) (2026-04-17)


### Bug Fixes

* **feedback-plugin:** handle IaC-managed labels and add --target-repo parameter ([#1054](https://github.com/laurigates/claude-plugins/issues/1054)) ([20bdd14](https://github.com/laurigates/claude-plugins/commit/20bdd14c034a05c4c9f13bedaab5f076965bca6f))

## [1.3.0](https://github.com/laurigates/claude-plugins/compare/feedback-plugin-v1.2.1...feedback-plugin-v1.3.0) (2026-04-17)


### Features

* **feedback-plugin:** add friction-learner agent for weekly session analysis ([#1051](https://github.com/laurigates/claude-plugins/issues/1051)) ([b6301a4](https://github.com/laurigates/claude-plugins/commit/b6301a4d5766d07ba5b25c1f059d7de816a47227))

## [1.2.1](https://github.com/laurigates/claude-plugins/compare/feedback-plugin-v1.2.0...feedback-plugin-v1.2.1) (2026-04-08)


### Bug Fixes

* **blueprint-plugin:** remove model field from skills and fix invocation syntax ([#1007](https://github.com/laurigates/claude-plugins/issues/1007)) ([42e1e5b](https://github.com/laurigates/claude-plugins/commit/42e1e5b6c73d43e5de4b27cdee16e316de44d4c0))

## [1.2.0](https://github.com/laurigates/claude-plugins/compare/feedback-plugin-v1.1.2...feedback-plugin-v1.2.0) (2026-02-27)


### Features

* add metadata fields to skill definitions across all plugins ([#828](https://github.com/laurigates/claude-plugins/issues/828)) ([59b3d1f](https://github.com/laurigates/claude-plugins/commit/59b3d1fadd8fd888f95ced8b071fb66cf6f9c825))
* add skill invocation control via user-invocable and disable-model-invocation frontmatter ([59b3d1f](https://github.com/laurigates/claude-plugins/commit/59b3d1fadd8fd888f95ced8b071fb66cf6f9c825))

## [1.1.2](https://github.com/laurigates/claude-plugins/compare/feedback-plugin-v1.1.1...feedback-plugin-v1.1.2) (2026-02-25)


### Bug Fixes

* replace git remote get-url with git remote -v for verbose output ([#804](https://github.com/laurigates/claude-plugins/issues/804)) ([e39407a](https://github.com/laurigates/claude-plugins/commit/e39407a366d2d0ba431df0f456074b847073eea8))
* **skills:** replace git remote get-url origin with git remote -v in context commands ([e39407a](https://github.com/laurigates/claude-plugins/commit/e39407a366d2d0ba431df0f456074b847073eea8))

## [1.1.1](https://github.com/laurigates/claude-plugins/compare/feedback-plugin-v1.1.0...feedback-plugin-v1.1.1) (2026-02-23)


### Bug Fixes

* remove 2&gt;/dev/null from context commands across all plugins ([#792](https://github.com/laurigates/claude-plugins/issues/792)) ([c72e67e](https://github.com/laurigates/claude-plugins/commit/c72e67ee37e809449f0e6282c48fac01363a59fd))

## [1.1.0](https://github.com/laurigates/claude-plugins/compare/feedback-plugin-v1.0.0...feedback-plugin-v1.1.0) (2026-02-18)


### Features

* **feedback-plugin:** add session feedback analysis skill ([#708](https://github.com/laurigates/claude-plugins/issues/708)) ([a25689d](https://github.com/laurigates/claude-plugins/commit/a25689d8e658d4a508f79fad7f1f89f38266141d))

## [1.1.0](https://github.com/laurigates/claude-plugins/compare/feedback-plugin-v1.0.0...feedback-plugin-v1.1.0) (2026-02-18)


### Features

* **feedback-plugin:** add session feedback analysis skill ([#708](https://github.com/laurigates/claude-plugins/issues/708)) ([a25689d](https://github.com/laurigates/claude-plugins/commit/a25689d8e658d4a508f79fad7f1f89f38266141d))

## [1.1.0](https://github.com/laurigates/claude-plugins/compare/feedback-plugin-v1.0.0...feedback-plugin-v1.1.0) (2026-02-18)


### Features

* **feedback-plugin:** add session feedback analysis skill ([#708](https://github.com/laurigates/claude-plugins/issues/708)) ([a25689d](https://github.com/laurigates/claude-plugins/commit/a25689d8e658d4a508f79fad7f1f89f38266141d))
