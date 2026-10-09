# configure-pre-commit Reference

Canonical hook list, pinned versions, per-project-type configurations, and
compliance conventions. (Absorbed the former `pre-commit-standards`
reference skill.)

## Version: 2025.1

Standard pre-commit configuration for repository compliance.

## Standard Versions (2025.1)

| Hook | Version | Purpose |
|------|---------|---------|
| pre-commit-hooks | v6.0.0 | Core hooks (trailing-whitespace, check-yaml, etc.) |
| conventional-pre-commit | v4.4.0 | Conventional commit message validation |
| biome | v2.4.16 | Code formatting and linting (JS, TS, JSON) |
| gruntwork pre-commit | v0.1.30 | helmlint, tflint (infrastructure only) |
| actionlint | v1.7.12 | GitHub Actions validation (infrastructure only) |
| helm-docs | v1.14.2 | Helm documentation (infrastructure only) |
| gitleaks | v8.30.1 | Secret scanning (recommended) |

## Project Type Configurations

### Frontend App (Vue/React)

Required hooks for frontend applications:

```yaml
default_install_hook_types:
  - pre-commit
  - commit-msg
default_stages: [pre-commit]

repos:
  - repo: https://github.com/pre-commit/pre-commit-hooks
    rev: v6.0.0
    hooks:
      - id: trailing-whitespace
      - id: end-of-file-fixer
      - id: check-yaml
        exclude: ^(helm/templates/|skaffold/|k8s/).*\.ya?ml$
      - id: check-json
        exclude: tsconfig\.json$
      - id: check-added-large-files
        args: ['--maxkb=1000']
      - id: check-merge-conflict
      - id: detect-private-key

  - repo: https://github.com/compilerla/conventional-pre-commit
    rev: v4.4.0
    hooks:
      - id: conventional-pre-commit
        stages: [commit-msg]

  - repo: https://github.com/biomejs/pre-commit
    rev: v2.4.16
    hooks:
      - id: biome-check
        additional_dependencies: ["@biomejs/biome@2.4.16"]

  # Optional: If project has Helm charts
  - repo: https://github.com/gruntwork-io/pre-commit
    rev: v0.1.30
    hooks:
      - id: helmlint
        files: ^helm/
```

### Infrastructure Repository

Required hooks for infrastructure (Terraform, Helm, ArgoCD):

```yaml
default_install_hook_types:
  - pre-commit
  - commit-msg
default_stages: [pre-commit]

repos:
  - repo: https://github.com/pre-commit/pre-commit-hooks
    rev: v6.0.0
    hooks:
      - id: trailing-whitespace
      - id: end-of-file-fixer
      - id: check-yaml
        args: [--allow-multiple-documents]
        exclude: argocd/.*templates/|helm/[^/]+/templates/
      - id: check-json
      - id: check-merge-conflict
      - id: check-symlinks
      - id: check-toml
      - id: check-added-large-files

  - repo: https://github.com/compilerla/conventional-pre-commit
    rev: v4.4.0
    hooks:
      - id: conventional-pre-commit
        stages: [commit-msg]

  - repo: https://github.com/gruntwork-io/pre-commit
    rev: v0.1.30
    hooks:
      - id: tflint
      - id: helmlint

  - repo: https://github.com/rhysd/actionlint
    rev: v1.7.12
    hooks:
      - id: actionlint

  - repo: https://github.com/norwoodj/helm-docs
    rev: v1.14.2
    hooks:
      - id: helm-docs
        args:
          - --chart-search-root=helm

  - repo: https://github.com/gitleaks/gitleaks
    rev: v8.30.1
    hooks:
      - id: gitleaks
```

### Python Service

Required hooks for Python projects:

```yaml
default_install_hook_types:
  - pre-commit
  - commit-msg
default_stages: [pre-commit]

repos:
  - repo: https://github.com/pre-commit/pre-commit-hooks
    rev: v6.0.0
    hooks:
      - id: trailing-whitespace
      - id: end-of-file-fixer
      - id: check-yaml
      - id: check-json
      - id: check-toml
      - id: check-added-large-files
      - id: check-merge-conflict
      - id: detect-private-key

  - repo: https://github.com/compilerla/conventional-pre-commit
    rev: v4.4.0
    hooks:
      - id: conventional-pre-commit
        stages: [commit-msg]

  - repo: https://github.com/astral-sh/ruff-pre-commit
    rev: v0.15.15
    hooks:
      - id: ruff
        args: [--fix]
      - id: ruff-format

  - repo: https://github.com/gitleaks/gitleaks
    rev: v8.30.1
    hooks:
      - id: gitleaks
```

## Compliance Checking

### Required Base Hooks (All Projects)

Every repository MUST have these hooks:

1. **pre-commit-hooks** (v6.0.0+)
   - `trailing-whitespace`
   - `end-of-file-fixer`
   - `check-yaml`
   - `check-json`
   - `check-merge-conflict`
   - `check-added-large-files`

2. **conventional-pre-commit** (v4.4.0+)
   - `conventional-pre-commit` in `commit-msg` stage

3. **Hook-type settings**
   - `default_install_hook_types` lists `pre-commit` and `commit-msg`
   - `default_stages: [pre-commit]` is set whenever `commit-msg` is installed
     (WARN when missing: every file hook runs twice per commit)

### Status Levels

| Status | Meaning |
|--------|---------|
| PASS | Hook present with compliant version |
| WARN | Hook present but version outdated |
| FAIL | Required hook missing |
| SKIP | Hook not applicable for project type |

### Version Comparison

When checking versions:
- Exact match or newer: PASS
- Older by patch version: WARN (functional but should update)
- Missing entirely: FAIL (must add)

## Exclusion Patterns

### Frontend Apps

Exclude Kubernetes/Helm templates from YAML/prettier checks:

```yaml
exclude: ^(helm/templates/|skaffold/|k8s/).*\.ya?ml$
```

### Infrastructure

Exclude ArgoCD and Helm templates:

```yaml
exclude: argocd/.*templates/|helm/[^/]+/templates/
```

### Python

No special exclusions needed for standard Python projects.

## Installation

After configuring `.pre-commit-config.yaml`:

```bash
pre-commit install --install-hooks
```

`default_install_hook_types` makes that one command install both the
`pre-commit` and `commit-msg` hook types; `--install-hooks` also builds the hook
environments up front. Without `default_install_hook_types`, plain
`pre-commit install` installs only the `pre-commit` type and commit-msg hooks
never run.

### Why `default_stages: [pre-commit]`

A hook with no `stages` key runs at every installed stage. Once the
`commit-msg` type is installed, every file hook (whitespace fixers,
`check-yaml`, `gitleaks`, …) runs twice per commit, once at pre-commit and again
at commit-msg, which doubles the time and prints the hook list twice.
`default_stages: [pre-commit]` confines unstaged hooks to the pre-commit stage;
the message hooks keep their explicit `stages: [commit-msg]`. Write it whenever
`commit-msg` is among the installed hook types (observed with pre-commit 4.6.2
and pre-commit-hooks v6.0.0, #2824).

## Updating

To update all hooks to latest versions:

```bash
pre-commit autoupdate
```

Then verify versions match project standards.
