# Changelog

## [1.6.1](https://github.com/laurigates/claude-plugins/compare/session-plugin-v1.6.0...session-plugin-v1.6.1) (2026-07-05)


### Bug Fixes

* **session-plugin:** surface gh availability so spinup retrieves GitHub issues ([#2001](https://github.com/laurigates/claude-plugins/issues/2001)) ([4a236f3](https://github.com/laurigates/claude-plugins/commit/4a236f3c196ea64a8abc26416b40de6cb0754dbe))

## [1.6.0](https://github.com/laurigates/claude-plugins/compare/session-plugin-v1.5.2...session-plugin-v1.6.0) (2026-07-05)


### Features

* **session-plugin:** surface blueprint tracker state in survey and offer drain pass at session-end ([#1998](https://github.com/laurigates/claude-plugins/issues/1998)) ([9a4b7a9](https://github.com/laurigates/claude-plugins/commit/9a4b7a9fa413d4c5442c108786750e08f54fa4b1))

## [1.5.2](https://github.com/laurigates/claude-plugins/compare/session-plugin-v1.5.1...session-plugin-v1.5.2) (2026-07-04)


### Bug Fixes

* **session-plugin:** base session-survey PRS on --author, not local branch ([#1941](https://github.com/laurigates/claude-plugins/issues/1941)) ([378b34c](https://github.com/laurigates/claude-plugins/commit/378b34c4f7584da0dd82a84c69b7ec5f85777600)), closes [#1915](https://github.com/laurigates/claude-plugins/issues/1915)

## [1.5.1](https://github.com/laurigates/claude-plugins/compare/session-plugin-v1.5.0...session-plugin-v1.5.1) (2026-07-04)


### Documentation

* archive completed/superseded planning docs under docs/archive/ ([#1940](https://github.com/laurigates/claude-plugins/issues/1940)) ([fe24f13](https://github.com/laurigates/claude-plugins/commit/fe24f1342e5f9370ed75729a86707bc5b66b7052)), closes [#1850](https://github.com/laurigates/claude-plugins/issues/1850) [#1460](https://github.com/laurigates/claude-plugins/issues/1460)

## [1.5.0](https://github.com/laurigates/claude-plugins/compare/session-plugin-v1.4.2...session-plugin-v1.5.0) (2026-06-29)


### Features

* **session-plugin:** add [PROMOTE] cross-repo promotion to session-distill ([#1881](https://github.com/laurigates/claude-plugins/issues/1881)) ([5b277cc](https://github.com/laurigates/claude-plugins/commit/5b277ccb76ed6ab2f26e753cccd3807adb4849d9))

## [1.4.2](https://github.com/laurigates/claude-plugins/compare/session-plugin-v1.4.1...session-plugin-v1.4.2) (2026-06-25)


### Bug Fixes

* **session-plugin:** session-end uses working UUID-capture command ([#1822](https://github.com/laurigates/claude-plugins/issues/1822)) ([18a5d24](https://github.com/laurigates/claude-plugins/commit/18a5d2495b50cf3511cc65276a04fa83f05d25ac))

## [1.4.1](https://github.com/laurigates/claude-plugins/compare/session-plugin-v1.4.0...session-plugin-v1.4.1) (2026-06-24)


### Code Refactoring

* **session-plugin:** extract shared read-only survey collector ([#1799](https://github.com/laurigates/claude-plugins/issues/1799)) ([57a10c2](https://github.com/laurigates/claude-plugins/commit/57a10c277d9666cfc8306be5803952705a9d6856))

## [1.4.0](https://github.com/laurigates/claude-plugins/compare/session-plugin-v1.3.3...session-plugin-v1.4.0) (2026-06-22)


### Features

* **session-plugin:** surface untracked assigned GitHub issues in spinup ([#1761](https://github.com/laurigates/claude-plugins/issues/1761)) ([6066c14](https://github.com/laurigates/claude-plugins/commit/6066c148512fdde1bb8411b26426e448690fc744))

## [1.3.3](https://github.com/laurigates/claude-plugins/compare/session-plugin-v1.3.2...session-plugin-v1.3.3) (2026-06-20)


### Bug Fixes

* **hooks-plugin:** guard test/hook mktemp -d sandboxes against shared-checkout git leak ([#1719](https://github.com/laurigates/claude-plugins/issues/1719)) ([448b212](https://github.com/laurigates/claude-plugins/commit/448b2127a7240136dffd721ad1309c2375cc0814))

## [1.3.2](https://github.com/laurigates/claude-plugins/compare/session-plugin-v1.3.1...session-plugin-v1.3.2) (2026-06-19)


### Bug Fixes

* **session-plugin:** prevent cross-project bleed in session-spinup ([#1705](https://github.com/laurigates/claude-plugins/issues/1705)) ([8d7312c](https://github.com/laurigates/claude-plugins/commit/8d7312ce6405692122f5ead89212e1968e91811a))

## [1.3.1](https://github.com/laurigates/claude-plugins/compare/session-plugin-v1.3.0...session-plugin-v1.3.1) (2026-06-18)


### Code Refactoring

* make Obsidian vault skills and vault-agent vault-agnostic ([#1698](https://github.com/laurigates/claude-plugins/issues/1698)) ([1e95452](https://github.com/laurigates/claude-plugins/commit/1e95452d966cbe8dcedb807a0717d2d1778c86af))

## [1.3.0](https://github.com/laurigates/claude-plugins/compare/session-plugin-v1.2.0...session-plugin-v1.3.0) (2026-06-18)


### Features

* **scripts:** context-command execution harness + sweep 122 fragile Context commands ([#1690](https://github.com/laurigates/claude-plugins/issues/1690)) ([609342f](https://github.com/laurigates/claude-plugins/commit/609342f2c5b6b5f2ee555f83dbac1f5f3dd1f93d))

## [1.2.0](https://github.com/laurigates/claude-plugins/compare/session-plugin-v1.1.0...session-plugin-v1.2.0) (2026-06-13)


### Features

* **session-plugin:** chain taskwarrior state sync into session teardown ([#1618](https://github.com/laurigates/claude-plugins/issues/1618)) ([f2c8cae](https://github.com/laurigates/claude-plugins/commit/f2c8cae82bbcf9c8c4ebb433068de21f491a082b))

## [1.1.0](https://github.com/laurigates/claude-plugins/compare/session-plugin-v1.0.0...session-plugin-v1.1.0) (2026-06-10)


### Features

* **session-plugin:** add session bookends plugin with end-of-session orchestrator ([#1561](https://github.com/laurigates/claude-plugins/issues/1561)) ([03e10f9](https://github.com/laurigates/claude-plugins/commit/03e10f9c081a0cff6dae306b47d9d514da3e3265))
