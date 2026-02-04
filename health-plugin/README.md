# health-plugin

Diagnose and fix Claude Code configuration issues including plugin registry, settings, hooks, and MCP servers.

## Installation

```bash
/plugin install health-plugin@laurigates-plugins
```

## Commands

| Command | Description |
|---------|-------------|
| `/health:check` | Comprehensive diagnostic scan of Claude Code environment |
| `/health:plugins` | Diagnose and fix plugin registry issues (addresses [#14202](https://github.com/anthropics/claude-code/issues/14202)) |

## Skills

| Skill | Description |
|-------|-------------|
| `plugin-registry` | Understanding Claude Code's plugin registry, scopes, and troubleshooting |
| `settings-configuration` | Settings file hierarchy, permission wildcards, and patterns |

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

### Permission Debugging

When tools are blocked unexpectedly, use the settings-configuration skill to understand:
- Settings file hierarchy (user → project → local)
- Permission wildcard patterns
- Shell operator protections

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
| Permission denied | Missing allow pattern | Check settings-configuration skill |
| Settings ignored | Invalid JSON | `/health:check` |

## Related

- [Claude Code Issue #14202](https://github.com/anthropics/claude-code/issues/14202) - Project-scoped plugin bug
- `configure-plugin` - Project infrastructure setup
- `hooks-plugin` - Hook configuration and automation
