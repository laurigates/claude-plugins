# Changelog

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
