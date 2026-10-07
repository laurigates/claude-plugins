# health-check: command reference

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Full scan | `/health:check` |
| Registry only | `/health:check --scope=registry` |
| Stack relevance only | `/health:check --scope=stack` |
| Agentic audit only | `/health:check --scope=agentic` |
| Runtime state audit (~/.claude.json) | `/health:check --scope=runtime` |
| Usage telemetry (never-fired/dormant skills) | `/health:check --scope=usage` |
| Usage with a custom dormancy window | `bash check-usage.sh --window-days 60 --verbose` |
| Fix everything (interactive) | `/health:check --fix` |
| Dry-run preview of fixes | `/health:check --fix --dry-run` |
| Detailed diagnostics | `/health:check --verbose` |
| Check plugin registry exists | `find ~/.claude/plugins -name 'installed_plugins.json'` |
| Validate settings JSON | `find .claude -maxdepth 1 -name 'settings.json'` |
| Smoke-test install script | `CLAUDE_CODE_REMOTE=true bash scripts/install_pkgs.sh` |
| Validate pre-commit config | `pre-commit validate-config .pre-commit-config.yaml` |
| Check marketplace enrollment | `find .claude -maxdepth 1 -name 'settings.json'` then grep for `extraKnownMarketplaces` |
