# Health Audit Reference

## Tech Stack Detection Mapping

| Indicator | Technology | Related Plugins |
|-----------|------------|-----------------|
| `package.json` + `tsconfig.json` | TypeScript | typescript-plugin |
| `package.json` (no tsconfig) | JavaScript | typescript-plugin (JS support) |
| `bun.lockb` or bun in package.json | Bun runtime | typescript-plugin |
| `Cargo.toml` | Rust | rust-plugin |
| `pyproject.toml`, `requirements.txt`, `setup.py` | Python | python-plugin |
| `go.mod` | Go | (no plugin yet) |
| `Dockerfile`, `docker-compose.yml` | Docker/Containers | container-plugin |
| `.github/workflows/*.yml` | GitHub Actions | github-actions-plugin |
| `*.tf` files | Terraform | terraform-plugin |
| `k8s/`, `kubernetes/` with manifests | Kubernetes | kubernetes-plugin |
| `bevy` in Cargo.toml | Bevy game engine | bevy-plugin |
| `.claude-plugin/` directory | Claude plugin development | (this repo) |
| `docs/` with markdown | Documentation | documentation-plugin |
| `langchain` in dependencies | LangChain | langchain-plugin |
| OpenAPI/Swagger specs | API development | api-plugin |
| `biome.json`, `.eslintrc*` | Code quality | code-quality-plugin |
| `vitest.config.*`, `jest.config.*` | Testing | testing-plugin |
| Home Assistant configs | Home Assistant | home-assistant-plugin |

## Plugin Relevance Mapping

| Plugin | Relevant When |
|--------|--------------|
| typescript-plugin | package.json exists |
| python-plugin | Python project indicators exist |
| rust-plugin | Cargo.toml exists |
| container-plugin | Dockerfile or compose file exists |
| kubernetes-plugin | K8s manifests exist |
| github-actions-plugin | .github/workflows/ exists |
| terraform-plugin | *.tf files exist |
| git-plugin | Always relevant (all repos use git) |
| tools-plugin | Always relevant (common CLI tools) |
| configure-plugin | Always relevant (setup automation) |
| testing-plugin | Test files/configs exist |
| code-quality-plugin | Linter configs exist |
| bevy-plugin | Bevy in Cargo.toml dependencies |
| langchain-plugin | LangChain in dependencies |
| api-plugin | OpenAPI specs exist |
| documentation-plugin | docs/ directory with markdown |
| blueprint-plugin | docs/blueprint/ or planning documents |
| agents-plugin | Agent development context |
| project-plugin | Project management needs |

## Report Template

```
Plugin Audit Report
===================
Project: <current-directory>
Date: <timestamp>

Detected Technology Stack
-------------------------
- TypeScript/JavaScript (package.json, tsconfig.json)
- Docker (Dockerfile, docker-compose.yml)
- GitHub Actions (.github/workflows/)

Currently Enabled Plugins (N)
-----------------------------
+ typescript-plugin     - RELEVANT (TypeScript project)
+ git-plugin            - RELEVANT (all repos)
x kubernetes-plugin     - NOT RELEVANT (no K8s manifests found)
x terraform-plugin      - NOT RELEVANT (no .tf files found)
x python-plugin         - NOT RELEVANT (no Python indicators)

Suggested Plugins to Add (N)
----------------------------
+ container-plugin      - Docker files detected
+ github-actions-plugin - Workflow files detected
+ testing-plugin        - Test configuration detected

Suggested Plugins to Remove (N)
-------------------------------
- kubernetes-plugin     - No K8s usage detected
- terraform-plugin      - No Terraform usage detected
- python-plugin         - No Python usage detected

Summary
-------
Enabled: N plugins
Relevant: N plugins
Irrelevant: N plugins (consider removing)
Missing: N plugins (consider adding)

Run `/health:audit --fix` to apply these recommendations.
```
