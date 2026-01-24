# ADR-0004: Marketplace Registry Model

## Status

Accepted

## Date

2024-12 (retroactively documented 2025-12)

## Context

With 23+ plugins in the repository, users need a way to:

1. **Discover** available plugins by category, keyword, or purpose
2. **Install** plugins without manually cloning repositories
3. **Update** plugins when new versions are available
4. **Browse** plugin metadata before installation

The Claude Code `/plugin install` command supports various sources, including local paths and remote repositories. We needed a way to organize our plugins for easy discovery and installation.

## Decision

Create a **marketplace registry** via `marketplace.json` at the repository root:

### Registry Structure

```json
{
  "name": "laurigates-plugins",
  "description": "Curated collection of Claude Code plugins",
  "owner": {
    "name": "Lauri Gates"
  },
  "homepage": "https://github.com/laurigates/claude-plugins",
  "plugins": [
    {
      "name": "blueprint-plugin",
      "source": "./blueprint-plugin",
      "description": "PRD → PRP workflow for structured feature development",
      "version": "1.1.0",
      "category": "methodology",
      "keywords": ["blueprint", "prd", "prp", "requirements"]
    },
    {
      "name": "python-plugin",
      "source": "./python-plugin",
      "description": "Python ecosystem: uv, ruff, pytest, basedpyright",
      "version": "1.0.0",
      "category": "language",
      "keywords": ["python", "uv", "ruff", "pytest"]
    }
  ]
}
```

### Installation Patterns

```bash
# Install from marketplace
/plugin install blueprint-plugin@laurigates-plugins

# Install directly from GitHub
/plugin install github:laurigates/claude-plugins/blueprint-plugin

# Install locally (for development)
/plugin install /path/to/claude-plugins/blueprint-plugin
```

### Category Taxonomy

| Category | Description |
|----------|-------------|
| `language` | Language ecosystem tools |
| `methodology` | Development workflows |
| `testing` | Test execution and quality |
| `infrastructure` | DevOps and CI/CD |
| `integration` | External system connectivity |
| `utility` | Cross-cutting tools |
| `specialized` | Domain-specific expertise |

## Consequences

### Advantages

- **Centralized discovery**: Single file lists all available plugins
- **Rich metadata**: Version, category, keywords enable filtering
- **Installation simplicity**: Short names instead of full paths
- **Browsable**: Users can read `marketplace.json` or render it as documentation
- **Scriptable**: Automation can parse JSON for bulk operations
- **Version tracking**: Marketplace reflects current stable versions

### Disadvantages

- **Manual maintenance**: Must update `marketplace.json` when plugins change
- **Single source**: All plugins in one repository (could split later)
- **No dependency resolution**: Plugins can recommend but not require companions
- **Version sync**: Plugin version in `plugin.json` must match `marketplace.json`

### Marketplace vs Plugin Manifest

| File | Purpose | Contains |
|------|---------|----------|
| `marketplace.json` | Discovery & installation | All plugins, categories, source paths |
| `plugin.json` | Plugin identity | Single plugin metadata, keywords |

The marketplace provides overview; individual manifests provide detail.

## Alternatives Considered

### 1. No Central Registry

Users specify full paths or GitHub URLs for every installation.

**Rejected**: Poor UX; requires knowing exact plugin locations.

### 2. NPM/Package Registry

Publish plugins to npm or a custom registry.

**Rejected**: Overhead of publishing; plugins are markdown, not packages.

### 3. GitHub Topics/Releases

Use GitHub repository features for discovery.

**Rejected**: Less structured; requires GitHub API calls for browsing.

### 4. Multiple Marketplaces

Separate registries for different plugin categories.

**Rejected**: Fragmentation; users would need to know which marketplace.

## Related Decisions

- ADR-0001: Plugin-Based Architecture
- ADR-0002: Domain-Driven Plugin Organization
- ADR-0008: Semantic Versioning with Manifest
