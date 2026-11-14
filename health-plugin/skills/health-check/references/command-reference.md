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
| Usage with a custom dormancy window | Step 2's `check-usage.sh` invocation with `--window-days 60 --verbose` appended |
| Fix everything (interactive) | `/health:check --fix` |
| Dry-run preview of fixes | `/health:check --fix --dry-run` |
| Detailed diagnostics | `/health:check --verbose` |
| Permissions coverage (1d) | Step 1a's `check-permissions-coverage.sh` invocation; add `--verbose` for per-tool `TOOL=` and `UNUSED_RULE=` lines |
| Check plugin registry exists | `find ~/.claude/plugins -name 'installed_plugins.json'` |
| Validate settings JSON | `find .claude -maxdepth 1 -name 'settings.json'` |
| Smoke-test install script | `CLAUDE_CODE_REMOTE=true bash scripts/install_pkgs.sh` |
| Validate pre-commit config | `pre-commit validate-config .pre-commit-config.yaml` |
| Marketplace enrollment (1e) | Step 1a's `check-marketplace-enrollment.sh` invocation; append `--repo <owner/name>` to look for another marketplace |
