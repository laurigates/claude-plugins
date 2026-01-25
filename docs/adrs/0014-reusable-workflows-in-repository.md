# ADR-0014: Reusable GitHub Workflows in Plugin Repository

---
date: 2026-01-25
created: 2026-01-25
modified: 2026-01-25
status: Accepted
deciders: claude-plugins team
domain: ci-cd
relates-to:
  - PRD-002
github-issues: []
---

## Context

We need to provide reusable GitHub Action workflows that leverage Claude Code and the claude-plugins ecosystem for CI/CD automation. The key architectural decision is where these workflows should live:

1. **In this repository** alongside the plugins
2. **In a separate repository** dedicated to workflows
3. **In consumer repositories** via templates or generators

GitHub's reusable workflows have specific constraints documented in [official documentation](https://docs.github.com/en/actions/how-tos/reuse-automations/reuse-workflows):

- All reusable workflows must be in `.github/workflows/` (no subdirectories)
- Max 50 unique reusable workflows per caller
- Max 10 levels of nesting depth
- Environment variables do NOT propagate from caller to called workflow
- Environment secrets cannot be passed via `workflow_call`

## Decision

**Keep reusable workflows in this repository (`claude-plugins`)** alongside the plugins they use.

### Rationale

| Benefit | Explanation |
|---------|-------------|
| **Coupled versioning** | Workflow updates ship with plugin updates |
| **Single source of truth** | No version coordination between repos |
| **Easier testing** | Test workflow changes against plugin changes in same PR |
| **Simpler consumption** | Users reference one repo for both plugins and workflows |
| **Plugin access** | Workflows can reference plugins via `plugin_marketplaces` |

### File Organization

Since subdirectories are not supported, use **naming prefixes** to organize:

```
.github/workflows/
├── reusable-security-owasp.yml       # Reusable (external consumption)
├── reusable-security-secrets.yml
├── reusable-a11y-wcag.yml
├── reusable-quality-code-smell.yml
├── reusable-quality-typescript.yml
├── ...
├── release-please.yml                 # Internal (this repo only)
├── skill-quality-review.yml
└── claude.yml
```

**Convention:**
- `reusable-*` prefix = callable from other repositories
- No prefix = internal to this repository

### Consumer Reference Pattern

External repositories consume workflows via:

```yaml
jobs:
  security:
    uses: laurigates/claude-plugins/.github/workflows/reusable-security-owasp.yml@v2.0.0
    secrets: inherit
```

**Reference options** (in order of recommendation):

| Method | Example | Use When |
|--------|---------|----------|
| Release tag | `@v2.0.0` | Production use (recommended) |
| Commit SHA | `@a1b2c3d4...` | Maximum security/reproducibility |
| Branch | `@main` | Development/testing only |

### Secrets Handling

**Option 1: Inherit (same organization)**
```yaml
secrets: inherit
```

**Option 2: Pass explicitly**
```yaml
secrets:
  CLAUDE_CODE_OAUTH_TOKEN: ${{ secrets.CLAUDE_CODE_OAUTH_TOKEN }}
```

## Consequences

### Positive

- **Version lock**: Consumers can pin to a specific release tag for stability
- **Atomic updates**: Plugin and workflow changes are tested together
- **Discoverability**: Users find everything in one place
- **Plugin leverage**: Workflows automatically load plugins from marketplace

### Negative

- **Larger repository**: More files in `.github/workflows/`
- **Flat structure**: No subdirectories for organization (GitHub constraint)
- **Release coupling**: Workflow-only fixes still require a release
- **Naming discipline**: Must maintain `reusable-*` convention manually

### Mitigations

| Issue | Mitigation |
|-------|------------|
| Flat structure | Consistent naming prefixes (`reusable-security-*`, `reusable-a11y-*`) |
| Release coupling | Minor version bumps for workflow-only changes |
| Naming discipline | PR review checklist, CI validation |

## Options Considered

### Option 1: Workflows in Plugin Repository (CHOSEN)

**Pros:**
- Coupled versioning
- Single source of truth
- Plugin access via marketplace

**Cons:**
- Larger repository
- Flat workflow directory

### Option 2: Separate Workflows Repository

**Pros:**
- Clean separation of concerns
- Independent release cycle

**Cons:**
- Version coordination between repos
- Plugin version pinning complexity
- Two repos for users to track

### Option 3: Template Generator

**Pros:**
- Customizable per consumer
- Full control in consumer repo

**Cons:**
- No centralized updates
- Drift between implementations
- Maintenance burden on consumers

## Related ADRs

- [ADR-0001: Plugin-Based Architecture](0001-plugin-based-architecture.md) - Foundation for plugin ecosystem
- [ADR-0004: Marketplace Registry Model](0004-marketplace-registry-model.md) - How workflows load plugins

## References

- [GitHub: Reusing workflows](https://docs.github.com/en/actions/how-tos/reuse-automations/reuse-workflows)
- [GitHub Blog: Using reusable workflows](https://github.blog/developer-skills/github/using-reusable-workflows-github-actions/)
