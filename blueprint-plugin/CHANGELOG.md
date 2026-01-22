# Changelog

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
