# Changelog

## [2.36.0](https://github.com/laurigates/claude-plugins/compare/git-plugin-v2.35.1...git-plugin-v2.36.0) (2026-05-07)


### Features

* **git-plugin:** add --all/--dry-run/--limit flags to git-pr-feedback ([#1257](https://github.com/laurigates/claude-plugins/issues/1257)) ([b4feafd](https://github.com/laurigates/claude-plugins/commit/b4feafd761720d874f74b6c76c02df1bb4b8ba6e))

## [2.35.1](https://github.com/laurigates/claude-plugins/compare/git-plugin-v2.35.0...git-plugin-v2.35.1) (2026-05-06)


### Bug Fixes

* **plugins:** quote args/argument-hint values to fix skill autocomplete ([#1254](https://github.com/laurigates/claude-plugins/issues/1254)) ([1874cff](https://github.com/laurigates/claude-plugins/commit/1874cfff8b724819bea6d9604b654cadf10b8038))

## [2.35.0](https://github.com/laurigates/claude-plugins/compare/git-plugin-v2.34.5...git-plugin-v2.35.0) (2026-05-05)


### Features

* **git-plugin:** align git-pr-feedback with GitHub's documented PR-feedback workflow ([#1240](https://github.com/laurigates/claude-plugins/issues/1240)) ([baa1bff](https://github.com/laurigates/claude-plugins/commit/baa1bff63c4bf575d665b5326c00b7f09642a146))

## [2.34.5](https://github.com/laurigates/claude-plugins/compare/git-plugin-v2.34.4...git-plugin-v2.34.5) (2026-04-29)


### Documentation

* **git-plugin:** mandate --body-file for gh issue/pr bodies ([#1211](https://github.com/laurigates/claude-plugins/issues/1211)) ([b14b3ea](https://github.com/laurigates/claude-plugins/commit/b14b3ead58b722de3c9b71c6ae94a7ede8d76a78))

## [2.34.4](https://github.com/laurigates/claude-plugins/compare/git-plugin-v2.34.3...git-plugin-v2.34.4) (2026-04-25)


### Documentation

* **git-plugin:** standardise When to Use tables ([#1172](https://github.com/laurigates/claude-plugins/issues/1172)) ([ffc0718](https://github.com/laurigates/claude-plugins/commit/ffc0718655a7a94aa34ede8a772a6cb69fbce0bb)), closes [#1156](https://github.com/laurigates/claude-plugins/issues/1156)

## [2.34.3](https://github.com/laurigates/claude-plugins/compare/git-plugin-v2.34.2...git-plugin-v2.34.3) (2026-04-25)


### Documentation

* **git-plugin,github-actions-plugin:** add When to Use tables to 3 skills ([#1144](https://github.com/laurigates/claude-plugins/issues/1144)) ([aa5a803](https://github.com/laurigates/claude-plugins/commit/aa5a8032ba06b299fb0dfa18d5e65c6b4d3ee851))

## [2.34.2](https://github.com/laurigates/claude-plugins/compare/git-plugin-v2.34.1...git-plugin-v2.34.2) (2026-04-24)


### Bug Fixes

* **feedback-plugin,git-plugin,github-actions-plugin:** remove gh list from context ([#1123](https://github.com/laurigates/claude-plugins/issues/1123)) ([8ad0b71](https://github.com/laurigates/claude-plugins/commit/8ad0b7140028a749dd61027f80eb0c75bb6f8bfb))

## [2.34.1](https://github.com/laurigates/claude-plugins/compare/git-plugin-v2.34.0...git-plugin-v2.34.1) (2026-04-22)


### Bug Fixes

* **git-plugin,blueprint-plugin:** add label pre-check before --add-label calls ([7cbed31](https://github.com/laurigates/claude-plugins/commit/7cbed3146b21034fa749452e4b380324cc0f812c))

## [2.34.0](https://github.com/laurigates/claude-plugins/compare/git-plugin-v2.33.0...git-plugin-v2.34.0) (2026-04-21)


### Features

* **git-plugin:** add git-coworker-check skill and coworker-detection rule ([5e427f0](https://github.com/laurigates/claude-plugins/commit/5e427f03ffd7c2d4614ef805c7931cc3a011e23b))


### Bug Fixes

* **git-plugin:** add args field to git-coworker-check frontmatter ([d548ade](https://github.com/laurigates/claude-plugins/commit/d548adee04adc917425c39ca0ec0ad979fb05d01))

## [2.33.0](https://github.com/laurigates/claude-plugins/compare/git-plugin-v2.32.0...git-plugin-v2.33.0) (2026-04-21)


### Features

* **git-plugin:** support native GitHub issue dependencies ([#1104](https://github.com/laurigates/claude-plugins/issues/1104)) ([22f43b5](https://github.com/laurigates/claude-plugins/commit/22f43b55cccf2a884ba523889529380321a29366))

## [2.32.0](https://github.com/laurigates/claude-plugins/compare/git-plugin-v2.31.0...git-plugin-v2.32.0) (2026-04-19)


### Features

* make skills discoverable by Claude's auto-invocation ([#1090](https://github.com/laurigates/claude-plugins/issues/1090)) ([cded1da](https://github.com/laurigates/claude-plugins/commit/cded1da1ebaf350cba1285b58ecadbbaa0eb01f6))

## [2.31.0](https://github.com/laurigates/claude-plugins/compare/git-plugin-v2.30.1...git-plugin-v2.31.0) (2026-04-17)


### Features

* fallback PR selector for git-pr-feedback skill ([#1066](https://github.com/laurigates/claude-plugins/issues/1066)) ([3d958e9](https://github.com/laurigates/claude-plugins/commit/3d958e9c5a168c3941eee2e6a09843f3a684ef4d))

## [2.30.1](https://github.com/laurigates/claude-plugins/compare/git-plugin-v2.30.0...git-plugin-v2.30.1) (2026-04-17)


### Documentation

* update Claude Opus model references to 4.7 ([#1052](https://github.com/laurigates/claude-plugins/issues/1052)) ([9ffadc5](https://github.com/laurigates/claude-plugins/commit/9ffadc553de069f47efebd4d2c54ff89e47649fd))

## [2.30.0](https://github.com/laurigates/claude-plugins/compare/git-plugin-v2.29.7...git-plugin-v2.30.0) (2026-04-16)


### Features

* **blueprint-plugin:** configurable output path for generated rules ([#1046](https://github.com/laurigates/claude-plugins/issues/1046)) ([e0b37bf](https://github.com/laurigates/claude-plugins/commit/e0b37bf4c64cca772f450dbb45e81734110bf978)), closes [#1043](https://github.com/laurigates/claude-plugins/issues/1043) [#1040](https://github.com/laurigates/claude-plugins/issues/1040)

## [2.29.7](https://github.com/laurigates/claude-plugins/compare/git-plugin-v2.29.6...git-plugin-v2.29.7) (2026-04-15)


### Documentation

* **plugins:** add flow diagrams for router and pipeline plugins ([#1034](https://github.com/laurigates/claude-plugins/issues/1034)) ([a5e0e08](https://github.com/laurigates/claude-plugins/commit/a5e0e087495f0e835c3ad7e5dcf5bf7f4e61ad02))

## [2.29.6](https://github.com/laurigates/claude-plugins/compare/git-plugin-v2.29.5...git-plugin-v2.29.6) (2026-04-08)


### Bug Fixes

* **blueprint-plugin:** remove model field from skills and fix invocation syntax ([#1007](https://github.com/laurigates/claude-plugins/issues/1007)) ([42e1e5b](https://github.com/laurigates/claude-plugins/commit/42e1e5b6c73d43e5de4b27cdee16e316de44d4c0))

## [2.29.5](https://github.com/laurigates/claude-plugins/compare/git-plugin-v2.29.4...git-plugin-v2.29.5) (2026-04-03)


### Documentation

* **git-plugin:** improve github-labels skill discoverability ([#1003](https://github.com/laurigates/claude-plugins/issues/1003)) ([688ea5e](https://github.com/laurigates/claude-plugins/commit/688ea5eff2083d32c38dccb22fcd5a6bdbeb69e6)), closes [#992](https://github.com/laurigates/claude-plugins/issues/992)

## [2.29.4](https://github.com/laurigates/claude-plugins/compare/git-plugin-v2.29.3...git-plugin-v2.29.4) (2026-03-25)


### Bug Fixes

* remove context: fork from all plugin skills to fix rate limit errors ([#981](https://github.com/laurigates/claude-plugins/issues/981)) ([56a90b1](https://github.com/laurigates/claude-plugins/commit/56a90b1464a9b1233a8bdb3d0716f1673bc70ad3))

## [2.29.3](https://github.com/laurigates/claude-plugins/compare/git-plugin-v2.29.2...git-plugin-v2.29.3) (2026-03-25)


### Bug Fixes

* **git-plugin,project-plugin:** upgrade skills to opus to fix rate limit errors ([#978](https://github.com/laurigates/claude-plugins/issues/978)) ([a8fb9ba](https://github.com/laurigates/claude-plugins/commit/a8fb9baf492cbe79dd635b9bcc6f957c77ddcd82))

## [2.29.2](https://github.com/laurigates/claude-plugins/compare/git-plugin-v2.29.1...git-plugin-v2.29.2) (2026-03-24)


### Performance

* **git-plugin,project-plugin:** reduce skill token consumption by 54% ([#976](https://github.com/laurigates/claude-plugins/issues/976)) ([26b67d8](https://github.com/laurigates/claude-plugins/commit/26b67d8a5dac2a3ef8f85f9a6d7972ccb2cce89d))

## [2.29.1](https://github.com/laurigates/claude-plugins/compare/git-plugin-v2.29.0...git-plugin-v2.29.1) (2026-03-20)


### Performance

* **git-plugin:** consolidate PR feedback API calls into single GraphQL query ([6fefc82](https://github.com/laurigates/claude-plugins/commit/6fefc82b9b51f6b0ea705eea0da81480463f82b7))
* git-pr-feedback skill with single GraphQL query ([#967](https://github.com/laurigates/claude-plugins/issues/967)) ([6fefc82](https://github.com/laurigates/claude-plugins/commit/6fefc82b9b51f6b0ea705eea0da81480463f82b7))

## [2.29.0](https://github.com/laurigates/claude-plugins/compare/git-plugin-v2.28.0...git-plugin-v2.29.0) (2026-03-19)


### Features

* issue hierarchy and management skills for GitHub issues ([#960](https://github.com/laurigates/claude-plugins/issues/960)) ([dd1d736](https://github.com/laurigates/claude-plugins/commit/dd1d736d5b7714097bb4a85382a0b8bf3da6093a))

## [2.28.0](https://github.com/laurigates/claude-plugins/compare/git-plugin-v2.27.1...git-plugin-v2.28.0) (2026-03-16)


### Features

* rate limit handling and caching to git-pr-feedback skill ([#951](https://github.com/laurigates/claude-plugins/issues/951)) ([6811132](https://github.com/laurigates/claude-plugins/commit/6811132f44791068bb023c78958ba2ebcbe1c69c))


### Bug Fixes

* **git-plugin:** add rate limit handling to git-pr-feedback skill ([6811132](https://github.com/laurigates/claude-plugins/commit/6811132f44791068bb023c78958ba2ebcbe1c69c))

## [2.27.1](https://github.com/laurigates/claude-plugins/compare/git-plugin-v2.27.0...git-plugin-v2.27.1) (2026-03-15)


### Bug Fixes

* **git-plugin:** resolve git-commit-push-pr failures on Sonnet and Haiku ([#944](https://github.com/laurigates/claude-plugins/issues/944)) ([c1645f0](https://github.com/laurigates/claude-plugins/commit/c1645f015ea746034840dadd579a4f8f4aa240bc))

## [2.27.0](https://github.com/laurigates/claude-plugins/compare/git-plugin-v2.26.2...git-plugin-v2.27.0) (2026-03-09)


### Features

* **rules:** update rules for Claude Code 2.1.63-2.1.71 changes ([#917](https://github.com/laurigates/claude-plugins/issues/917)) ([20341e8](https://github.com/laurigates/claude-plugins/commit/20341e871fe7e91eb79d51aa02ad7bc9003a93e1))

## [2.26.2](https://github.com/laurigates/claude-plugins/compare/git-plugin-v2.26.1...git-plugin-v2.26.2) (2026-03-09)


### Bug Fixes

* **finops-plugin,git-plugin:** replace gh repo view with git remote in context commands ([#913](https://github.com/laurigates/claude-plugins/issues/913)) ([f4cf31a](https://github.com/laurigates/claude-plugins/commit/f4cf31aebdc00d6a6d7ca911db3cf1534b13ce75))

## [2.26.1](https://github.com/laurigates/claude-plugins/compare/git-plugin-v2.26.0...git-plugin-v2.26.1) (2026-03-09)


### Bug Fixes

* **git-plugin:** fix multi-line PR body parsing in issue link hook ([78ce925](https://github.com/laurigates/claude-plugins/commit/78ce9259f5137f8471ac12dbe71afe8fffc6a933))
* multi-line body parsing in PR validation hook ([#911](https://github.com/laurigates/claude-plugins/issues/911)) ([78ce925](https://github.com/laurigates/claude-plugins/commit/78ce9259f5137f8471ac12dbe71afe8fffc6a933))

## [2.26.0](https://github.com/laurigates/claude-plugins/compare/git-plugin-v2.25.2...git-plugin-v2.26.0) (2026-03-05)


### Features

* standardize shell script conventions and add linting ([#892](https://github.com/laurigates/claude-plugins/issues/892)) ([0eba700](https://github.com/laurigates/claude-plugins/commit/0eba7009728418bdef6355bd91fc9ee50c6982a8))

## [2.25.2](https://github.com/laurigates/claude-plugins/compare/git-plugin-v2.25.1...git-plugin-v2.25.2) (2026-03-04)


### Bug Fixes

* haiku model incompatibility with AskUserQuestion tool ([#881](https://github.com/laurigates/claude-plugins/issues/881)) ([c09e400](https://github.com/laurigates/claude-plugins/commit/c09e40031e2eef7fa78640ee1d8327a0f18bbe64))

## [2.25.1](https://github.com/laurigates/claude-plugins/compare/git-plugin-v2.25.0...git-plugin-v2.25.1) (2026-03-04)


### Bug Fixes

* **git-plugin:** compare PR branches against origin/main instead of local main ([989ae89](https://github.com/laurigates/claude-plugins/commit/989ae89ae49e1e8d1c9b61ec31daac1ce58ee507))
* PR context comparison to always use origin/main ([#877](https://github.com/laurigates/claude-plugins/issues/877)) ([989ae89](https://github.com/laurigates/claude-plugins/commit/989ae89ae49e1e8d1c9b61ec31daac1ce58ee507))

## [2.25.0](https://github.com/laurigates/claude-plugins/compare/git-plugin-v2.24.0...git-plugin-v2.25.0) (2026-03-04)


### Features

* add `context: fork` guidance and apply to verbose skills ([#833](https://github.com/laurigates/claude-plugins/issues/833)) ([cced641](https://github.com/laurigates/claude-plugins/commit/cced641a953953b97f37528960782cacd75dbcab))
* add metadata fields to skill definitions across all plugins ([#828](https://github.com/laurigates/claude-plugins/issues/828)) ([59b3d1f](https://github.com/laurigates/claude-plugins/commit/59b3d1fadd8fd888f95ced8b071fb66cf6f9c825))
* add safety hooks for Terraform, Kubernetes, Git, and Blueprint plugins ([#835](https://github.com/laurigates/claude-plugins/issues/835)) ([d4d86a0](https://github.com/laurigates/claude-plugins/commit/d4d86a03b96d99642f341effb8f3999df5246c8b))
* add skill invocation control via user-invocable and disable-model-invocation frontmatter ([59b3d1f](https://github.com/laurigates/claude-plugins/commit/59b3d1fadd8fd888f95ced8b071fb66cf6f9c825))
* **blueprint-plugin:** add PreCompact hook for derivation workflow context ([d4d86a0](https://github.com/laurigates/claude-plugins/commit/d4d86a03b96d99642f341effb8f3999df5246c8b))
* **configure-plugin:** replace detect-secrets with gitleaks for secret scanning ([#668](https://github.com/laurigates/claude-plugins/issues/668)) ([3fc5bbc](https://github.com/laurigates/claude-plugins/commit/3fc5bbc2f8500f30160cc5dfeb5e3d1253ed0a54))
* evaluate-plugin for skill evaluation and benchmarking ([#871](https://github.com/laurigates/claude-plugins/issues/871)) ([22cf97a](https://github.com/laurigates/claude-plugins/commit/22cf97a513245928e2e5b2572758ea0e33e34b90))
* **git-plugin:** add fork-to-upstream PR workflow skills ([#856](https://github.com/laurigates/claude-plugins/issues/856)) ([cb7ec04](https://github.com/laurigates/claude-plugins/commit/cb7ec046c2d37a109f384a5670e7f6310d9cbbb9))
* **git-plugin:** add git-api-pr skill for server-side PR creation ([#667](https://github.com/laurigates/claude-plugins/issues/667)) ([e8a3380](https://github.com/laurigates/claude-plugins/commit/e8a338017c697ce6f231e2d089f35cc252b829eb))
* **git-plugin:** add git-conflicts skill for merge conflict resolution ([#849](https://github.com/laurigates/claude-plugins/issues/849)) ([ce62049](https://github.com/laurigates/claude-plugins/commit/ce62049ce6405cfb3930e7f94f5228866e3f4b16))
* **git-plugin:** add GitHub URL resolution patterns to gh-cli-agentic ([9c8420b](https://github.com/laurigates/claude-plugins/commit/9c8420b5542dd4fadd5b7ff607afe8b9387c14d2))
* **git-plugin:** track post-merge follow-ups as issues, not PR checklists ([ebce835](https://github.com/laurigates/claude-plugins/commit/ebce835f10cd11361c378f20bb0da572eb458117))
* **git-plugin:** use ./worktrees/ directory for agent worktree workflows ([a97db86](https://github.com/laurigates/claude-plugins/commit/a97db8613d879db4c06cefc6f94edcfca95f9043))
* integrate worktree isolation into agent framework ([#830](https://github.com/laurigates/claude-plugins/issues/830)) ([564ffcf](https://github.com/laurigates/claude-plugins/commit/564ffcf8f34cf9d672816b42dabcf1280c701589))
* introduce three-tier model palette (opus/sonnet/haiku) ([#709](https://github.com/laurigates/claude-plugins/issues/709)) ([2c1e9cc](https://github.com/laurigates/claude-plugins/commit/2c1e9ccff5d48c2b426beac5b3b38cd4576c79a0))
* **kubernetes-plugin:** add kubectl dry-run injection hook ([d4d86a0](https://github.com/laurigates/claude-plugins/commit/d4d86a03b96d99642f341effb8f3999df5246c8b))
* Refactor PR workflow to track post-merge actions as GitHub issues ([#769](https://github.com/laurigates/claude-plugins/issues/769)) ([ebce835](https://github.com/laurigates/claude-plugins/commit/ebce835f10cd11361c378f20bb0da572eb458117))
* **skills:** add context: fork to verbose autonomous skills ([cced641](https://github.com/laurigates/claude-plugins/commit/cced641a953953b97f37528960782cacd75dbcab))
* **terraform-plugin:** add terraform apply gate hook ([d4d86a0](https://github.com/laurigates/claude-plugins/commit/d4d86a03b96d99642f341effb8f3999df5246c8b))


### Bug Fixes

* **frontmatter:** resolve 83 validation errors across 75 files ([#434](https://github.com/laurigates/claude-plugins/issues/434)) ([5beb75e](https://github.com/laurigates/claude-plugins/commit/5beb75ed4b2cb0431d060bd7102903495c03c6c5))
* **git-ops:** enable git write permissions and clarify configuration ([#430](https://github.com/laurigates/claude-plugins/issues/430)) ([3448890](https://github.com/laurigates/claude-plugins/commit/3448890b00d1feb40a4d6e86ae5850d4cdb97b90))
* **git-plugin:** remove backticks from status codes to prevent parsing bug ([373023c](https://github.com/laurigates/claude-plugins/commit/373023ce8a292211890240612785e41641563c4d))
* **git-plugin:** remove pipe operator from worktree skill context command ([#695](https://github.com/laurigates/claude-plugins/issues/695)) ([38884b1](https://github.com/laurigates/claude-plugins/commit/38884b170286289b7d31261967071bfae58c4f73))
* **hooks-plugin:** block git push -u on main to differently-named branch ([#746](https://github.com/laurigates/claude-plugins/issues/746)) ([25e3e49](https://github.com/laurigates/claude-plugins/commit/25e3e494e84f676503a52a5ed24e0eb62c467e09))
* remove 2&gt;/dev/null from context commands across all plugins ([#792](https://github.com/laurigates/claude-plugins/issues/792)) ([c72e67e](https://github.com/laurigates/claude-plugins/commit/c72e67ee37e809449f0e6282c48fac01363a59fd))
* remove pipe/ls operators from context commands and add CI linting ([#653](https://github.com/laurigates/claude-plugins/issues/653)) ([7a01eef](https://github.com/laurigates/claude-plugins/commit/7a01eef21495ed6243277fbaa88082b7ecabc793))
* replace broken context command patterns in skill files ([#644](https://github.com/laurigates/claude-plugins/issues/644)) ([440ba34](https://github.com/laurigates/claude-plugins/commit/440ba347bcc73a0512f74975cfd6b4af9fe8566e))
* replace git remote get-url with git remote -v for verbose output ([#804](https://github.com/laurigates/claude-plugins/issues/804)) ([e39407a](https://github.com/laurigates/claude-plugins/commit/e39407a366d2d0ba431df0f456074b847073eea8))
* **scripts:** enhance context command linter with stderr safety checks and fix violations ([#819](https://github.com/laurigates/claude-plugins/issues/819)) ([2975b9b](https://github.com/laurigates/claude-plugins/commit/2975b9b0bf6698bdecf627e3d28bad06fde03cd1))
* **skills:** replace git remote get-url origin with git remote -v in context commands ([e39407a](https://github.com/laurigates/claude-plugins/commit/e39407a366d2d0ba431df0f456074b847073eea8))
* standardize skill name fields to kebab-case across all plugins ([72c0f83](https://github.com/laurigates/claude-plugins/commit/72c0f837a1b07004850c5906a30d619a79098f69))


### Code Refactoring

* consolidate skill documentation and remove reference files ([#758](https://github.com/laurigates/claude-plugins/issues/758)) ([3d1e8cc](https://github.com/laurigates/claude-plugins/commit/3d1e8ccd9becba5faec5b1df1fa06f410eca7437))
* extract detailed content to REFERENCE.md files ([#605](https://github.com/laurigates/claude-plugins/issues/605)) ([7efbd83](https://github.com/laurigates/claude-plugins/commit/7efbd83b9a2b1ef67be702206396ba6d8102684d))
* git-worktree workflow to worktree-first implementation model ([#693](https://github.com/laurigates/claude-plugins/issues/693)) ([16d46e5](https://github.com/laurigates/claude-plugins/commit/16d46e559bbf0daa2874c11ecbf6483e6be29bc2))
* reframe negative guidance as positive guidance across skills ([7e755ee](https://github.com/laurigates/claude-plugins/commit/7e755ee1c32c39c124f3204a0d0a8d1d770e1573))


### Documentation

* **git-plugin:** add conventional commits standards ([#616](https://github.com/laurigates/claude-plugins/issues/616)) ([5b74389](https://github.com/laurigates/claude-plugins/commit/5b74389ecdf5223dd62368390ecd9b36ccb1596c))
* **git-plugin:** add GitHub URL resolution patterns to gh-cli-agentic ([#687](https://github.com/laurigates/claude-plugins/issues/687)) ([9c8420b](https://github.com/laurigates/claude-plugins/commit/9c8420b5542dd4fadd5b7ff607afe8b9387c14d2))
* **git-plugin:** document PR check watching workflow ([24116de](https://github.com/laurigates/claude-plugins/commit/24116de12541b7af7677d5e1ed195628bf4599eb))
* **git-plugin:** improve worktree documentation and migration notes ([03d04ef](https://github.com/laurigates/claude-plugins/commit/03d04ef1035d3a9f8675342c5c79ad163bc6edee))
* **git-plugin:** remove exclusive git permissions claims from git-ops agent ([0f92846](https://github.com/laurigates/claude-plugins/commit/0f928466543e7a302c11ff9d51ae481c8bf887eb))
* **git-plugin:** remove obsolete orchestrator mode documentation ([#685](https://github.com/laurigates/claude-plugins/issues/685)) ([9e4e794](https://github.com/laurigates/claude-plugins/commit/9e4e794fce72c4daec7fdd8fccfc16ae9ad43bac))
* **git-plugin:** update git-pr-feedback skill documentation and metadata ([#823](https://github.com/laurigates/claude-plugins/issues/823)) ([aa3fba5](https://github.com/laurigates/claude-plugins/commit/aa3fba56b82a3192a3d73ab34eb8024978398076))
* improve skill documentation with decision guides and references ([#426](https://github.com/laurigates/claude-plugins/issues/426)) ([24116de](https://github.com/laurigates/claude-plugins/commit/24116de12541b7af7677d5e1ed195628bf4599eb))
* **rules:** update rules and skills for Claude Code 2.1.50-2.1.63 ([#859](https://github.com/laurigates/claude-plugins/issues/859)) ([6c66021](https://github.com/laurigates/claude-plugins/commit/6c66021fefa205abfc4f575229e3bbb9cdc6263a))

## [2.24.0](https://github.com/laurigates/claude-plugins/compare/git-plugin-v2.23.1...git-plugin-v2.24.0) (2026-03-04)


### Features

* evaluate-plugin for skill evaluation and benchmarking ([#871](https://github.com/laurigates/claude-plugins/issues/871)) ([22cf97a](https://github.com/laurigates/claude-plugins/commit/22cf97a513245928e2e5b2572758ea0e33e34b90))

## [2.23.1](https://github.com/laurigates/claude-plugins/compare/git-plugin-v2.23.0...git-plugin-v2.23.1) (2026-03-02)


### Documentation

* **rules:** update rules and skills for Claude Code 2.1.50-2.1.63 ([#859](https://github.com/laurigates/claude-plugins/issues/859)) ([6c66021](https://github.com/laurigates/claude-plugins/commit/6c66021fefa205abfc4f575229e3bbb9cdc6263a))

## [2.23.0](https://github.com/laurigates/claude-plugins/compare/git-plugin-v2.22.0...git-plugin-v2.23.0) (2026-03-02)


### Features

* **git-plugin:** add fork-to-upstream PR workflow skills ([#856](https://github.com/laurigates/claude-plugins/issues/856)) ([cb7ec04](https://github.com/laurigates/claude-plugins/commit/cb7ec046c2d37a109f384a5670e7f6310d9cbbb9))

## [2.22.0](https://github.com/laurigates/claude-plugins/compare/git-plugin-v2.21.0...git-plugin-v2.22.0) (2026-03-01)


### Features

* add safety hooks for Terraform, Kubernetes, Git, and Blueprint plugins ([#835](https://github.com/laurigates/claude-plugins/issues/835)) ([d4d86a0](https://github.com/laurigates/claude-plugins/commit/d4d86a03b96d99642f341effb8f3999df5246c8b))
* **blueprint-plugin:** add PreCompact hook for derivation workflow context ([d4d86a0](https://github.com/laurigates/claude-plugins/commit/d4d86a03b96d99642f341effb8f3999df5246c8b))
* **git-plugin:** add git-conflicts skill for merge conflict resolution ([#849](https://github.com/laurigates/claude-plugins/issues/849)) ([ce62049](https://github.com/laurigates/claude-plugins/commit/ce62049ce6405cfb3930e7f94f5228866e3f4b16))
* **kubernetes-plugin:** add kubectl dry-run injection hook ([d4d86a0](https://github.com/laurigates/claude-plugins/commit/d4d86a03b96d99642f341effb8f3999df5246c8b))
* **terraform-plugin:** add terraform apply gate hook ([d4d86a0](https://github.com/laurigates/claude-plugins/commit/d4d86a03b96d99642f341effb8f3999df5246c8b))

## [2.21.0](https://github.com/laurigates/claude-plugins/compare/git-plugin-v2.20.0...git-plugin-v2.21.0) (2026-02-27)


### Features

* add `context: fork` guidance and apply to verbose skills ([#833](https://github.com/laurigates/claude-plugins/issues/833)) ([cced641](https://github.com/laurigates/claude-plugins/commit/cced641a953953b97f37528960782cacd75dbcab))
* integrate worktree isolation into agent framework ([#830](https://github.com/laurigates/claude-plugins/issues/830)) ([564ffcf](https://github.com/laurigates/claude-plugins/commit/564ffcf8f34cf9d672816b42dabcf1280c701589))
* **skills:** add context: fork to verbose autonomous skills ([cced641](https://github.com/laurigates/claude-plugins/commit/cced641a953953b97f37528960782cacd75dbcab))

## [2.20.0](https://github.com/laurigates/claude-plugins/compare/git-plugin-v2.19.4...git-plugin-v2.20.0) (2026-02-27)


### Features

* add metadata fields to skill definitions across all plugins ([#828](https://github.com/laurigates/claude-plugins/issues/828)) ([59b3d1f](https://github.com/laurigates/claude-plugins/commit/59b3d1fadd8fd888f95ced8b071fb66cf6f9c825))
* add skill invocation control via user-invocable and disable-model-invocation frontmatter ([59b3d1f](https://github.com/laurigates/claude-plugins/commit/59b3d1fadd8fd888f95ced8b071fb66cf6f9c825))

## [2.19.4](https://github.com/laurigates/claude-plugins/compare/git-plugin-v2.19.3...git-plugin-v2.19.4) (2026-02-26)


### Documentation

* **git-plugin:** update git-pr-feedback skill documentation and metadata ([#823](https://github.com/laurigates/claude-plugins/issues/823)) ([aa3fba5](https://github.com/laurigates/claude-plugins/commit/aa3fba56b82a3192a3d73ab34eb8024978398076))

## [2.19.3](https://github.com/laurigates/claude-plugins/compare/git-plugin-v2.19.2...git-plugin-v2.19.3) (2026-02-26)


### Bug Fixes

* **scripts:** enhance context command linter with stderr safety checks and fix violations ([#819](https://github.com/laurigates/claude-plugins/issues/819)) ([2975b9b](https://github.com/laurigates/claude-plugins/commit/2975b9b0bf6698bdecf627e3d28bad06fde03cd1))

## [2.19.2](https://github.com/laurigates/claude-plugins/compare/git-plugin-v2.19.1...git-plugin-v2.19.2) (2026-02-25)


### Bug Fixes

* replace git remote get-url with git remote -v for verbose output ([#804](https://github.com/laurigates/claude-plugins/issues/804)) ([e39407a](https://github.com/laurigates/claude-plugins/commit/e39407a366d2d0ba431df0f456074b847073eea8))
* **skills:** replace git remote get-url origin with git remote -v in context commands ([e39407a](https://github.com/laurigates/claude-plugins/commit/e39407a366d2d0ba431df0f456074b847073eea8))

## [2.19.1](https://github.com/laurigates/claude-plugins/compare/git-plugin-v2.19.0...git-plugin-v2.19.1) (2026-02-23)


### Bug Fixes

* remove 2&gt;/dev/null from context commands across all plugins ([#792](https://github.com/laurigates/claude-plugins/issues/792)) ([c72e67e](https://github.com/laurigates/claude-plugins/commit/c72e67ee37e809449f0e6282c48fac01363a59fd))

## [2.19.0](https://github.com/laurigates/claude-plugins/compare/git-plugin-v2.18.2...git-plugin-v2.19.0) (2026-02-20)


### Features

* **git-plugin:** track post-merge follow-ups as issues, not PR checklists ([ebce835](https://github.com/laurigates/claude-plugins/commit/ebce835f10cd11361c378f20bb0da572eb458117))
* Refactor PR workflow to track post-merge actions as GitHub issues ([#769](https://github.com/laurigates/claude-plugins/issues/769)) ([ebce835](https://github.com/laurigates/claude-plugins/commit/ebce835f10cd11361c378f20bb0da572eb458117))

## [2.18.2](https://github.com/laurigates/claude-plugins/compare/git-plugin-v2.18.1...git-plugin-v2.18.2) (2026-02-20)


### Code Refactoring

* consolidate skill documentation and remove reference files ([#758](https://github.com/laurigates/claude-plugins/issues/758)) ([3d1e8cc](https://github.com/laurigates/claude-plugins/commit/3d1e8ccd9becba5faec5b1df1fa06f410eca7437))

## [2.18.1](https://github.com/laurigates/claude-plugins/compare/git-plugin-v2.18.0...git-plugin-v2.18.1) (2026-02-18)


### Bug Fixes

* **hooks-plugin:** block git push -u on main to differently-named branch ([#746](https://github.com/laurigates/claude-plugins/issues/746)) ([25e3e49](https://github.com/laurigates/claude-plugins/commit/25e3e494e84f676503a52a5ed24e0eb62c467e09))

## [2.18.0](https://github.com/laurigates/claude-plugins/compare/git-plugin-v2.17.0...git-plugin-v2.18.0) (2026-02-18)


### Features

* introduce three-tier model palette (opus/sonnet/haiku) ([#709](https://github.com/laurigates/claude-plugins/issues/709)) ([2c1e9cc](https://github.com/laurigates/claude-plugins/commit/2c1e9ccff5d48c2b426beac5b3b38cd4576c79a0))

## [2.17.0](https://github.com/laurigates/claude-plugins/compare/git-plugin-v2.16.2...git-plugin-v2.17.0) (2026-02-16)


### Features

* **git-plugin:** add GitHub URL resolution patterns to gh-cli-agentic ([9c8420b](https://github.com/laurigates/claude-plugins/commit/9c8420b5542dd4fadd5b7ff607afe8b9387c14d2))


### Bug Fixes

* **git-plugin:** remove pipe operator from worktree skill context command ([#695](https://github.com/laurigates/claude-plugins/issues/695)) ([38884b1](https://github.com/laurigates/claude-plugins/commit/38884b170286289b7d31261967071bfae58c4f73))


### Documentation

* **git-plugin:** add GitHub URL resolution patterns to gh-cli-agentic ([#687](https://github.com/laurigates/claude-plugins/issues/687)) ([9c8420b](https://github.com/laurigates/claude-plugins/commit/9c8420b5542dd4fadd5b7ff607afe8b9387c14d2))

## [2.16.2](https://github.com/laurigates/claude-plugins/compare/git-plugin-v2.16.1...git-plugin-v2.16.2) (2026-02-16)


### Code Refactoring

* git-worktree workflow to worktree-first implementation model ([#693](https://github.com/laurigates/claude-plugins/issues/693)) ([16d46e5](https://github.com/laurigates/claude-plugins/commit/16d46e559bbf0daa2874c11ecbf6483e6be29bc2))

## [2.16.1](https://github.com/laurigates/claude-plugins/compare/git-plugin-v2.16.0...git-plugin-v2.16.1) (2026-02-16)


### Documentation

* **git-plugin:** remove obsolete orchestrator mode documentation ([#685](https://github.com/laurigates/claude-plugins/issues/685)) ([9e4e794](https://github.com/laurigates/claude-plugins/commit/9e4e794fce72c4daec7fdd8fccfc16ae9ad43bac))

## [2.16.0](https://github.com/laurigates/claude-plugins/compare/git-plugin-v2.15.0...git-plugin-v2.16.0) (2026-02-16)


### Features

* **git-plugin:** add git-api-pr skill for server-side PR creation ([#667](https://github.com/laurigates/claude-plugins/issues/667)) ([e8a3380](https://github.com/laurigates/claude-plugins/commit/e8a338017c697ce6f231e2d089f35cc252b829eb))

## [2.15.0](https://github.com/laurigates/claude-plugins/compare/git-plugin-v2.14.4...git-plugin-v2.15.0) (2026-02-16)


### Features

* **configure-plugin:** replace detect-secrets with gitleaks for secret scanning ([#668](https://github.com/laurigates/claude-plugins/issues/668)) ([3fc5bbc](https://github.com/laurigates/claude-plugins/commit/3fc5bbc2f8500f30160cc5dfeb5e3d1253ed0a54))

## [2.14.4](https://github.com/laurigates/claude-plugins/compare/git-plugin-v2.14.3...git-plugin-v2.14.4) (2026-02-15)


### Bug Fixes

* remove pipe/ls operators from context commands and add CI linting ([#653](https://github.com/laurigates/claude-plugins/issues/653)) ([7a01eef](https://github.com/laurigates/claude-plugins/commit/7a01eef21495ed6243277fbaa88082b7ecabc793))

## [2.14.3](https://github.com/laurigates/claude-plugins/compare/git-plugin-v2.14.2...git-plugin-v2.14.3) (2026-02-15)


### Bug Fixes

* replace broken context command patterns in skill files ([#644](https://github.com/laurigates/claude-plugins/issues/644)) ([440ba34](https://github.com/laurigates/claude-plugins/commit/440ba347bcc73a0512f74975cfd6b4af9fe8566e))

## [2.14.2](https://github.com/laurigates/claude-plugins/compare/git-plugin-v2.14.1...git-plugin-v2.14.2) (2026-02-14)


### Code Refactoring

* extract detailed content to REFERENCE.md files ([#605](https://github.com/laurigates/claude-plugins/issues/605)) ([7efbd83](https://github.com/laurigates/claude-plugins/commit/7efbd83b9a2b1ef67be702206396ba6d8102684d))

## [2.14.1](https://github.com/laurigates/claude-plugins/compare/git-plugin-v2.14.0...git-plugin-v2.14.1) (2026-02-14)


### Documentation

* **git-plugin:** add conventional commits standards ([#616](https://github.com/laurigates/claude-plugins/issues/616)) ([5b74389](https://github.com/laurigates/claude-plugins/commit/5b74389ecdf5223dd62368390ecd9b36ccb1596c))

## [2.14.0](https://github.com/laurigates/claude-plugins/compare/git-plugin-v2.13.2...git-plugin-v2.14.0) (2026-02-12)


### Features

* **git-plugin:** use ./worktrees/ directory for agent worktree workflows ([a97db86](https://github.com/laurigates/claude-plugins/commit/a97db8613d879db4c06cefc6f94edcfca95f9043))


### Bug Fixes

* standardize skill name fields to kebab-case across all plugins ([72c0f83](https://github.com/laurigates/claude-plugins/commit/72c0f837a1b07004850c5906a30d619a79098f69))


### Code Refactoring

* reframe negative guidance as positive guidance across skills ([7e755ee](https://github.com/laurigates/claude-plugins/commit/7e755ee1c32c39c124f3204a0d0a8d1d770e1573))


### Documentation

* **git-plugin:** improve worktree documentation and migration notes ([03d04ef](https://github.com/laurigates/claude-plugins/commit/03d04ef1035d3a9f8675342c5c79ad163bc6edee))
* **git-plugin:** remove exclusive git permissions claims from git-ops agent ([0f92846](https://github.com/laurigates/claude-plugins/commit/0f928466543e7a302c11ff9d51ae481c8bf887eb))

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
