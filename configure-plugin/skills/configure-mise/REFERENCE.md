# configure-mise — Reference

Detailed templates and mapping tables for [`/configure:mise`](SKILL.md). Loaded on demand; no size limit.

## Config file resolution

mise merges config from several files, most-specific wins. Project files override the global one; `*.local.toml` overrides its sibling.

| File | Scope | Commit? |
|------|-------|---------|
| `~/.config/mise/config.toml` | global (all projects) | dotfiles only |
| `mise.toml` *(preferred)* / `.mise.toml` / `.config/mise.toml` | project | **yes** |
| `mise.local.toml` / `.mise.local.toml` | project, machine-local | **no** — gitignore |
| `.tool-versions`, `.nvmrc`, `.python-version` | legacy (asdf/nvm/pyenv) | honored only with `legacy_version_file = true` |

`mise.lock` pins resolved versions+checksums for reproducible installs — commit it. Regenerate with `mise lock`.

## Backend cheat-sheet

```toml
[tools]
# core runtimes — multi-version as a list
python = ["3.12", "3.13"]
node   = "lts"            # or "latest", "22", "20.11.0"
go     = "1.23"
rust   = "latest"
bun    = "latest"

# Python CLIs via pipx backend (routed through uvx)
"pipx:ruff"       = "latest"
"pipx:pre-commit" = "latest"
"pipx:ansible"    = "latest"
# extra uvx args:
"pipx:mlx-lm"     = { version = "latest", uvx_args = "--prerelease allow" }

# standalone CLI binaries via aqua (checksums + provenance) — org/repo names
"aqua:BurntSushi/ripgrep"           = "latest"   # rg
"aqua:sharkdp/fd"                   = "latest"
"aqua:sharkdp/bat"                  = "latest"
"aqua:jqlang/jq"                    = "latest"
"aqua:mikefarah/yq"                 = "latest"
"aqua:cli/cli"                      = "latest"   # gh
"aqua:kubernetes/kubectl"           = "latest"
"aqua:helm/helm"                    = "latest"
"aqua:hashicorp/terraform"          = "latest"
"aqua:jesseduffield/lazygit"        = "latest"
"aqua:gitleaks/gitleaks"            = "latest"

# other backends when aqua lacks the tool
"npm:typescript-language-server" = "latest"
"go:golang.org/x/tools/gopls"    = "latest"
"cargo:tokei"                    = "latest"
"github:starship/starship"       = "latest"

# short names mise knows natively (core registry)
just     = "latest"
neovim   = "nightly"
chezmoi  = "latest"
uv       = "latest"          # register uv as managed so pipx: → uvx works
```

### Version pin granularity

| Spec | Allows | Use for |
|------|--------|---------|
| `"latest"` | any new release on upgrade | dev tooling where churn is fine |
| `"3"` | minor + patch within major | loose runtime pin |
| `"3.13"` | patch within minor | typical library runtime |
| `"3.13.2"` | exact | reproducibility-critical tools |
| `mise use --pin` | writes exact resolved version | freeze without hand-editing |

## `[env]` — environment & secrets

```toml
[env]
EDITOR = "nvim"
NODE_ENV = "development"

# prepend to PATH (project-local bin)
_.path = ["./bin", "./node_modules/.bin"]

# load secrets/vars from a gitignored file — NEVER inline secrets
_.file = ".env.local"

# load from multiple files (later wins)
# _.file = [".env", ".env.local"]

# source a script's exports
# _.source = "./scripts/env.sh"
```

`_.file` values are not committed; keep the referenced file in `.gitignore`. For the dotfiles global config this is how `~/.api_tokens` is loaded (`_.file = "~/.api_tokens"`).

## `[tasks]` — replacing Make/just

```toml
[tasks.test]
description = "Run the test suite"
run = "pytest -x -q"

[tasks.lint]
description = "Lint everything"
run = [
  "ruff check .",
  "ruff format --check .",
]

# aggregate task with dependencies (run after its deps)
[tasks.ci]
description = "Full local CI"
depends = ["lint", "test"]

# alias + multi-line shell
[tasks.check]
alias = "c"
description = "Quick checks"
run = """
#!/usr/bin/env bash
set -euo pipefail
echo "running checks…"
ruff check .
"""

# file-based tasks live in `mise-tasks/<name>` or `.mise/tasks/<name>`
# and are auto-discovered — no [tasks] entry needed.
```

