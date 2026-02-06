# health-plugin

Diagnose and fix Claude Code configuration issues including plugin registry, settings, hooks, and MCP servers.

## Installation

```bash
/plugin install health-plugin@laurigates-claude-plugins
```

## Skills

| Skill | Description |
|-------|-------------|
| `/health:agentic-audit` | Audit skills, commands, and agents for agentic output optimization |
| `/health:audit` | Audit enabled plugins against project tech stack and recommend additions/removals |
| `/health:check` | Comprehensive diagnostic scan of Claude Code environment |
| `/health:plugins` | Diagnose and fix plugin registry issues (addresses [#14202](https://github.com/anthropics/claude-code/issues/14202)) |
| `plugin-registry` | Understanding Claude Code's plugin registry, scopes, and troubleshooting |
| `settings-configuration` | Settings file hierarchy, permission wildcards, and patterns |

## Scripts

| Script | Description |
|--------|-------------|
| `prune-claude-config.py` | Remove orphaned projects and cached data from `~/.claude.json` |

## Use Cases

### Plugin Shows "Installed" But Doesn't Work

This is a known issue ([#14202](https://github.com/anthropics/claude-code/issues/14202)) where project-scoped plugins incorrectly appear as globally installed.

```bash
# Diagnose the issue
/health:plugins

# Fix automatically
/health:plugins --fix
```

### Full Environment Health Check

```bash
# Run all diagnostics
/health:check

# With verbose output
/health:check --verbose
```

### Audit Plugin Relevance

Ensure only relevant plugins are enabled for your project:

```bash
# See what plugins are relevant to this project
/health:audit

# Preview changes without applying
/health:audit --dry-run

# Apply recommended changes
/health:audit --fix
```

This analyzes your project's tech stack (package.json, Cargo.toml, Dockerfile, etc.) and recommends:
- Removing plugins that don't apply (e.g., kubernetes-plugin if no K8s manifests)
- Adding plugins that match detected technologies (e.g., container-plugin if Dockerfile exists)

### Permission Debugging

When tools are blocked unexpectedly, use the settings-configuration skill to understand:
- Settings file hierarchy (user → project → local)
- Permission wildcard patterns
- Shell operator protections

### Prune Config File

Clean up your `~/.claude.json` by removing orphaned projects and cached data:

```bash
# Preview what would be removed
python health-plugin/scripts/prune-claude-config.py --dry-run

# Interactive mode (confirm before changes)
python health-plugin/scripts/prune-claude-config.py --interactive

# Run immediately (creates backup automatically)
python health-plugin/scripts/prune-claude-config.py
```

The script removes:
- **Orphaned projects**: Entries for directories that no longer exist
- **Cached data**: `cachedChangelog`, `cachedStatsigGates`, `cachedDynamicConfigs`

Your settings, MCP servers, and tips history are preserved.

## Quick Reference

### Plugin Registry Location
```
~/.claude/plugins/installed_plugins.json
```

### Settings File Locations
| Scope | Path |
|-------|------|
| User | `~/.claude/settings.json` |
| Project | `.claude/settings.json` |
| Local | `.claude/settings.local.json` |

### Common Issues

| Symptom | Likely Cause | Command |
|---------|--------------|---------|
| Plugin not working | Wrong projectPath in registry | `/health:plugins --fix` |
| Irrelevant plugins enabled | No relevance audit done | `/health:audit --fix` |
| Permission denied | Missing allow pattern | Check settings-configuration skill |
| Settings ignored | Invalid JSON | `/health:check` |
| Large ~/.claude.json | Orphaned projects/caches | `prune-claude-config.py` |

## Related

- [Claude Code Issue #14202](https://github.com/anthropics/claude-code/issues/14202) - Project-scoped plugin bug
- `configure-plugin` - Project infrastructure setup
- `hooks-plugin` - Hook configuration and automation
