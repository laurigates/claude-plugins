# ADR-0006: Project Standards Enforcement

## Status

Accepted

## Date

2024-12 (retroactively documented 2025-12)

## Context

Professional development requires consistent infrastructure across projects: CI/CD pipelines, pre-commit hooks, test configurations, linting, container definitions, and more. Without standardization:

1. **Inconsistent quality**: Each project had different tool configurations
2. **Setup overhead**: Repeating configuration work for every new project
3. **Knowledge silos**: Best practices not shared across projects
4. **Drift**: Configurations diverge from standards over time
5. **Onboarding friction**: New contributors face different setups per project

A common stack pattern (FastAPI/Vue/Helm) emerged, and the principles apply broadly to any project.

## Decision

Create a **standards enforcement plugin** (`configure-plugin`) that provides:

### 30+ Configure Commands

```
/configure:all              # Apply all applicable standards
/configure:status           # Check current compliance
/configure:pre-commit       # Pre-commit hooks
/configure:release-please   # Automated releases
/configure:workflows        # GitHub Actions CI/CD
/configure:dockerfile       # Container definitions
/configure:tests            # Test infrastructure
/configure:coverage         # Code coverage
/configure:linting          # Linter configuration
/configure:formatting       # Code formatting
/configure:dead-code        # Dead code detection
/configure:security         # Security scanning
/configure:docs             # Documentation setup
/configure:mcp              # MCP server configuration
...and more
```

### Standards Tracking

Projects track their standards compliance in `.project-standards.yaml`:

```yaml
version: "1.0"
standards:
  pre-commit:
    enabled: true
    configured_at: "2024-12-15"
  release-please:
    enabled: true
    configured_at: "2024-12-15"
  workflows:
    enabled: true
    configured_at: "2024-12-15"
  testing:
    enabled: true
    tiers: [unit, integration]
```

### Supporting Skills

| Skill | Purpose |
|-------|---------|
| `ci-workflows` | GitHub Actions patterns |
| `pre-commit-standards` | Pre-commit hook configurations |
| `release-please-standards` | Release automation |
| `skaffold-standards` | Kubernetes deployment |

## Consequences

### Advantages

- **One-command setup**: `/configure:all` applies comprehensive standards
- **Consistency**: All projects follow same patterns
- **Best practices codified**: Expertise embedded in commands
- **Compliance visibility**: `/configure:status` shows gaps
- **Incremental adoption**: Apply standards one at a time
- **Living documentation**: Commands are executable documentation

### Disadvantages

- **Opinionated**: Standards reflect specific preferences
- **Maintenance burden**: Standards evolve; commands must update
- **Override complexity**: Projects with unique needs may conflict
- **Tool coupling**: Assumes specific toolchain (pre-commit, release-please, etc.)

### Standards Categories

| Category | Standards |
|----------|-----------|
| **Quality** | Pre-commit hooks, linting, formatting, dead code |
| **Testing** | Unit/integration/e2e setup, coverage, memory profiling |
| **CI/CD** | GitHub Actions, release-please, semantic versioning |
| **Security** | Secret scanning, dependency auditing, SAST |
| **Container** | Dockerfile, Skaffold, registry configuration |
| **Documentation** | README generation, API docs, changelog |

### Context-Aware Configuration

Commands detect project characteristics:

```yaml
## Context
- Package manager: !`find . -maxdepth 1 \( -name "pyproject.toml" ... \)`
- Pre-commit config: !`find . -maxdepth 1 -name ".pre-commit-config.yaml"`
- CI workflows: !`ls -la .github/workflows/ 2>/dev/null | head -10`
```

## Alternatives Considered

### 1. Template Repositories

Create GitHub template repos with pre-configured standards.

**Rejected**: No way to update existing projects; drift over time.

### 2. Cookiecutter/Yeoman

Use project scaffolding tools.

**Rejected**: One-time generation; doesn't help existing projects.

### 3. Manual Documentation

Write standards docs; developers implement manually.

**Rejected**: Inconsistent implementation; time-consuming.

### 4. Monorepo Standards

Enforce standards at monorepo level only.

**Rejected**: Many projects are standalone; need project-level standards.

## Related Decisions

- ADR-0005: Blueprint Development Methodology (methodology integration)
- ADR-0007: Namespace-Based Command Organization (`/configure:*` namespace)
- Dotfiles ADR-0009: Conventional Commits + Release-Please
