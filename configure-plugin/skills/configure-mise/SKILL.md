---
created: 2026-06-24
modified: 2026-06-24
reviewed: 2026-06-24
description: "mise runtime/tool version manager - mise.toml, backends (pipx/aqua/npm/cargo/go), tasks, env, lockfile. Use when setting up, pinning runtimes/CLI tools, or migrating from asdf/nvm/pyenv/brew/Make."
allowed-tools: Glob, Grep, Read, Write, Edit, Bash, AskUserQuestion, TodoWrite, WebSearch, WebFetch
args: "[--check-only] [--fix] [--global] [--migrate <asdf|nvm|pyenv|brew|makefile>]"
argument-hint: "[--check-only] [--fix] [--global] [--migrate <source>]"
name: configure-mise
---

# /configure:mise

Set up and audit [mise](https://mise.jdx.dev/) as the unified manager for language runtimes, CLI tools, environment variables, and project tasks. mise replaces asdf/nvm/pyenv (runtimes), `cargo install`/`brew install` (CLI binaries), and Make/just (tasks) behind one `mise.toml`.

## When to Use This Skill

| Use this skill when... | Use another approach when... |
|------------------------|------------------------------|
| Setting up `mise.toml` to pin a project's runtimes and CLI tools | Installing one tool ad-hoc — run `mise use <tool>@<ver>` directly |
| Picking the right backend for a tool (core / `pipx:` / `aqua:` / `npm:` / `cargo:` / `go:`) | The project only needs Python/JS *libraries* — use `/configure:package-management` (uv/bun) |
| Migrating from `.tool-versions`/asdf, `.nvmrc`, `.python-version`, Homebrew, or a Makefile | Defining build/test recipes only, no version management — use `/configure:justfile` or `/configure:makefile` |
| Adding `[tasks]`, `[env]`, secret loading, or a `mise.lock` for reproducible installs | Running a specific runtime version once — `mise exec <tool>@<ver> -- <cmd>` (see global rule `mise-stale-tool-copies` / `dependency-management`) |
| Auditing an existing mise setup for pinning, lockfile, trust, and backend correctness | Configuring CI runtime install — that consumes the `mise.toml` this skill produces (`jdx/mise-action`) |

## Context

- Project root: !`pwd`
- mise config (project): !`find . -maxdepth 2 \( -name 'mise.toml' -o -name '.mise.toml' -o -path './.config/mise.toml' -o -name 'mise.local.toml' \)`
- Lockfile: !`find . -maxdepth 1 -name 'mise.lock'`
- Legacy version files: !`find . -maxdepth 2 \( -name '.tool-versions' -o -name '.nvmrc' -o -name '.python-version' -o -name '.ruby-version' -o -name '.go-version' \)`
- Things mise can absorb: !`find . -maxdepth 1 \( -name 'Makefile' -o -name 'justfile' -o -name 'Brewfile' \)`

## Parameters

Parse from command arguments:

- `--check-only`: Audit and report; make no changes (CI/review mode).
- `--fix`: Apply the recommended config without prompting for each step.
- `--global`: Target the **global** config (`~/.config/mise/config.toml`) instead of a project `mise.toml`.
- `--migrate <source>`: Convert an existing setup into `mise.toml`. Sources: `asdf` (`.tool-versions`), `nvm` (`.nvmrc`), `pyenv` (`.python-version`), `brew` (Brewfile CLI tools), `makefile` (targets → `[tasks]`).

## Backend Selection (the core decision)

mise installs every tool through a *backend*. Picking the right one mirrors the user's tool-install priority (`dependency-management` rule): **mise first, with the most secure/fastest backend**.

| Tool kind | Backend | Syntax | Why |
|-----------|---------|--------|-----|
| Language runtime | core | `python = ["3.12","3.13"]`, `node = "lts"`, `go = "1.23"`, `rust = "latest"` | Native version switching, the reason mise exists |
| Python CLI tool | `pipx:` | `"pipx:ruff" = "latest"` | Routed through `uvx` (fast); set `pipx.uvx = true` |
| Standalone CLI binary | `aqua:` | `"aqua:BurntSushi/ripgrep" = "latest"` | Checksums + SLSA provenance + Cosign — the secure default |
| Node global | `npm:` | `"npm:typescript-language-server" = "latest"` | When no aqua entry exists |
| Rust tool (no aqua) | `cargo:` | `"cargo:tokei" = "latest"` | Builds from source; prefer aqua if available |
| Go tool (no aqua) | `go:` | `"go:golang.org/x/tools/gopls" = "latest"` | Installs via `go install` |
| GitHub release (no aqua) | `github:` | `"github:starship/starship" = "latest"` | Direct release-asset fetch |

Rule of thumb: **runtime → core; Python CLI → `pipx:`; everything else → `aqua:` first**, falling back to `npm:`/`cargo:`/`go:`/`github:` only when the aqua registry lacks the tool. Verify aqua availability at <https://github.com/aquaproj/aqua-registry>.

## Execution

### Step 1: Detect current state

From Context, classify the repo:

- **No mise, has legacy version files** (`.tool-versions`, `.nvmrc`, `.python-version`) → migration candidate.
- **No mise, has Makefile/Brewfile** → task/tool migration candidate.
- **Has `mise.toml`** → audit mode (Step 5).
- **Greenfield** → fresh `mise.toml`.

Detect which runtimes the project already implies: `pyproject.toml`/`.python-version` → Python; `package.json`/`.nvmrc` → Node; `go.mod` → Go; `Cargo.toml` → Rust.

### Step 2: Choose config target and naming

| Target | File | Committed? |
|--------|------|-----------|
| Project (default) | `mise.toml` at repo root | yes — pins the team to the same versions |
| Project, local overrides | `mise.local.toml` | no — add to `.gitignore` |
| Global (`--global`) | `~/.config/mise/config.toml` | n/a (dotfiles) |

Prefer the modern `mise.toml` name over legacy `.mise.toml`. Use `mise.local.toml` for machine-specific or secret-bearing overrides and ensure it is gitignored.

### Step 3: Build the `[tools]` block

Pin runtimes the project needs, then add CLI tools by backend (table above). Pin **as loosely as safe**: `python = "3.13"` (allow patch upgrades) for libraries; exact pins (`opentofu = "1.11.2"`) for tools where reproducibility matters. Detect latest stable versions with WebSearch/`mise ls-remote <tool>` before writing.

Minimal example:

```toml
[tools]
python = "3.13"
node = "lts"
"pipx:ruff" = "latest"
"pipx:pre-commit" = "latest"
"aqua:jqlang/jq" = "latest"
"aqua:cli/cli" = "latest"   # gh
```

### Step 4: Add `[env]`, `[tasks]`, `[settings]` as needed

- **`[env]`** — project env vars and PATH; load secrets from a gitignored file with `_.file = ".env.local"` (never inline secrets). See REFERENCE.md.
- **`[tasks]`** — migrate Makefile/just recipes here so `mise run <task>` replaces `make <target>`. Supports `depends`, `alias`, multi-line `run`. See REFERENCE.md for the full grammar.
- **`[settings]`** — set `pipx.uvx = true` whenever any `pipx:` tool is present (works around `jdx/mise#7477`); `experimental = true` for newer backends; `legacy_version_file = true` to keep honoring `.tool-versions`/`.nvmrc` during migration.

### Step 5: Audit (always; the whole job when `--check-only`)

Report a compliance table:

```
mise Configuration Report
=========================
Config file            mise.toml                 [PRESENT | MISSING]
Runtimes pinned        python, node              [PINNED | UNPINNED]
CLI backends           aqua / pipx               [SECURE | cargo-from-source | mixed]
pipx.uvx setting       true                      [SET | MISSING (pipx tools present)]
Lockfile               mise.lock                 [COMMITTED | MISSING]
Local overrides        mise.local.toml           [GITIGNORED | TRACKED ⚠ | n/a]
Trust                  trusted                    [TRUSTED | UNTRUSTED]
Legacy files remaining .tool-versions            [MIGRATED | STILL PRESENT]

Overall: [N issues]
```

Checks: every runtime pinned; CLI tools prefer `aqua:` over `cargo:`/source builds; `pipx.uvx = true` present if any `pipx:` tool; `mise.lock` committed; `mise.local.toml` gitignored if present; config trusted (`mise trust`). If `--check-only`, stop here.

### Step 6: Apply (with `--fix` or on confirmation)

1. Write/patch the target config (Step 2 file).
2. `mise trust` the config (required before mise will use a new/edited file).
3. `mise install` to materialize tools.
4. `mise lock` to generate/refresh `mise.lock`, then track it (`git add mise.lock`).
5. If `mise.local.toml` exists, ensure `.gitignore` covers it.
6. `mise doctor` to verify the setup is healthy.

### Step 7: Migrations (`--migrate <source>`)

| Source | Action |
|--------|--------|
| `asdf` | Read `.tool-versions`, map each line to a `[tools]` entry, keep `legacy_version_file = true`, then remove `.tool-versions` once verified. asdf plugin names usually match mise core/aqua names. |
| `nvm` | `.nvmrc` → `node = "<ver>"`. |
| `pyenv` | `.python-version` → `python = "<ver>"` (a list if multiple). |
| `brew` | Move CLI tools (not casks/services/build-deps) from Brewfile to `aqua:`/core backends; leave GUI apps, fonts, daemons, and compilers in Homebrew. |
| `makefile` | Convert each target to a `[tasks.<name>]` with `run`; map prerequisites to `depends`. See REFERENCE.md task grammar. |

Always verify with `mise install && mise doctor` before deleting the source file. See [REFERENCE.md](REFERENCE.md) for per-source mapping tables and worked examples.

### Step 8: CI integration (mention, don't duplicate)

A committed `mise.toml` + `mise.lock` is consumed in CI by `jdx/mise-action` (`mise install` then `mise run <task>`), giving local↔CI parity (the `local-ci-parity` rule). Point the user to `/configure:ci-workflows` rather than writing the workflow here.

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Audit only | `/configure:mise --check-only` |
| Auto-configure | `/configure:mise --fix` |
| List installed tools (JSON) | `mise ls --json` |
| Show active versions | `mise current` |
| Available versions of a tool | `mise ls-remote <tool>` |
| Show outdated | `mise outdated` |
| Diagnose | `mise doctor` |
| Generate lockfile | `mise lock` |

## Flags

| Flag | Description |
|------|-------------|
| `--check-only` | Report status without modifying files |
| `--fix` | Apply the recommended config without per-step prompts |
| `--global` | Target `~/.config/mise/config.toml` instead of project `mise.toml` |
| `--migrate <source>` | Convert `asdf`/`nvm`/`pyenv`/`brew`/`makefile` into `mise.toml` |

## Examples

```bash
# Audit an existing setup
/configure:mise --check-only

# Set up mise.toml for the current project
/configure:mise

# Auto-configure, no prompts
/configure:mise --fix

# Migrate an asdf project
/configure:mise --migrate asdf

# Convert Makefile targets into mise tasks
/configure:mise --migrate makefile
```

## Error Handling

- **mise not installed**: Offer the install one-liner (`curl https://mise.run | sh`) or note it is itself a Homebrew bootstrap tool; do not block the audit.
- **Untrusted config**: mise refuses to load an untrusted file — run `mise trust` after writing.
- **`pipx:` tool fails to resolve**: ensure `uv` is a mise-managed tool and `pipx.uvx = true` is set (`jdx/mise#7477`).
- **aqua package not found**: the `org/repo` name must match an aqua-registry entry; fall back to `github:`/`cargo:`/`go:` or core.
- **Tool "keeps coming back" after removal**: stale per-node-version copies + `~/.default-npm-packages` re-seeding — see the global `mise-stale-tool-copies` rule.
- **node ≥26 on minimal Linux**: prebuilt binaries link `libatomic.so.1`; gate `node` to platforms that have it (chezmoi-style `os` guard) or pin an older line.

## See Also

- `/configure:package-management` — uv/bun for Python/JS **libraries** (mise installs the runtimes; uv/bun manage deps)
- `/configure:justfile`, `/configure:makefile` — task runners mise's `[tasks]` can replace
- `/configure:ci-workflows` — CI that consumes `mise.toml` via `jdx/mise-action`
- Global rules: `dependency-management` (tool-install priority, `mise exec` vs `mise use`), `mise-stale-tool-copies` (per-version cleanup)
- [REFERENCE.md](REFERENCE.md) — full `[tasks]`/`[env]`/`[settings]` grammar, backend cheat-sheet, migration mapping tables
- **mise docs**: <https://mise.jdx.dev/> · **aqua registry**: <https://github.com/aquaproj/aqua-registry>
