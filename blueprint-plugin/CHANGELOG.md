# Changelog

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
