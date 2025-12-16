---
allowed-tools: Read, Write, Edit, MultiEdit, Bash(pip install:*), Bash(npm install:*), Bash(pre-commit:*), Bash(pytest:*), Bash(npm test:*), Bash(git:*), TodoWrite, SlashCommand
description: Configure comprehensive testing infrastructure with CI/CD integration
argument-hint: [--coverage] [--ci <github|gitlab|circleci>]
---

## Context

- Package files: !`find . -maxdepth 1 \( -name "package.json" -o -name "pyproject.toml" -o -name "setup.py" -o -name "go.mod" -o -name "Cargo.toml" \) -type f`
- Test config: !`find . -maxdepth 1 \( -name "pytest.ini" -o -name "jest.config.*" -o -name "vitest.config.*" -o -name ".mocharc.*" \) -type f`
- Pre-commit config: !`find . -maxdepth 1 -name ".pre-commit-config.yaml" -type f`
- GitHub Actions: !`find .github/workflows -maxdepth 1 -type f -name "*.yml" -o -name "*.yaml"`

## Your task

### 1. Pre-commit Setup
- Install pre-commit if needed: `pip install pre-commit`
- Create/update `.pre-commit-config.yaml` with language-specific hooks
- Install hooks: `pre-commit install`
- Test with: `pre-commit run --all-files`

### 2. Test Structure
- Create test directories: `tests/unit`, `tests/integration`, `tests/e2e`
- Write comprehensive tests covering:
  - Unit tests for all functions
  - Integration tests for components
  - Edge cases and error handling
- Use SlashCommand: `/test:run` to verify test execution
- Use SlashCommand: `/lint:check` to ensure test code quality

### 3. GitHub Actions
- Create `.github/workflows/tests.yml` with matrix testing
- Add coverage reporting with Codecov integration
- Configure GitHub Pages for coverage reports

### 4. Documentation
- Set up documentation generation (Sphinx/TypeDoc/godoc)
- Create `.github/workflows/docs.yml` for auto-generation
- Deploy docs to GitHub Pages

### 5. Badges
- Add test and coverage badges to README