Run with `mise run <name>` (or `mise run c`). List with `mise tasks`. `mise watch <name>` re-runs on file change. `depends` replaces Makefile prerequisites; `run` as a list runs steps sequentially.

### Makefile → `[tasks]` mapping

| Makefile | mise |
|----------|------|
| `target: dep1 dep2` | `[tasks.target]` + `depends = ["dep1","dep2"]` |
| recipe lines (tab-indented) | `run = "…"` or `run = ["…","…"]` |
| `.PHONY` | n/a — tasks aren't files |
| `$(VAR)` | `[env]` var or task-level `env = {…}` |
| `make target` | `mise run target` |

## `[settings]` — common knobs

```toml
[settings]
experimental = true          # enable newer backends/features
legacy_version_file = true   # keep honoring .tool-versions/.nvmrc during migration
pipx.uvx = true              # route pipx: backend through uvx (jdx/mise#7477)
# activate_aggressive = true # switch versions even mid-directory (global dotfiles use this)
# idiomatic_version_file_enable_tools = ["python"]  # opt-in legacy files per tool
```

Set `pipx.uvx = true` whenever any `pipx:` tool is present — mise only auto-detects uvx when `uv` is itself mise-managed, so register `uv = "latest"` under `[tools]` too.

## Migration worked examples

### asdf (`.tool-versions`)

```
# .tool-versions
python 3.13.2
nodejs 20.11.0
terraform 1.7.5
```
→
```toml
[tools]
python = "3.13.2"
node = "20.11.0"
"aqua:hashicorp/terraform" = "1.7.5"

[settings]
legacy_version_file = true   # until .tool-versions is removed
```
asdf plugin name `nodejs` → mise core `node`. Verify with `mise install && mise current`, then delete `.tool-versions`.

### Homebrew CLI tools → mise

Keep in Homebrew: GUI casks, services/daemons (postgresql, mosquitto), build deps (cmake, ninja), platform glue (mas), and bootstrap (mise itself, chezmoi, git). Move *standalone CLI binaries* to mise:

| `brew install …` | mise |
|------------------|------|
| `kubectl` | `"aqua:kubernetes/kubectl"` |
| `ripgrep` | `"aqua:BurntSushi/ripgrep"` |
| `jq` | `"aqua:jqlang/jq"` |
| `gh` | `"aqua:cli/cli"` |
| `terraform` | `"aqua:hashicorp/terraform"` |
| `python@3.13` | core `python = "3.13"` |

### nvm / pyenv

`.nvmrc` `20.11.0` → `node = "20.11.0"`. `.python-version` `3.13.2` (one per line) → `python = ["3.13.2", …]`.

## Verification commands

```bash
mise trust                 # required before mise uses a new/edited config
mise install               # materialize all tools
mise lock                  # write/refresh mise.lock (commit it)
mise doctor                # health check
mise current               # active versions per tool
mise ls --json             # installed tools (machine-readable, parallel-safe)
mise outdated              # what could upgrade
mise ls-remote <tool>      # available versions before pinning
```

## Gotchas

- **Trust**: mise refuses untrusted config files; `mise trust` (or `mise trust --all`) after writing.
- **`pipx:` resolution** depends on a mise-managed `uv` + `pipx.uvx = true`.
- **aqua names** are `org/repo` and must match the aqua-registry; otherwise fall back to `github:`/`cargo:`/`go:`.
- **Stale tool copies**: a global tool can reappear from another node version's `node_modules` or from `~/.default-npm-packages` re-seeding — see the global `mise-stale-tool-copies` rule.
- **One-off version**: `mise exec <tool>@<ver> -- <cmd>` scopes a version to a single command; `mise use` *changes the default* (global `dependency-management` rule).
- **node ≥26** prebuilt binaries need `libatomic.so.1` — absent on some minimal Linux/appliances; gate or pin.

## Sources

Distilled from the laurigates dotfiles mise setup (`private_dot_config/mise/config.toml.tmpl`, `docs/mise-migration-guide.md`, `docs/mise-quick-reference.md`, `docs/adrs/0002-unified-tool-version-management-mise.md`) and the global `mise-stale-tool-copies` / `dependency-management` rules.
