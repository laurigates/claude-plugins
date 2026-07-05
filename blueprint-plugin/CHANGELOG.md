# Changelog

## [3.39.1](https://github.com/laurigates/claude-plugins/compare/blueprint-plugin-v3.39.0...blueprint-plugin-v3.39.1) (2026-07-05)


### Documentation

* **blueprint-plugin:** cross-reference session-end as a drain-wave trigger ([#1999](https://github.com/laurigates/claude-plugins/issues/1999)) ([85420ff](https://github.com/laurigates/claude-plugins/commit/85420ff15c9a6594ed2bec2ad72517a23b98fae6))

## [3.39.0](https://github.com/laurigates/claude-plugins/compare/blueprint-plugin-v3.38.1...blueprint-plugin-v3.39.0) (2026-07-05)


### Features

* **blueprint-plugin:** guard ADR-number collisions in blueprint-adr-validate ([#1963](https://github.com/laurigates/claude-plugins/issues/1963)) ([52c6e78](https://github.com/laurigates/claude-plugins/commit/52c6e7831fee0027da201957b20dcff7f7fae019))

## [3.38.1](https://github.com/laurigates/claude-plugins/compare/blueprint-plugin-v3.38.0...blueprint-plugin-v3.38.1) (2026-07-04)


### Bug Fixes

* **blueprint-plugin:** clarify work-order handoff is user-invocable ([#1946](https://github.com/laurigates/claude-plugins/issues/1946)) ([8d1f86b](https://github.com/laurigates/claude-plugins/commit/8d1f86be516e6c17099fe39e6226da5a3571fd8d)), closes [#1906](https://github.com/laurigates/claude-plugins/issues/1906)

## [3.38.0](https://github.com/laurigates/claude-plugins/compare/blueprint-plugin-v3.37.2...blueprint-plugin-v3.38.0) (2026-07-03)


### Features

* **blueprint-plugin:** retarget curated AI context from ai_docs to .claude/rules/ ([#1927](https://github.com/laurigates/claude-plugins/issues/1927)) ([6e47edd](https://github.com/laurigates/claude-plugins/commit/6e47eddbe5a26f938cb5aae51638c07c5266fc09))

## [3.37.2](https://github.com/laurigates/claude-plugins/compare/blueprint-plugin-v3.37.1...blueprint-plugin-v3.37.2) (2026-06-22)


### Bug Fixes

* **blueprint-plugin:** scope blueprint-init rules to generated_rules_path and gate migrate default ([#1739](https://github.com/laurigates/claude-plugins/issues/1739)) ([865601b](https://github.com/laurigates/claude-plugins/commit/865601bcc2ea072dea2f5a2f362d4a6cd30f7265))

## [3.37.1](https://github.com/laurigates/claude-plugins/compare/blueprint-plugin-v3.37.0...blueprint-plugin-v3.37.1) (2026-06-20)


### Bug Fixes

* **hooks-plugin:** guard test/hook mktemp -d sandboxes against shared-checkout git leak ([#1719](https://github.com/laurigates/claude-plugins/issues/1719)) ([448b212](https://github.com/laurigates/claude-plugins/commit/448b2127a7240136dffd721ad1309c2375cc0814))

## [3.37.0](https://github.com/laurigates/claude-plugins/compare/blueprint-plugin-v3.36.2...blueprint-plugin-v3.37.0) (2026-06-18)


### Features

* **scripts:** context-command execution harness + sweep 122 fragile Context commands ([#1690](https://github.com/laurigates/claude-plugins/issues/1690)) ([609342f](https://github.com/laurigates/claude-plugins/commit/609342f2c5b6b5f2ee555f83dbac1f5f3dd1f93d))

## [3.36.2](https://github.com/laurigates/claude-plugins/compare/blueprint-plugin-v3.36.1...blueprint-plugin-v3.36.2) (2026-06-14)


### Documentation

* **blueprint-plugin:** mark merged cues live in registry ([#1635](https://github.com/laurigates/claude-plugins/issues/1635)) ([a0e1e61](https://github.com/laurigates/claude-plugins/commit/a0e1e6175ac720fc3d2ebd512c86f9601e978df5))

## [3.36.1](https://github.com/laurigates/claude-plugins/compare/blueprint-plugin-v3.36.0...blueprint-plugin-v3.36.1) (2026-06-13)


### Documentation

* **blueprint-plugin:** add behavioral-cue registry ([#1624](https://github.com/laurigates/claude-plugins/issues/1624)) ([e967986](https://github.com/laurigates/claude-plugins/commit/e9679862677f3932c6fd4925e5847ccdf1225a6b))

## [3.36.0](https://github.com/laurigates/claude-plugins/compare/blueprint-plugin-v3.35.0...blueprint-plugin-v3.36.0) (2026-06-13)


### Features

* **blueprint-plugin:** widen structural-cue detection beyond manifests + export lines ([#1617](https://github.com/laurigates/claude-plugins/issues/1617)) ([98677a5](https://github.com/laurigates/claude-plugins/commit/98677a5c5990d066cb17eb96e472fa020664d1db))

## [3.35.0](https://github.com/laurigates/claude-plugins/compare/blueprint-plugin-v3.34.3...blueprint-plugin-v3.35.0) (2026-06-13)


### Features

* **blueprint-plugin:** add structural-change cue PostToolUse hook ([#1611](https://github.com/laurigates/claude-plugins/issues/1611)) ([293a27a](https://github.com/laurigates/claude-plugins/commit/293a27a6341fa5cef24723f8c84abbca9be98bf6))

## [3.34.3](https://github.com/laurigates/claude-plugins/compare/blueprint-plugin-v3.34.2...blueprint-plugin-v3.34.3) (2026-06-13)


### Bug Fixes

* **skills:** rename 45 skill.md files to canonical SKILL.md ([#1608](https://github.com/laurigates/claude-plugins/issues/1608)) ([786b701](https://github.com/laurigates/claude-plugins/commit/786b701ee78134e31251f8c69dc58c34e4ccbb14))

## [3.34.2](https://github.com/laurigates/claude-plugins/compare/blueprint-plugin-v3.34.1...blueprint-plugin-v3.34.2) (2026-06-10)


### Code Refactoring

* **blueprint-plugin:** extract feature-tracker-sync, sync-ids, derive-tests procedures to scripts + regression tests ([#1568](https://github.com/laurigates/claude-plugins/issues/1568)) ([2b15d14](https://github.com/laurigates/claude-plugins/commit/2b15d14a2a1f6bdd70ad9286d22d517628ccc874))

## [3.34.1](https://github.com/laurigates/claude-plugins/compare/blueprint-plugin-v3.34.0...blueprint-plugin-v3.34.1) (2026-05-29)


### Code Refactoring

* **blueprint-plugin:** fold derive-prd + derive-adr into derive-plans ([#1453](https://github.com/laurigates/claude-plugins/issues/1453)) ([8777bcb](https://github.com/laurigates/claude-plugins/commit/8777bcbe072a0c0426b6cc38e941f2bb362bb6dd))

## [3.34.0](https://github.com/laurigates/claude-plugins/compare/blueprint-plugin-v3.33.3...blueprint-plugin-v3.34.0) (2026-05-24)


### Features

* **hooks-plugin:** add SessionStart drift-nudge architecture ([#1401](https://github.com/laurigates/claude-plugins/issues/1401)) ([47815e2](https://github.com/laurigates/claude-plugins/commit/47815e2035923e9c714142597cd6ed4ad43e9f7e))

## [3.33.3](https://github.com/laurigates/claude-plugins/compare/blueprint-plugin-v3.33.2...blueprint-plugin-v3.33.3) (2026-05-22)


### Bug Fixes

* **blueprint-plugin:** unify ADR/PRD/PRP/TRP layout at top-level docs/ ([#1373](https://github.com/laurigates/claude-plugins/issues/1373)) ([97cbbab](https://github.com/laurigates/claude-plugins/commit/97cbbab49dce3bc8ae94b15916e4ed1f88914441))

## [3.33.2](https://github.com/laurigates/claude-plugins/compare/blueprint-plugin-v3.33.1...blueprint-plugin-v3.33.2) (2026-05-22)


### Bug Fixes

* **blueprint-plugin:** infer feature status from working tree and git history ([#1368](https://github.com/laurigates/claude-plugins/issues/1368)) ([852ec61](https://github.com/laurigates/claude-plugins/commit/852ec613d12bf4587bf5729fce3e3a61a7876163))
* **blueprint-plugin:** require paths frontmatter on derived rules ([#1371](https://github.com/laurigates/claude-plugins/issues/1371)) ([71bdb7f](https://github.com/laurigates/claude-plugins/commit/71bdb7f1dc95545091fcd17d029bd8c7e646dda0))

## [3.33.1](https://github.com/laurigates/claude-plugins/compare/blueprint-plugin-v3.33.0...blueprint-plugin-v3.33.1) (2026-05-14)


### Code Refactoring

* **blueprint-plugin:** tighten skill descriptions for listing budget ([be877cd](https://github.com/laurigates/claude-plugins/commit/be877cdbb2a97126bd22228f2061ef0604eb1a5f))

## [3.33.0](https://github.com/laurigates/claude-plugins/compare/blueprint-plugin-v3.32.1...blueprint-plugin-v3.33.0) (2026-05-09)


### Features

* **plugins:** add check_skill_size() lint and trim 4 oversized SKILL.md bodies ([#1284](https://github.com/laurigates/claude-plugins/issues/1284)) ([20c97c9](https://github.com/laurigates/claude-plugins/commit/20c97c93337d52e739ab3619a6d6c473a89903b6))

## [3.32.1](https://github.com/laurigates/claude-plugins/compare/blueprint-plugin-v3.32.0...blueprint-plugin-v3.32.1) (2026-05-09)


### Documentation

* trim oversized SKILL.md descriptions across 41 plugins ([#1265](https://github.com/laurigates/claude-plugins/issues/1265)) ([e13d9f4](https://github.com/laurigates/claude-plugins/commit/e13d9f46a010559082c6d5eb61b0cb891843bf97))

## [3.32.0](https://github.com/laurigates/claude-plugins/compare/blueprint-plugin-v3.31.2...blueprint-plugin-v3.32.0) (2026-05-04)


### Features

* **rules:** re-enable model: parameter for skills at the extremes ([#1232](https://github.com/laurigates/claude-plugins/issues/1232)) ([5abba3a](https://github.com/laurigates/claude-plugins/commit/5abba3aa13a9b7574e6a7aadd1a9dd7ca4dea812))

## [3.31.2](https://github.com/laurigates/claude-plugins/compare/blueprint-plugin-v3.31.1...blueprint-plugin-v3.31.2) (2026-05-04)


### Bug Fixes

* **blueprint-plugin:** hoist Steps content out of dropped headings ([#1230](https://github.com/laurigates/claude-plugins/issues/1230)) ([d16b336](https://github.com/laurigates/claude-plugins/commit/d16b3368e9c95f2cbc4400d30a0e85698f91b3de))

## [3.31.1](https://github.com/laurigates/claude-plugins/compare/blueprint-plugin-v3.31.0...blueprint-plugin-v3.31.1) (2026-04-27)


### Documentation

* **blueprint-plugin:** refresh docs to match current skill set ([#1197](https://github.com/laurigates/claude-plugins/issues/1197)) ([97c99e0](https://github.com/laurigates/claude-plugins/commit/97c99e0d95c1a8ca1b4ee69a4053ae07325e6b3d))

## [3.31.0](https://github.com/laurigates/claude-plugins/compare/blueprint-plugin-v3.30.2...blueprint-plugin-v3.31.0) (2026-04-25)


### Features

* **blueprint-plugin:** add story-audit and story-reconcile skills ([#1173](https://github.com/laurigates/claude-plugins/issues/1173)) ([3ea17aa](https://github.com/laurigates/claude-plugins/commit/3ea17aac3a7cad519fdd64fa421823fbc6142c3d))

## [3.30.2](https://github.com/laurigates/claude-plugins/compare/blueprint-plugin-v3.30.1...blueprint-plugin-v3.30.2) (2026-04-25)


### Bug Fixes

* **skills:** convert When to Use sections to required table format ([#1192](https://github.com/laurigates/claude-plugins/issues/1192)) ([4a52cb4](https://github.com/laurigates/claude-plugins/commit/4a52cb4f5cbc459e5df78d361891a91bbe1496ec))

## [3.30.1](https://github.com/laurigates/claude-plugins/compare/blueprint-plugin-v3.30.0...blueprint-plugin-v3.30.1) (2026-04-25)


### Documentation

* **blueprint-plugin:** standardise When to Use tables ([#1171](https://github.com/laurigates/claude-plugins/issues/1171)) ([f5eec8f](https://github.com/laurigates/claude-plugins/commit/f5eec8f59b43b691a0c1e7840af504c0c2e7c0ce)), closes [#1156](https://github.com/laurigates/claude-plugins/issues/1156)

## [3.30.0](https://github.com/laurigates/claude-plugins/compare/blueprint-plugin-v3.29.0...blueprint-plugin-v3.30.0) (2026-04-25)


### Features

* **blueprint-plugin:** add taskwarrior-sidecar mode to feature-tracker-sync ([#1147](https://github.com/laurigates/claude-plugins/issues/1147)) ([4e8020a](https://github.com/laurigates/claude-plugins/commit/4e8020aad4d14228f8cf7afdfb9333f95da21606))

## [3.29.0](https://github.com/laurigates/claude-plugins/compare/blueprint-plugin-v3.28.1...blueprint-plugin-v3.29.0) (2026-04-24)


### Features

* **blueprint-plugin:** add blueprint-docs-currency skill + claude-plugins docs-currency rule ([#1135](https://github.com/laurigates/claude-plugins/issues/1135)) ([b2e6d9b](https://github.com/laurigates/claude-plugins/commit/b2e6d9bc8e1b7154498b866d0c46f46907a5afd2))

## [3.28.1](https://github.com/laurigates/claude-plugins/compare/blueprint-plugin-v3.28.0...blueprint-plugin-v3.28.1) (2026-04-22)


### Bug Fixes

* **git-plugin,blueprint-plugin:** add label pre-check before --add-label calls ([7cbed31](https://github.com/laurigates/claude-plugins/commit/7cbed3146b21034fa749452e4b380324cc0f812c))

## [3.28.0](https://github.com/laurigates/claude-plugins/compare/blueprint-plugin-v3.27.1...blueprint-plugin-v3.28.0) (2026-04-19)


### Features

* make skills discoverable by Claude's auto-invocation ([#1090](https://github.com/laurigates/claude-plugins/issues/1090)) ([cded1da](https://github.com/laurigates/claude-plugins/commit/cded1da1ebaf350cba1285b58ecadbbaa0eb01f6))

## [3.27.1](https://github.com/laurigates/claude-plugins/compare/blueprint-plugin-v3.27.0...blueprint-plugin-v3.27.1) (2026-04-18)


### Bug Fixes

* **blueprint-plugin:** canonicalize manifest.json filename across blueprint docs ([#1086](https://github.com/laurigates/claude-plugins/issues/1086)) ([b08a387](https://github.com/laurigates/claude-plugins/commit/b08a3873ab33c336260ff1d5e39fd987e47dcd45))

## [3.27.0](https://github.com/laurigates/claude-plugins/compare/blueprint-plugin-v3.26.1...blueprint-plugin-v3.27.0) (2026-04-17)


### Features

* non-interactive mode to blueprint-upgrade skill ([#1063](https://github.com/laurigates/claude-plugins/issues/1063)) ([0d1bb74](https://github.com/laurigates/claude-plugins/commit/0d1bb74842164fffe7f2ff49bf5cc5302922cf8d))

## [3.26.1](https://github.com/laurigates/claude-plugins/compare/blueprint-plugin-v3.26.0...blueprint-plugin-v3.26.1) (2026-04-16)


### Bug Fixes

* **blueprint-plugin:** advertise v3.3.0 as upgrade target ([#1048](https://github.com/laurigates/claude-plugins/issues/1048)) ([ca5db69](https://github.com/laurigates/claude-plugins/commit/ca5db694e975396aa18cbeaa7503675ea2821272)), closes [#1026](https://github.com/laurigates/claude-plugins/issues/1026)

## [3.26.0](https://github.com/laurigates/claude-plugins/compare/blueprint-plugin-v3.25.2...blueprint-plugin-v3.26.0) (2026-04-16)


### Features

* **blueprint-plugin:** configurable output path for generated rules ([#1046](https://github.com/laurigates/claude-plugins/issues/1046)) ([e0b37bf](https://github.com/laurigates/claude-plugins/commit/e0b37bf4c64cca772f450dbb45e81734110bf978)), closes [#1043](https://github.com/laurigates/claude-plugins/issues/1043) [#1040](https://github.com/laurigates/claude-plugins/issues/1040)

## [3.25.2](https://github.com/laurigates/claude-plugins/compare/blueprint-plugin-v3.25.1...blueprint-plugin-v3.25.2) (2026-04-15)


### Documentation

* **plugins:** add flow diagrams for router and pipeline plugins ([#1034](https://github.com/laurigates/claude-plugins/issues/1034)) ([a5e0e08](https://github.com/laurigates/claude-plugins/commit/a5e0e087495f0e835c3ad7e5dcf5bf7f4e61ad02))

## [3.25.1](https://github.com/laurigates/claude-plugins/compare/blueprint-plugin-v3.25.0...blueprint-plugin-v3.25.1) (2026-04-08)


### Bug Fixes

* **blueprint-plugin:** remove model field from skills and fix invocation syntax ([#1007](https://github.com/laurigates/claude-plugins/issues/1007)) ([42e1e5b](https://github.com/laurigates/claude-plugins/commit/42e1e5b6c73d43e5de4b27cdee16e316de44d4c0))

## [3.25.0](https://github.com/laurigates/claude-plugins/compare/blueprint-plugin-v3.24.1...blueprint-plugin-v3.25.0) (2026-03-12)


### Features

* auto-sync registry and unified ID validation for blueprint docs ([#934](https://github.com/laurigates/claude-plugins/issues/934)) ([5a494c4](https://github.com/laurigates/claude-plugins/commit/5a494c453ac07f81b053549c789a7cc67ba7d9ce))

## [3.24.1](https://github.com/laurigates/claude-plugins/compare/blueprint-plugin-v3.24.0...blueprint-plugin-v3.24.1) (2026-03-10)


### Bug Fixes

* **skills:** use find -exec in context commands for missing file resilience ([#919](https://github.com/laurigates/claude-plugins/issues/919)) ([9520d25](https://github.com/laurigates/claude-plugins/commit/9520d250132a293833c3604ade47f5b547de28f1))

## [3.24.0](https://github.com/laurigates/claude-plugins/compare/blueprint-plugin-v3.23.0...blueprint-plugin-v3.24.0) (2026-03-07)


### Features

* **blueprint-plugin:** add path scoping to derive-rules skill ([#902](https://github.com/laurigates/claude-plugins/issues/902)) ([2dc5706](https://github.com/laurigates/claude-plugins/commit/2dc5706c8c31be2a43b15eb3ef9d66e76b9de66c))

## [3.23.0](https://github.com/laurigates/claude-plugins/compare/blueprint-plugin-v3.22.2...blueprint-plugin-v3.23.0) (2026-03-05)


### Features

* standardize shell script conventions and add linting ([#892](https://github.com/laurigates/claude-plugins/issues/892)) ([0eba700](https://github.com/laurigates/claude-plugins/commit/0eba7009728418bdef6355bd91fc9ee50c6982a8))

## [3.22.2](https://github.com/laurigates/claude-plugins/compare/blueprint-plugin-v3.22.1...blueprint-plugin-v3.22.2) (2026-03-04)


### Bug Fixes

* haiku model incompatibility with AskUserQuestion tool ([#881](https://github.com/laurigates/claude-plugins/issues/881)) ([c09e400](https://github.com/laurigates/claude-plugins/commit/c09e40031e2eef7fa78640ee1d8327a0f18bbe64))

## [3.22.1](https://github.com/laurigates/claude-plugins/compare/blueprint-plugin-v3.22.0...blueprint-plugin-v3.22.1) (2026-03-01)


### Bug Fixes

* replace test -f/-d with find in context commands ([#850](https://github.com/laurigates/claude-plugins/issues/850)) ([a236ac8](https://github.com/laurigates/claude-plugins/commit/a236ac80ab81ce37878268b2ad76f7ad6d4aa5fb))

## [3.22.0](https://github.com/laurigates/claude-plugins/compare/blueprint-plugin-v3.21.0...blueprint-plugin-v3.22.0) (2026-02-27)


### Features

* add safety hooks for Terraform, Kubernetes, Git, and Blueprint plugins ([#835](https://github.com/laurigates/claude-plugins/issues/835)) ([d4d86a0](https://github.com/laurigates/claude-plugins/commit/d4d86a03b96d99642f341effb8f3999df5246c8b))
* **blueprint-plugin:** add PreCompact hook for derivation workflow context ([d4d86a0](https://github.com/laurigates/claude-plugins/commit/d4d86a03b96d99642f341effb8f3999df5246c8b))
* **kubernetes-plugin:** add kubectl dry-run injection hook ([d4d86a0](https://github.com/laurigates/claude-plugins/commit/d4d86a03b96d99642f341effb8f3999df5246c8b))
* **terraform-plugin:** add terraform apply gate hook ([d4d86a0](https://github.com/laurigates/claude-plugins/commit/d4d86a03b96d99642f341effb8f3999df5246c8b))

## [3.21.0](https://github.com/laurigates/claude-plugins/compare/blueprint-plugin-v3.20.0...blueprint-plugin-v3.21.0) (2026-02-27)


### Features

* **hooks-plugin:** add LLM-powered prompt and agent hooks documentation and examples ([#834](https://github.com/laurigates/claude-plugins/issues/834)) ([203d1d9](https://github.com/laurigates/claude-plugins/commit/203d1d9494e37771b1186f0e50948c75109c8fe6))

## [3.20.0](https://github.com/laurigates/claude-plugins/compare/blueprint-plugin-v3.19.3...blueprint-plugin-v3.20.0) (2026-02-27)


### Features

* add metadata fields to skill definitions across all plugins ([#828](https://github.com/laurigates/claude-plugins/issues/828)) ([59b3d1f](https://github.com/laurigates/claude-plugins/commit/59b3d1fadd8fd888f95ced8b071fb66cf6f9c825))
* add skill invocation control via user-invocable and disable-model-invocation frontmatter ([59b3d1f](https://github.com/laurigates/claude-plugins/commit/59b3d1fadd8fd888f95ced8b071fb66cf6f9c825))

## [3.19.3](https://github.com/laurigates/claude-plugins/compare/blueprint-plugin-v3.19.2...blueprint-plugin-v3.19.3) (2026-02-26)


### Bug Fixes

* **scripts:** enhance context command linter with stderr safety checks and fix violations ([#819](https://github.com/laurigates/claude-plugins/issues/819)) ([2975b9b](https://github.com/laurigates/claude-plugins/commit/2975b9b0bf6698bdecf627e3d28bad06fde03cd1))

## [3.19.2](https://github.com/laurigates/claude-plugins/compare/blueprint-plugin-v3.19.1...blueprint-plugin-v3.19.2) (2026-02-23)


### Bug Fixes

* remove 2&gt;/dev/null from context commands across all plugins ([#792](https://github.com/laurigates/claude-plugins/issues/792)) ([c72e67e](https://github.com/laurigates/claude-plugins/commit/c72e67ee37e809449f0e6282c48fac01363a59fd))

## [3.19.1](https://github.com/laurigates/claude-plugins/compare/blueprint-plugin-v3.19.0...blueprint-plugin-v3.19.1) (2026-02-22)


### Bug Fixes

* **ci:** fix version extraction in changelog-review workflow ([#779](https://github.com/laurigates/claude-plugins/issues/779)) ([dfe620c](https://github.com/laurigates/claude-plugins/commit/dfe620c615f74b09c9eb6b408ef0f254ef497450))

## [3.19.0](https://github.com/laurigates/claude-plugins/compare/blueprint-plugin-v3.18.0...blueprint-plugin-v3.19.0) (2026-02-20)


### Features

* **blueprint-plugin:** revise init questions for streamlined onboarding ([1942c1e](https://github.com/laurigates/claude-plugins/commit/1942c1e51d796afbf1225cddf9ab080351bd75e2))


### Code Refactoring

* **blueprint-plugin:** blueprint-init workflow and simplify user prompts ([#768](https://github.com/laurigates/claude-plugins/issues/768)) ([1942c1e](https://github.com/laurigates/claude-plugins/commit/1942c1e51d796afbf1225cddf9ab080351bd75e2))

## [3.18.0](https://github.com/laurigates/claude-plugins/compare/blueprint-plugin-v3.17.0...blueprint-plugin-v3.18.0) (2026-02-18)


### Features

* introduce three-tier model palette (opus/sonnet/haiku) ([#709](https://github.com/laurigates/claude-plugins/issues/709)) ([2c1e9cc](https://github.com/laurigates/claude-plugins/commit/2c1e9ccff5d48c2b426beac5b3b38cd4576c79a0))

## [3.17.0](https://github.com/laurigates/claude-plugins/compare/blueprint-plugin-v3.16.6...blueprint-plugin-v3.17.0) (2026-02-17)


### Features

* **blueprint-plugin:** add task registry for operational metadata tracking ([#706](https://github.com/laurigates/claude-plugins/issues/706)) ([565540d](https://github.com/laurigates/claude-plugins/commit/565540dbfa37c14154b0c23320306089054601b7))

## [3.16.6](https://github.com/laurigates/claude-plugins/compare/blueprint-plugin-v3.16.5...blueprint-plugin-v3.16.6) (2026-02-15)


### Bug Fixes

* remove pipe/ls operators from context commands and add CI linting ([#653](https://github.com/laurigates/claude-plugins/issues/653)) ([7a01eef](https://github.com/laurigates/claude-plugins/commit/7a01eef21495ed6243277fbaa88082b7ecabc793))

## [3.16.5](https://github.com/laurigates/claude-plugins/compare/blueprint-plugin-v3.16.4...blueprint-plugin-v3.16.5) (2026-02-15)


### Bug Fixes

* replace broken context command patterns in skill files ([#644](https://github.com/laurigates/claude-plugins/issues/644)) ([440ba34](https://github.com/laurigates/claude-plugins/commit/440ba347bcc73a0512f74975cfd6b4af9fe8566e))

## [3.16.4](https://github.com/laurigates/claude-plugins/compare/blueprint-plugin-v3.16.3...blueprint-plugin-v3.16.4) (2026-02-14)


### Code Refactoring

* extract detailed content to REFERENCE.md files ([#605](https://github.com/laurigates/claude-plugins/issues/605)) ([7efbd83](https://github.com/laurigates/claude-plugins/commit/7efbd83b9a2b1ef67be702206396ba6d8102684d))

## [3.16.3](https://github.com/laurigates/claude-plugins/compare/blueprint-plugin-v3.16.2...blueprint-plugin-v3.16.3) (2026-02-14)


### Documentation

* **git-plugin:** add conventional commits standards ([#616](https://github.com/laurigates/claude-plugins/issues/616)) ([5b74389](https://github.com/laurigates/claude-plugins/commit/5b74389ecdf5223dd62368390ecd9b36ccb1596c))

## [3.16.2](https://github.com/laurigates/claude-plugins/compare/blueprint-plugin-v3.16.1...blueprint-plugin-v3.16.2) (2026-02-14)


### Code Refactoring

* restructure 11 skills to execution pattern ([#609](https://github.com/laurigates/claude-plugins/issues/609)) ([0aff44a](https://github.com/laurigates/claude-plugins/commit/0aff44ae5768e3cd3aedfed568137738fc298bbc))

## [3.16.1](https://github.com/laurigates/claude-plugins/compare/blueprint-plugin-v3.16.0...blueprint-plugin-v3.16.1) (2026-02-12)


### Bug Fixes

* standardize skill name fields to kebab-case across all plugins ([72c0f83](https://github.com/laurigates/claude-plugins/commit/72c0f837a1b07004850c5906a30d619a79098f69))

## [3.16.0](https://github.com/laurigates/claude-plugins/compare/blueprint-plugin-v3.15.0...blueprint-plugin-v3.16.0) (2026-02-12)


### Features

* **blueprint-plugin:** add v3.0→v3.1 migration and remove work-overview references ([e9849b0](https://github.com/laurigates/claude-plugins/commit/e9849b0a0d3d434432d32e68fee3498696fb09c8))

## [3.15.0](https://github.com/laurigates/claude-plugins/compare/blueprint-plugin-v3.14.2...blueprint-plugin-v3.15.0) (2026-02-09)


### Features

* **blueprint-plugin,documentation-plugin:** adapt skills to Claude Code auto memory and [@import](https://github.com/import) features ([f18e27b](https://github.com/laurigates/claude-plugins/commit/f18e27bb0b2261e2a829659b919ee0f5f4fb1a4e))

## [3.14.2](https://github.com/laurigates/claude-plugins/compare/blueprint-plugin-v3.14.1...blueprint-plugin-v3.14.2) (2026-02-08)


### Code Refactoring

* reframe negative guidance as positive guidance across skills ([7e755ee](https://github.com/laurigates/claude-plugins/commit/7e755ee1c32c39c124f3204a0d0a8d1d770e1573))

## [3.14.1](https://github.com/laurigates/claude-plugins/compare/blueprint-plugin-v3.14.0...blueprint-plugin-v3.14.1) (2026-02-08)


### Bug Fixes

* update skill review dates to trigger release sync ([#489](https://github.com/laurigates/claude-plugins/issues/489)) ([ca20d06](https://github.com/laurigates/claude-plugins/commit/ca20d0667baaa31dfa805c7dc775a1828c515223))

## [3.14.0](https://github.com/laurigates/claude-plugins/compare/blueprint-plugin-v3.13.1...blueprint-plugin-v3.14.0) (2026-02-07)


### Features

* **blueprint-plugin:** add dry-run/report-only modes to blueprint skills ([#463](https://github.com/laurigates/claude-plugins/issues/463)) ([91bedfc](https://github.com/laurigates/claude-plugins/commit/91bedfc1e75d42da0d0772679a0a8c2f881e46d4))

## [3.14.0](https://github.com/laurigates/claude-plugins/compare/blueprint-plugin-v3.13.1...blueprint-plugin-v3.14.0) (2026-02-07)


### Features

* **blueprint-plugin:** add dry-run/report-only modes to blueprint skills ([#463](https://github.com/laurigates/claude-plugins/issues/463)) ([91bedfc](https://github.com/laurigates/claude-plugins/commit/91bedfc1e75d42da0d0772679a0a8c2f881e46d4))

## [3.13.1](https://github.com/laurigates/claude-plugins/compare/blueprint-plugin-v3.13.0...blueprint-plugin-v3.13.1) (2026-02-06)


### Bug Fixes

* **frontmatter:** resolve 83 validation errors across 75 files ([#434](https://github.com/laurigates/claude-plugins/issues/434)) ([5beb75e](https://github.com/laurigates/claude-plugins/commit/5beb75ed4b2cb0431d060bd7102903495c03c6c5))

## [3.13.0](https://github.com/laurigates/claude-plugins/compare/blueprint-plugin-v3.12.0...blueprint-plugin-v3.13.0) (2026-02-06)


### Features

* **blueprint-plugin:** improve ADR/docs commands with programmatic listing pattern ([8d02b54](https://github.com/laurigates/claude-plugins/commit/8d02b54e7cc24e8ecf80b90d3aae25b844b270f5))

## [3.12.0](https://github.com/laurigates/claude-plugins/compare/blueprint-plugin-v3.11.0...blueprint-plugin-v3.12.0) (2026-02-05)


### Features

* **blueprint-plugin:** consolidate tracking files and add work-order auto-creation ([0cb7b59](https://github.com/laurigates/claude-plugins/commit/0cb7b59a95bb67433827ca4700ac57ec8a67db96))

## [3.12.0](https://github.com/laurigates/claude-plugins/compare/blueprint-plugin-v3.11.0...blueprint-plugin-v3.12.0) (2026-02-05)


### Features

* **blueprint-plugin:** consolidate tracking files and add work-order auto-creation ([0cb7b59](https://github.com/laurigates/claude-plugins/commit/0cb7b59a95bb67433827ca4700ac57ec8a67db96))

## [3.12.0](https://github.com/laurigates/claude-plugins/compare/blueprint-plugin-v3.11.0...blueprint-plugin-v3.12.0) (2026-02-05)


### Features

* **blueprint-plugin:** consolidate tracking files and add work-order auto-creation ([0cb7b59](https://github.com/laurigates/claude-plugins/commit/0cb7b59a95bb67433827ca4700ac57ec8a67db96))

## [3.11.0](https://github.com/laurigates/claude-plugins/compare/blueprint-plugin-v3.10.1...blueprint-plugin-v3.11.0) (2026-02-04)


### Features

* Add args and argument-hint parameters to commands ([6f7958e](https://github.com/laurigates/claude-plugins/commit/6f7958e78ba39b91e6d1e918935d58ae7ad376aa))
* **blueprint-plugin:** consolidate tracking files and add work-order auto-creation ([0cb7b59](https://github.com/laurigates/claude-plugins/commit/0cb7b59a95bb67433827ca4700ac57ec8a67db96))

## [3.11.0](https://github.com/laurigates/claude-plugins/compare/blueprint-plugin-v3.10.1...blueprint-plugin-v3.11.0) (2026-02-03)


### Features

* Add args and argument-hint parameters to commands ([6f7958e](https://github.com/laurigates/claude-plugins/commit/6f7958e78ba39b91e6d1e918935d58ae7ad376aa))

## [3.10.1](https://github.com/laurigates/claude-plugins/compare/blueprint-plugin-v3.10.0...blueprint-plugin-v3.10.1) (2026-02-01)


### Code Refactoring

* **blueprint-plugin:** remove deprecated generate-commands ([#292](https://github.com/laurigates/claude-plugins/issues/292)) ([438cb35](https://github.com/laurigates/claude-plugins/commit/438cb353127522bc1c96c499d4fcabbb71934969))

## [3.10.0](https://github.com/laurigates/claude-plugins/compare/blueprint-plugin-v3.9.0...blueprint-plugin-v3.10.0) (2026-01-30)


### Features

* **blueprint-plugin:** refactor to derive-* commands and add git-based rule derivation ([ea33c2c](https://github.com/laurigates/claude-plugins/commit/ea33c2c6cc83c05167677022d5524434240a53ad))

## [3.9.0](https://github.com/laurigates/claude-plugins/compare/blueprint-plugin-v3.8.1...blueprint-plugin-v3.9.0) (2026-01-29)


### Features

* **blueprint:** add /blueprint:adr-list command ([#240](https://github.com/laurigates/claude-plugins/issues/240)) ([c80c1ba](https://github.com/laurigates/claude-plugins/commit/c80c1baaecddad401d9d29c02e45fa30fff81795))

## [3.8.1](https://github.com/laurigates/claude-plugins/compare/blueprint-plugin-v3.8.0...blueprint-plugin-v3.8.1) (2026-01-25)


### Bug Fixes

* rename marketplace from 'lgates-claude-plugins' to 'laurigates-plugins' ([#195](https://github.com/laurigates/claude-plugins/issues/195)) ([4310935](https://github.com/laurigates/claude-plugins/commit/43109350d121f9c0749af86461daef9849eea133))

## [3.8.0](https://github.com/laurigates/claude-plugins/compare/blueprint-plugin-v3.7.1...blueprint-plugin-v3.8.0) (2026-01-23)


### Features

* add model specification to all skills and commands ([#131](https://github.com/laurigates/claude-plugins/issues/131)) ([81f2961](https://github.com/laurigates/claude-plugins/commit/81f296155b50864b8b1687b9eb18a9c2cbb08791))

## [3.7.1](https://github.com/laurigates/claude-plugins/compare/blueprint-plugin-v3.7.0...blueprint-plugin-v3.7.1) (2026-01-22)


### Bug Fixes

* **blueprint-plugin:** wrap hook definitions in hooks key for external file loading ([#127](https://github.com/laurigates/claude-plugins/issues/127)) ([751eb57](https://github.com/laurigates/claude-plugins/commit/751eb57e60aa3d294c517e9d0032e1c59487c6d5))

## [3.7.0](https://github.com/laurigates/claude-plugins/compare/blueprint-plugin-v3.6.0...blueprint-plugin-v3.7.0) (2026-01-21)


### Features

* **blueprint-plugin:** add validation hooks for PRPs and ADRs ([5cd142f](https://github.com/laurigates/claude-plugins/commit/5cd142f1a91f3917d4bca1229e43de9130e62c72))

## [3.6.0](https://github.com/laurigates/claude-plugins/compare/blueprint-plugin-v3.5.0...blueprint-plugin-v3.6.0) (2026-01-20)


### Features

* **blueprint-plugin:** add unified document ID system for traceability ([#110](https://github.com/laurigates/claude-plugins/issues/110)) ([502ad7b](https://github.com/laurigates/claude-plugins/commit/502ad7b73314078f11f28f75b984789fba27930d))

## [3.5.0](https://github.com/laurigates/claude-plugins/compare/blueprint-plugin-v3.4.0...blueprint-plugin-v3.5.0) (2026-01-18)


### Features

* add shell-scripting rule for safe frontmatter extraction ([#101](https://github.com/laurigates/claude-plugins/issues/101)) ([de1ae61](https://github.com/laurigates/claude-plugins/commit/de1ae612228e0ee1a3a88aadac89792e25559aa1))

## [3.4.0](https://github.com/laurigates/claude-plugins/compare/blueprint-plugin-v3.3.0...blueprint-plugin-v3.4.0) (2026-01-17)


### Features

* **blueprint-plugin:** automate feature tracker sync in development loop ([#97](https://github.com/laurigates/claude-plugins/issues/97)) ([0491d9f](https://github.com/laurigates/claude-plugins/commit/0491d9fb5857fd96c5f62ba42c2dc341a7e91c50))

## [3.3.0](https://github.com/laurigates/claude-plugins/compare/blueprint-plugin-v3.2.1...blueprint-plugin-v3.3.0) (2026-01-17)


### Features

* **blueprint-plugin:** add structured logging for deferred PRP items ([#93](https://github.com/laurigates/claude-plugins/issues/93)) ([89e853a](https://github.com/laurigates/claude-plugins/commit/89e853a9170e3b39cd92ec517926af39005e0f2c))
* **blueprint-plugin:** always commit CLAUDE.md and .claude/rules/ ([#94](https://github.com/laurigates/claude-plugins/issues/94)) ([4bf328f](https://github.com/laurigates/claude-plugins/commit/4bf328f961f16cf8ed29d25d8f6e2e5f84775795))

## [3.2.1](https://github.com/laurigates/claude-plugins/compare/blueprint-plugin-v3.2.0...blueprint-plugin-v3.2.1) (2026-01-15)


### Documentation

* **blueprint-plugin:** update diagrams with ADR conflict detection ([e14cc65](https://github.com/laurigates/claude-plugins/commit/e14cc657a73c7510897bda1e594f49809bf51e82))

## [3.2.0](https://github.com/laurigates/claude-plugins/compare/blueprint-plugin-v3.1.0...blueprint-plugin-v3.2.0) (2026-01-15)


### Features

* **blueprint-plugin:** add ADR conflict detection and relationship tracking ([aac8b94](https://github.com/laurigates/claude-plugins/commit/aac8b94fe3c5942a06b9366aa8cd2d032d0300a0))

## [3.1.0](https://github.com/laurigates/claude-plugins/compare/blueprint-plugin-v3.0.1...blueprint-plugin-v3.1.0) (2026-01-15)


### Features

* **blueprint-plugin:** add retroactive import command for existing projects ([4b83477](https://github.com/laurigates/claude-plugins/commit/4b83477cff3c55a687d42897d9da37f09d717a61))

## [3.0.1](https://github.com/laurigates/claude-plugins/compare/blueprint-plugin-v3.0.0...blueprint-plugin-v3.0.1) (2026-01-15)


### Documentation

* **blueprint-plugin:** add comprehensive workflow diagrams ([#73](https://github.com/laurigates/claude-plugins/issues/73)) ([85a610e](https://github.com/laurigates/claude-plugins/commit/85a610e3d85ee16c89e77f2fc373241f23c941fe))

## [3.0.0](https://github.com/laurigates/claude-plugins/compare/blueprint-plugin-v2.0.0...blueprint-plugin-v3.0.0) (2026-01-09)


### ⚠ BREAKING CHANGES

* **blueprint-plugin:** Blueprint state moves from .claude/blueprints/ to docs/blueprint/

### Features

* **blueprint-plugin:** add automatic document detection and management ([ecafdfd](https://github.com/laurigates/claude-plugins/commit/ecafdfdf96bca4c78ce6cda099a9a3f14230ce25))
* **blueprint-plugin:** add feature tracking for requirements management ([cba73bc](https://github.com/laurigates/claude-plugins/commit/cba73bcaada9e59a2f973b9fa0cff039ca7a0f68))
* **blueprint-plugin:** implement v3.0 structure migration ([4fde69f](https://github.com/laurigates/claude-plugins/commit/4fde69fcacb5d33180296ce1c30a475c211c066c))


### Bug Fixes

* sync plugin.json versions to match release-please manifest ([1ac44e1](https://github.com/laurigates/claude-plugins/commit/1ac44e1240eed27eb3f829edaaac9bc863634d89))


### Documentation

* **blueprint-plugin:** add ADR-0011 for blueprint state relocation ([87d92a5](https://github.com/laurigates/claude-plugins/commit/87d92a5d61204064a747638ec797efbfd6d41abb))

## [2.0.0](https://github.com/laurigates/claude-plugins/compare/blueprint-plugin-v1.1.0...blueprint-plugin-v2.0.0) (2025-12-28)


### ⚠ BREAKING CHANGES

* **blueprint-plugin:** Blueprint structure has changed significantly:
    - PRDs, ADRs, PRPs now in docs/ instead of .claude/blueprints/
    - Generated skills/commands in .claude/blueprints/generated/
    - Custom overrides in .claude/skills/ and .claude/commands/

### Features

* **blueprint-plugin:** add GitHub issue integration to work orders ([52e10d2](https://github.com/laurigates/claude-plugins/commit/52e10d201fc979e6d6db174854b50ece448e0ba7))
* **blueprint-plugin:** add PRD/ADR onboarding commands and agents ([e80d62f](https://github.com/laurigates/claude-plugins/commit/e80d62fd702b811a45ff4c42d8d1cdfbd494675e))
* **blueprint-plugin:** three-layer architecture with docs/ for PRDs ([e221acd](https://github.com/laurigates/claude-plugins/commit/e221acd34c289d2737b9083a29f8153e0ea28ec8))
* **blueprint:** add version tracking, modular rules, and CLAUDE.md management ([e6fd2c0](https://github.com/laurigates/claude-plugins/commit/e6fd2c01554c474044b88bafe95aef9d534b6b1a))
