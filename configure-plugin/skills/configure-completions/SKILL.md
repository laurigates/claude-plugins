---
name: configure-completions
description: "Shell completions for a released CLI: generator subcommand, Homebrew/archive/installer delivery, drift test. Use when a repo ships a CLI binary, to add or audit its completions."
args: "[--check-only] [--fix]"
argument-hint: "[--check-only] [--fix]"
allowed-tools: Glob, Grep, Read, Write, Edit, Bash(cargo *), Bash(go *), Bash(uv *), Bash(just *), Bash(git status *), Bash(git diff *), Bash(git add *), Bash(find *), Bash(test *), Bash(bash -n *), Bash(zsh -n *), Bash(fish -n *), AskUserQuestion, TodoWrite
created: 2026-10-30
modified: 2026-10-30
reviewed: 2026-10-30
---

# /configure:completions

Make every CLI a repo releases ship shell completions, through every channel a
user can install it from, with a test that keeps committed scripts current.

## When to Use This Skill

| Use this skill when... | Use another approach when... |
|------------------------|------------------------------|
| A repo releases a CLI binary and has no `completions` command | The Typer/Click `--install-completion` mechanics themselves are the problem — `python-plugin:typer-cli-completion` |
| Auditing that Homebrew, archives and installers all deliver completions | Setting up the release pipeline itself — `/configure:release-please`, `/configure:workflows` |
| Completions exist but nothing stops the committed scripts drifting | The repo ships a library, not a CLI — this standard is N/A |

## Context

- Rust bins: !`find . -maxdepth 3 -name Cargo.toml -not -path '*/target/*'`
- Go modules: !`find . -maxdepth 2 -name go.mod`
- Python projects: !`find . -maxdepth 2 -name pyproject.toml`
- cargo-dist config: !`find . -maxdepth 1 \( -name 'dist-workspace.toml' -o -name 'dist.toml' \)`
- GoReleaser config: !`find . -maxdepth 1 \( -name '.goreleaser.yml' -o -name '.goreleaser.yaml' \)`
- Committed completion scripts: !`find . -type d -name completions -not -path '*/.git/*' -not -path '*/target/*' -not -path '*/node_modules/*'`
- Project standards: !`find . -maxdepth 1 -name '.project-standards.yaml'`

## Parameters

| Parameter | Description |
|-----------|-------------|
| `--check-only` | Report the compliance table; write nothing |
| `--fix` | Apply every missing piece without prompting |

Default (no flag): report, then ask before applying fixes.

## The Standard

A released CLI is compliant when all three hold:

1. **Generator** — the binary prints its own completion script, generated from
   the CLI definition: `<bin> completions <shell>` (clap), the built-in
   `completion` command (cobra), or `--show-completion` (Typer). Never a
   hand-written script.
2. **Every install channel delivers them**:

   | Channel | Delivery |
   |---------|----------|
   | Homebrew formula/cask | `generate_completions_from_executable` runs the generator at install |
   | Release archives | pre-generated bash/zsh/fish scripts in a `completions/` directory |
   | Shell installer, `cargo install`, `go install`, `uv tool install`/`pipx`, source | documented `eval "$(<bin> completions zsh)"` lines (these installers cannot place completion files) |

3. **No drift** — committed scripts are compared with generator output by a
   test in the normal suite, and a recipe (`just completions`) regenerates them.
   Channels that run the generator at install or shell start cannot drift; only
   committed copies can.

## Execution

Execute this completions compliance workflow:

### Step 1: Decide applicability

Find the released binaries: `[[bin]]`/`[package.metadata.dist]` (Rust),
`package main` + a `.goreleaser.y*ml` `builds` entry (Go),
`[project.scripts]` (Python). No released binary → report `N/A` and stop.

### Step 2: Detect the framework and channels

- Framework: `clap` in Cargo.toml, `github.com/spf13/cobra` in go.mod,
  `typer`/`click` in pyproject.toml. Another framework → report it and check
  whether it has a generator before proposing anything.
- Channels: cargo-dist `installers` (shell, homebrew, powershell, npm),
  GoReleaser `homebrew_casks`/`brews`/`archives`, a tap repo, PyPI.

### Step 3: Check each requirement

Report one row per requirement, each with the evidence that decides it:

| Requirement | PASS evidence |
|-------------|---------------|
| Generator | `<bin> completions bash` (or the framework's form) exits 0 and prints a script |
| Homebrew | the published formula/cask contains `generate_completions_from_executable` — read the tap file, not the generator config |
| Archives | the archive listing contains `completions/` (e.g. `tar -tJf` on a local `dist build`) |
| Installer docs | README or usage doc shows the `eval`/`source` lines |
| Drift test | a test reads the committed scripts and compares them with generator output |
| Regenerate recipe | a justfile/Makefile target writes the scripts from the generator |

### Step 4: Apply fixes (`--fix` or confirmed)

Per framework, use the templates in [REFERENCE.md](REFERENCE.md):

- **Rust / clap**: add `clap_complete`, a `Completions { shell: Shell }`
  subcommand, committed scripts, the drift test; with cargo-dist, `include` the
  scripts and patch the generated formula (dist's formula installs only
  executables).
- **Go / cobra**: the default `completion` command already exists unless
  `CompletionOptions.DisableDefaultCmd` is set; wire GoReleaser's
  `generate_completions_from_executable` with `shell_parameter_format: cobra`.
- **Python / Typer or Click**: see `python-plugin:typer-cli-completion` for
  generating scripts from a non-shell parent; Homebrew uses
  `shell_parameter_format: :typer` or `:click`.

Then add the docs section and the regenerate recipe, regenerate, and
syntax-check the scripts (`bash -n`, `zsh -n`, `fish -n`).

### Step 5: Prove the drift test bites

Append a line to one committed script, run the test, confirm it fails with the
regenerate hint, restore the file. A drift test never seen failing is not
evidence.

### Step 6: Update standards tracking

```yaml
components:
  completions: "2025.1"
  completions_framework: "[clap|cobra|typer|click]"
  completions_channels: [homebrew, archives, docs]
```

### Step 7: Report

Print the compliance table, the files changed, and anything only a release can
verify (a patched formula is exercised by the next publish). Under
`--check-only`, prefix with "DRY RUN — no files modified".

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Audit only | `/configure:completions --check-only` |
| Apply all fixes | `/configure:completions --fix` |
| Generator smoke | `<bin> completions bash > /dev/null && echo ok` |
| Archive contents (cargo-dist) | `dist build --artifacts=local --target <triple>` then `tar -tJf target/distrib/*.tar.xz` |
| Syntax-check scripts | `bash -n completions/<bin>.bash && zsh -n completions/_<bin>` |

## See Also

- [REFERENCE.md](REFERENCE.md) — per-framework templates and the cargo-dist formula patch
- `python-plugin:typer-cli-completion` — Typer/Click generation from a non-shell parent
- `/configure:release-please` — the release pipeline these channels hang off
