# Changelog

## [1.16.4](https://github.com/laurigates/claude-plugins/compare/hooks-plugin-v1.16.3...hooks-plugin-v1.16.4) (2026-04-08)


### Bug Fixes

* **blueprint-plugin:** remove model field from skills and fix invocation syntax ([#1007](https://github.com/laurigates/claude-plugins/issues/1007)) ([42e1e5b](https://github.com/laurigates/claude-plugins/commit/42e1e5b6c73d43e5de4b27cdee16e316de44d4c0))

## [1.16.3](https://github.com/laurigates/claude-plugins/compare/hooks-plugin-v1.16.2...hooks-plugin-v1.16.3) (2026-04-07)


### Bug Fixes

* **hooks-plugin:** replace prompt hook with command script for task completeness ([#1010](https://github.com/laurigates/claude-plugins/issues/1010)) ([9c03197](https://github.com/laurigates/claude-plugins/commit/9c03197c1a6578ba745202a2b8cd6424008644d7))

## [1.16.2](https://github.com/laurigates/claude-plugins/compare/hooks-plugin-v1.16.1...hooks-plugin-v1.16.2) (2026-04-01)


### Bug Fixes

* change test timeout decision from warn to approve ([#1000](https://github.com/laurigates/claude-plugins/issues/1000)) ([1e5fcfe](https://github.com/laurigates/claude-plugins/commit/1e5fcfe9b04f20ae274c571da64520c240a5a207))
* **hooks-plugin:** use valid schema value for test timeout decision ([1e5fcfe](https://github.com/laurigates/claude-plugins/commit/1e5fcfe9b04f20ae274c571da64520c240a5a207))

## [1.16.1](https://github.com/laurigates/claude-plugins/compare/hooks-plugin-v1.16.0...hooks-plugin-v1.16.1) (2026-04-01)


### Bug Fixes

* **hooks-plugin:** prevent UserPromptSubmit hook from misinterpreting user messages as agent messages ([716835e](https://github.com/laurigates/claude-plugins/commit/716835e16dd2c0cf8c6c9107ff087e8d7a0e0fc1))


### Performance

* safety classifier to distinguish user messages from AI responses ([#998](https://github.com/laurigates/claude-plugins/issues/998)) ([716835e](https://github.com/laurigates/claude-plugins/commit/716835e16dd2c0cf8c6c9107ff087e8d7a0e0fc1))

## [1.16.0](https://github.com/laurigates/claude-plugins/compare/hooks-plugin-v1.15.1...hooks-plugin-v1.16.0) (2026-03-30)


### Features

* hard timeout and fast test recipe preferences to test verification hook ([#996](https://github.com/laurigates/claude-plugins/issues/996)) ([ae039cd](https://github.com/laurigates/claude-plugins/commit/ae039cd462efac3c241aa9b24d80336ec9b0207e))

## [1.15.1](https://github.com/laurigates/claude-plugins/compare/hooks-plugin-v1.15.0...hooks-plugin-v1.15.1) (2026-03-30)


### Bug Fixes

* false positives in echo/printf redirection check for quoted strings ([#993](https://github.com/laurigates/claude-plugins/issues/993)) ([3e18f02](https://github.com/laurigates/claude-plugins/commit/3e18f02590e6889318ec76d1d1126d6567038b5d))
* **hooks-plugin:** prevent false positive on echo inside single-quoted strings ([3e18f02](https://github.com/laurigates/claude-plugins/commit/3e18f02590e6889318ec76d1d1126d6567038b5d))

## [1.15.0](https://github.com/laurigates/claude-plugins/compare/hooks-plugin-v1.14.2...hooks-plugin-v1.15.0) (2026-03-26)


### Features

* adapt permission guidance and settings for Claude Code auto mode ([#986](https://github.com/laurigates/claude-plugins/issues/986)) ([1203090](https://github.com/laurigates/claude-plugins/commit/120309051938470a5e3c80cc375c0bf7e37247ea)), closes [#983](https://github.com/laurigates/claude-plugins/issues/983)

## [1.14.2](https://github.com/laurigates/claude-plugins/compare/hooks-plugin-v1.14.1...hooks-plugin-v1.14.2) (2026-03-23)


### Code Refactoring

* branch protection hook with tiered permission decisions ([#972](https://github.com/laurigates/claude-plugins/issues/972)) ([9a672b4](https://github.com/laurigates/claude-plugins/commit/9a672b41e4eed381b45452cc7d7b3d48115b9b8f))

## [1.14.1](https://github.com/laurigates/claude-plugins/compare/hooks-plugin-v1.14.0...hooks-plugin-v1.14.1) (2026-03-13)


### Bug Fixes

* **git-repo-agent:** replace AskUserQuestion with two-phase Python-orchestrated interaction ([#939](https://github.com/laurigates/claude-plugins/issues/939)) ([8292e21](https://github.com/laurigates/claude-plugins/commit/8292e217d7b13b85e52240d55ed6f059fb0ace82))

## [1.14.0](https://github.com/laurigates/claude-plugins/compare/hooks-plugin-v1.13.5...hooks-plugin-v1.14.0) (2026-03-13)


### Features

* hooks-permission-request-hook skill for auto-approval rules ([#937](https://github.com/laurigates/claude-plugins/issues/937)) ([0ab8571](https://github.com/laurigates/claude-plugins/commit/0ab8571dcb5f82e8b88e3db24457c7c55fd8dbfe))
* **hooks-plugin:** add permission-request-hook skill ([0ab8571](https://github.com/laurigates/claude-plugins/commit/0ab8571dcb5f82e8b88e3db24457c7c55fd8dbfe))

## [1.13.5](https://github.com/laurigates/claude-plugins/compare/hooks-plugin-v1.13.4...hooks-plugin-v1.13.5) (2026-03-12)


### Bug Fixes

* cat pipeline regression and improve test runner detection ([#932](https://github.com/laurigates/claude-plugins/issues/932)) ([d51ce4f](https://github.com/laurigates/claude-plugins/commit/d51ce4fda7a3cc71ba024a162eeadb07ea518b6e))
* **hooks-plugin:** fix pytest hook issues and cat pipeline false positive ([d51ce4f](https://github.com/laurigates/claude-plugins/commit/d51ce4fda7a3cc71ba024a162eeadb07ea518b6e))

## [1.13.4](https://github.com/laurigates/claude-plugins/compare/hooks-plugin-v1.13.3...hooks-plugin-v1.13.4) (2026-03-12)


### Bug Fixes

* allow local git merge on protected branches ([#929](https://github.com/laurigates/claude-plugins/issues/929)) ([eb11049](https://github.com/laurigates/claude-plugins/commit/eb11049f8a33d7ed077cbc062759d823908b1209))
* **hooks-plugin:** allow local merge to main in branch protection ([eb11049](https://github.com/laurigates/claude-plugins/commit/eb11049f8a33d7ed077cbc062759d823908b1209)), closes [#42](https://github.com/laurigates/claude-plugins/issues/42)

## [1.13.3](https://github.com/laurigates/claude-plugins/compare/hooks-plugin-v1.13.2...hooks-plugin-v1.13.3) (2026-03-11)


### Bug Fixes

* **hooks-plugin:** fix env var syntax and bun test command ([#926](https://github.com/laurigates/claude-plugins/issues/926)) ([b5a1dd4](https://github.com/laurigates/claude-plugins/commit/b5a1dd48d69e0665de37e408e8484d3acf8221c4))

## [1.13.2](https://github.com/laurigates/claude-plugins/compare/hooks-plugin-v1.13.1...hooks-plugin-v1.13.2) (2026-03-11)


### Bug Fixes

* **hooks-plugin:** fix secret-protection.sh failing on non-sensitive files ([4328a4d](https://github.com/laurigates/claude-plugins/commit/4328a4de045b9188eded91080140f579d87f474c))
* secret protection hook return codes ([#921](https://github.com/laurigates/claude-plugins/issues/921)) ([4328a4d](https://github.com/laurigates/claude-plugins/commit/4328a4de045b9188eded91080140f579d87f474c))

## [1.13.1](https://github.com/laurigates/claude-plugins/compare/hooks-plugin-v1.13.0...hooks-plugin-v1.13.1) (2026-03-09)


### Performance

* **hooks-plugin:** replace agent hook with deterministic test verification script ([#906](https://github.com/laurigates/claude-plugins/issues/906)) ([8a29621](https://github.com/laurigates/claude-plugins/commit/8a296219e31f53cbf7a960c5c15bbdd3fe0cc204))

## [1.13.0](https://github.com/laurigates/claude-plugins/compare/hooks-plugin-v1.12.2...hooks-plugin-v1.13.0) (2026-03-05)


### Features

* standardize shell script conventions and add linting ([#892](https://github.com/laurigates/claude-plugins/issues/892)) ([0eba700](https://github.com/laurigates/claude-plugins/commit/0eba7009728418bdef6355bd91fc9ee50c6982a8))

## [1.12.2](https://github.com/laurigates/claude-plugins/compare/hooks-plugin-v1.12.1...hooks-plugin-v1.12.2) (2026-03-03)


### Bug Fixes

* **hooks-plugin:** fix UserPromptSubmit hook false-positives and user-facing message ([b8316cf](https://github.com/laurigates/claude-plugins/commit/b8316cff8a0773553e258563dd10117d34feb617))
* **hooks-plugin:** prevent echo false positive when followed by unrelated 2&gt;/dev/null ([e6ca8ab](https://github.com/laurigates/claude-plugins/commit/e6ca8ab305d37cf4551081d617e0821c0dbfe6a8))
* refine safety prompt classification with stricter criteria ([#863](https://github.com/laurigates/claude-plugins/issues/863)) ([b8316cf](https://github.com/laurigates/claude-plugins/commit/b8316cff8a0773553e258563dd10117d34feb617))
* regex false positives in echo/printf file-write detection ([#864](https://github.com/laurigates/claude-plugins/issues/864)) ([e6ca8ab](https://github.com/laurigates/claude-plugins/commit/e6ca8ab305d37cf4551081d617e0821c0dbfe6a8))

## [1.12.1](https://github.com/laurigates/claude-plugins/compare/hooks-plugin-v1.12.0...hooks-plugin-v1.12.1) (2026-03-02)


### Documentation

* **rules:** update rules and skills for Claude Code 2.1.50-2.1.63 ([#859](https://github.com/laurigates/claude-plugins/issues/859)) ([6c66021](https://github.com/laurigates/claude-plugins/commit/6c66021fefa205abfc4f575229e3bbb9cdc6263a))

## [1.12.0](https://github.com/laurigates/claude-plugins/compare/hooks-plugin-v1.11.1...hooks-plugin-v1.12.0) (2026-03-01)


### Features

* add security, branch protection, and checkpoint hooks ([#852](https://github.com/laurigates/claude-plugins/issues/852)) ([55441bf](https://github.com/laurigates/claude-plugins/commit/55441bf40fcb3b5fa34572fa2c6087e8365b73b7))


### Bug Fixes

* **hooks-plugin:** stop hook should allow Claude confirmation questions ([f6ca9d4](https://github.com/laurigates/claude-plugins/commit/f6ca9d42255a9423391872db712f026ceb8566b3))
* replace test -f/-d with find in context commands ([#850](https://github.com/laurigates/claude-plugins/issues/850)) ([a236ac8](https://github.com/laurigates/claude-plugins/commit/a236ac80ab81ce37878268b2ad76f7ad6d4aa5fb))

## [1.11.1](https://github.com/laurigates/claude-plugins/compare/hooks-plugin-v1.11.0...hooks-plugin-v1.11.1) (2026-03-01)


### Bug Fixes

* bash-antipatterns hook exemptions for find and grep ([#845](https://github.com/laurigates/claude-plugins/issues/845)) ([f618dd6](https://github.com/laurigates/claude-plugins/commit/f618dd6715b1d920f9807ded9b8368ebe3c8f358))
* **hooks-plugin:** correct find and grep exemptions in bash-antipatterns hook ([f618dd6](https://github.com/laurigates/claude-plugins/commit/f618dd6715b1d920f9807ded9b8368ebe3c8f358))

## [1.11.0](https://github.com/laurigates/claude-plugins/compare/hooks-plugin-v1.10.2...hooks-plugin-v1.11.0) (2026-03-01)


### Features

* add GitHub MCP server configuration ([#846](https://github.com/laurigates/claude-plugins/issues/846)) ([47baa7f](https://github.com/laurigates/claude-plugins/commit/47baa7fcb9605b585148ddf2deabc98652bf58bd))

## [1.10.2](https://github.com/laurigates/claude-plugins/compare/hooks-plugin-v1.10.1...hooks-plugin-v1.10.2) (2026-02-28)


### Bug Fixes

* **hooks-plugin:** narrow git chain check to index-modifying commands ([f8d24e6](https://github.com/laurigates/claude-plugins/commit/f8d24e655960aafaffcc0026064c7e026ef98810))
* refine git chained command check to only flag index-modifying operations ([#843](https://github.com/laurigates/claude-plugins/issues/843)) ([f8d24e6](https://github.com/laurigates/claude-plugins/commit/f8d24e655960aafaffcc0026064c7e026ef98810))

## [1.10.1](https://github.com/laurigates/claude-plugins/compare/hooks-plugin-v1.10.0...hooks-plugin-v1.10.1) (2026-02-28)


### Bug Fixes

* **hooks-plugin:** scope git stash reminder to session-created stashes only ([#841](https://github.com/laurigates/claude-plugins/issues/841)) ([bf35e8d](https://github.com/laurigates/claude-plugins/commit/bf35e8d9ebf755ab429cae647d3bf36cf4fba89e))

## [1.10.0](https://github.com/laurigates/claude-plugins/compare/hooks-plugin-v1.9.0...hooks-plugin-v1.10.0) (2026-02-27)


### Features

* **hooks-plugin:** add session-end issue hook for deferred todo tracking ([#839](https://github.com/laurigates/claude-plugins/issues/839)) ([3549547](https://github.com/laurigates/claude-plugins/commit/35495473cc93c7828577edc796f50f4ea58443e1))

## [1.9.0](https://github.com/laurigates/claude-plugins/compare/hooks-plugin-v1.8.0...hooks-plugin-v1.9.0) (2026-02-27)


### Features

* **hooks-plugin:** add LLM-powered prompt and agent hooks documentation and examples ([#834](https://github.com/laurigates/claude-plugins/issues/834)) ([203d1d9](https://github.com/laurigates/claude-plugins/commit/203d1d9494e37771b1186f0e50948c75109c8fe6))

## [1.8.0](https://github.com/laurigates/claude-plugins/compare/hooks-plugin-v1.7.1...hooks-plugin-v1.8.0) (2026-02-27)


### Features

* add metadata fields to skill definitions across all plugins ([#828](https://github.com/laurigates/claude-plugins/issues/828)) ([59b3d1f](https://github.com/laurigates/claude-plugins/commit/59b3d1fadd8fd888f95ced8b071fb66cf6f9c825))
* add skill invocation control via user-invocable and disable-model-invocation frontmatter ([59b3d1f](https://github.com/laurigates/claude-plugins/commit/59b3d1fadd8fd888f95ced8b071fb66cf6f9c825))

## [1.7.1](https://github.com/laurigates/claude-plugins/compare/hooks-plugin-v1.7.0...hooks-plugin-v1.7.1) (2026-02-27)


### Bug Fixes

* **hooks-plugin:** Skip branch operations in git worktrees during session cleanup ([#826](https://github.com/laurigates/claude-plugins/issues/826)) ([63104c9](https://github.com/laurigates/claude-plugins/commit/63104c9eab8354128e7b6ddc7c7ab11ccae53ffe))
* **hooks-plugin:** skip git switch and pull in worktrees during SessionEnd ([63104c9](https://github.com/laurigates/claude-plugins/commit/63104c9eab8354128e7b6ddc7c7ab11ccae53ffe))

## [1.7.0](https://github.com/laurigates/claude-plugins/compare/hooks-plugin-v1.6.0...hooks-plugin-v1.7.0) (2026-02-26)


### Features

* **hooks-plugin:** add SessionEnd hook for git session cleanup ([#820](https://github.com/laurigates/claude-plugins/issues/820)) ([0c59ce1](https://github.com/laurigates/claude-plugins/commit/0c59ce1c885a1a798d5daf5ae10922aa6219f46f))


### Bug Fixes

* **scripts:** enhance context command linter with stderr safety checks and fix violations ([#819](https://github.com/laurigates/claude-plugins/issues/819)) ([2975b9b](https://github.com/laurigates/claude-plugins/commit/2975b9b0bf6698bdecf627e3d28bad06fde03cd1))

## [1.6.0](https://github.com/laurigates/claude-plugins/compare/hooks-plugin-v1.5.8...hooks-plugin-v1.6.0) (2026-02-26)


### Features

* **hooks-plugin:** add git stash reminder Stop hook ([#817](https://github.com/laurigates/claude-plugins/issues/817)) ([1edf2a9](https://github.com/laurigates/claude-plugins/commit/1edf2a97e16eaaa3523f0c4d02d06ea7087816b1))

## [1.5.8](https://github.com/laurigates/claude-plugins/compare/hooks-plugin-v1.5.7...hooks-plugin-v1.5.8) (2026-02-26)


### Documentation

* **hooks-plugin:** document Claude Code 2.1.50 hook system enhancements ([#813](https://github.com/laurigates/claude-plugins/issues/813)) ([92f1b1d](https://github.com/laurigates/claude-plugins/commit/92f1b1dda1ba03918f283f9961c7a161dd3fdf70)), closes [#798](https://github.com/laurigates/claude-plugins/issues/798)

## [1.5.7](https://github.com/laurigates/claude-plugins/compare/hooks-plugin-v1.5.6...hooks-plugin-v1.5.7) (2026-02-23)


### Bug Fixes

* remove 2&gt;/dev/null from context commands across all plugins ([#792](https://github.com/laurigates/claude-plugins/issues/792)) ([c72e67e](https://github.com/laurigates/claude-plugins/commit/c72e67ee37e809449f0e6282c48fac01363a59fd))

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
