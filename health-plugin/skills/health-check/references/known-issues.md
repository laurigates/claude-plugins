# health-check: known issues and fix paths

## Known Issues

| Issue | Symptom | Fix path |
|-------|---------|----------|
| [#14202](https://github.com/anthropics/claude-code/issues/14202) | Plugin shows "installed" but not active | `/health:check --scope=registry --fix` |
| Stale `enabledPlugins` key in settings.json | Plugin appears enabled but no registry/marketplace entry | `/health:check --scope=registry --fix` |
| Orphaned `projectPath` | Plugin installed for deleted project | `/health:check --scope=registry --fix` |
| Invalid settings JSON | Settings file won't load | `/health:check` |
| Missing marketplace enrollment | laurigates/claude-plugins skills unavailable in web sessions | `/configure:claude-plugins --fix` |
