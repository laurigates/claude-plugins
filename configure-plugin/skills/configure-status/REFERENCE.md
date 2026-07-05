# /configure:status Reference

## File-Presence Checks (script-less components)

For components without a detection script (`HAS_SCRIPT=false` in the lister
output), assess presence and validity from these files:

| Component | Files Checked |
|-----------|---------------|
| Pre-commit | `.pre-commit-config.yaml` |
| Release-please | `release-please-config.json`, `.release-please-manifest.json`, `.github/workflows/release-please.yml` |
| Dockerfile | `Dockerfile`, `Dockerfile.*` |
| Skaffold | `skaffold.yaml` |
| CI Workflows | `.github/workflows/*.yml` |
| Reusable Workflows | `.github/workflows/*` calling `reusable-*.yml` |
| ArgoCD Automerge | `.github/workflows/argocd-automerge.yml` |
| GitHub Pages | `.github/workflows/docs.yml`, `.github/workflows/*pages*.yml` |
| Claude Plugins | `.claude/settings.json` (`enabledPlugins`, `extraKnownMarketplaces`) |
| Gitattributes | `.gitattributes` |
| Gitignore | `.gitignore` (managed Claude Code block) |
| Worktreeinclude | `.worktreeinclude` |
| Container | `Dockerfile`, `.github/workflows/*container*`, `.devcontainer/` |
| Helm | `helm/*/Chart.yaml` |
| Documentation | `tsdoc.json`, `typedoc.json`, `mkdocs.yml`, `docs/conf.py`, `pyproject.toml [tool.ruff.lint.pydocstyle]` |
| README | `README.md` |
| Surface | `surf.toml` |
| Cache Busting | `next.config.*`, `vite.config.*`, `vercel.json`, `_headers` |
| Tests | `vitest.config.*`, `jest.config.*`, `pytest.ini`, `pyproject.toml [tool.pytest]`, `.cargo/config.toml` |
| Coverage | `vitest.config.* [coverage]`, `pyproject.toml [tool.coverage]`, `.coveragerc` |
| API Tests | `**/pacts/`, `**/*.pact.json`, OpenAPI validation configs |
| Integration Tests | `docker-compose.test.yml`, `tests/integration/` |
| Load Tests | `k6/`, `artillery.yml`, `locustfile.py` |
| Memory Profiling | `pyproject.toml [tool.pytest]` with `pytest-memray` |
| Linting | `biome.json`, `pyproject.toml [tool.ruff]`, `clippy.toml` |
| Dead Code | `knip.json`, `knip.ts`, `pyproject.toml [tool.vulture]` |
| Feature Flags | OpenFeature SDK in deps, `flags.goff.yaml` |
| Package Management | `uv.lock`, `bun.lock`, `bun.lockb` |
| Mise | `mise.toml`, `.tool-versions` |
| Editor | `.editorconfig`, `.vscode/settings.json`, `.vscode/extensions.json` |
| MCP | `.mcp.json` |
| Makefile | `Makefile` |
| Justfile | `justfile`, `Justfile` |
| Web Session | `scripts/install_pkgs.sh`, `.claude/settings.json` SessionStart hook |
| Sentry | Sentry SDK in deps, `sentry.*.config.ts`, `instrumentation.ts`, env-var DSN |

## Verbose Details (`--verbose`)

- Show specific version numbers for each hook/tool
- List individual compliance checks performed
- Show detected deviations from `.project-standards.yaml`
- Display file modification timestamps
- Show cache-busting configuration details (framework, CDN, hash patterns)
