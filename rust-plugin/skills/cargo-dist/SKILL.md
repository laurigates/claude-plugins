---
created: 2026-11-02
modified: 2026-11-02
reviewed: 2026-11-02
name: cargo-dist
description: "cargo-dist (dist) release binaries for a Rust CLI. Use when setting up dist-workspace.toml, pairing dist with release-please, or publishing a Homebrew formula."
user-invocable: false
allowed-tools: Bash, Read, Write, Edit, Grep, Glob, AskUserQuestion, TodoWrite
---

# cargo-dist — Release Binaries for a Rust CLI

[dist](https://opensource.axo.dev/cargo-dist/) (formerly cargo-dist) builds
per-target archives, installers and a Homebrew formula, and generates the
`release.yml` GitHub workflow that does it on every tag. The [Setup](#setup) steps are
the non-interactive setup, written for dist 0.32; check the installed version
with `dist --version` and the
[config reference](https://opensource.axo.dev/cargo-dist/book/reference/config.html)
when it differs.

## When to Use This Skill

| Use this skill when... | Use instead when... |
|------------------------|---------------------|
| Shipping prebuilt binaries of a Rust CLI on GitHub Releases | Versioning and changelogs only: `configure-plugin:configure-release-please` |
| Pairing dist with release-please tags | Tap layout, formula review, homebrew-core eligibility: the proposed `homebrew-plugin` |
| Adding a Homebrew formula or shell/PowerShell installer | Container images: `configure-plugin:configure-container` |
| Pinning the actions in dist's generated `release.yml` | Starting the crate itself: `rust-plugin:cargo-generate` |

## Take project facts from the project, or ask

Nothing in this skill assumes an owner, tap, target list or secret layout.
Read them before writing config, and ask with `AskUserQuestion` for whatever
the files do not settle:

| Fact | Where to look first |
|------|---------------------|
| Binary crates and their names | `Cargo.toml` (`[[bin]]`, `[workspace] members`) |
| Release tooling | `release-please-config.json`, `.github/workflows/*release*` |
| Homebrew tap (`<owner>/homebrew-tap`) | An existing `dist-workspace.toml`, the README's install section |
| Targets | Existing CI matrix, the README's supported platforms |
| How secrets reach repo settings | Ask — it is the user's choice |

When the user gives an answer that will hold across their repos (the tap, the
target set, how secrets are provisioned), offer to save it as a user-level rule
so later setups read it instead of asking again.

## Context

- Manifests: !`find . -maxdepth 1 \( -name 'Cargo.toml' -o -name 'dist-workspace.toml' -o -name 'release-please-config.json' \)`
- Release workflows: !`find . -maxdepth 3 -path './.github/workflows/release*.yml'`

## Setup

### 1. Write `dist-workspace.toml` by hand, then generate

`dist init` is interactive. Write the file directly and let `dist generate`
produce `release.yml`:

```toml
[workspace]
members = ["cargo:."]

[dist]
cargo-dist-version = "0.32.0"
ci = "github"
installers = ["shell", "homebrew"]
tap = "<owner>/homebrew-tap"
targets = ["aarch64-apple-darwin", "x86_64-apple-darwin", "x86_64-unknown-linux-gnu"]
install-path = "CARGO_HOME"
create-release = false          # release-please owns the GitHub Release
publish-jobs = ["./publish-homebrew"]
```

```bash
dist generate          # writes .github/workflows/release.yml
```

To run a pinned dist without installing it, use mise if it is available,
otherwise dist's own installer:

```bash
mise exec github:axodotdev/cargo-dist@<version> -- dist generate
```

### 2. Add the `dist` profile

`dist build` fails with "profile `dist` is not defined" until the workspace
`Cargo.toml` has it:

```toml
[profile.dist]
inherits = "release"
lto = "thin"
```

### 3. Choose which crates ship

| Situation | Setting on the crate |
|-----------|----------------------|
| Workspace has `publish = false` | `[package.metadata.dist] dist = true` on each binary crate that ships — dist skips unpublishable crates otherwise |
| Several binary crates, only some ship | `[package.metadata.dist] dist = false` on the rest — each shipped binary crate becomes its own release and its own formula |
| Install name differs from the package name | `[package.metadata.dist] formula = "<binary>"` |

The formula and the archives are named after the **package**, not the binary.
`formula` changes the install name only; archives keep the package name
(`<package>-<target>.tar.xz`).

Set `homepage` in package metadata. Without it, `dist generate` warns "The
Homebrew publish job is enabled but no homepage was specified". In a workspace,
put `homepage` in `[workspace.package]` and `homepage.workspace = true` in the
crate.

## Working with release-please

- `create-release = false` makes dist upload to the release that already exists
  for the tag, instead of creating its own. release-please creates that
  release.
- release-please must run with a **GitHub App token** (or a PAT), not
  `GITHUB_TOKEN`. A tag pushed with `GITHUB_TOKEN` does not trigger other
  workflows, so `release.yml` never starts. The token setup is in
  `configure-plugin:configure-release-please`.
- On pull requests, `release.yml` runs only `plan` (`pr-run-mode = "plan"`, the
  default), so a green PR check does not prove the build works. Verify locally
  ([Verify before tagging](#verify-before-tagging)).

## Pinning the generated workflow's actions

Hand edits to `release.yml` are overwritten by the next `dist generate`, and
`dist generate --check` fails on them. Pin through config instead:

```toml
[dist.github-action-commits]
"actions/checkout" = "<sha-or-tag>"
"actions/upload-artifact" = "<sha-or-tag>"
"actions/download-artifact" = "<sha-or-tag>"
```

The table accepts tags (`"v7.0.1"`) as well as commit SHAs, so follow the repo's
existing pinning convention.

## Custom publish job

Use a custom job when the built-in `homebrew` publish job does not fit — for
example when the tap token is a static repository secret the built-in job
cannot read under that name. List it as `publish-jobs = ["./publish-homebrew"]`
and write `.github/workflows/publish-homebrew.yml` as a reusable workflow
(`on: workflow_call` with a required string input `plan`).

`dist generate` calls it from `release.yml` like this (abbreviated):

```yaml
custom-publish-homebrew:
  needs: [plan, ...]
  if: ${{ !fromJson(needs.plan.outputs.val).announcement_is_prerelease || fromJson(needs.plan.outputs.val).publish_prereleases }}
  uses: ./.github/workflows/publish-homebrew.yml
  with:
    plan: ${{ needs.plan.outputs.val }}
  secrets: inherit
```

The prerelease guard stays on the calling job, so the reusable workflow does
not repeat it. With `homebrew` in `installers` but not in `publish-jobs`,
`dist generate` warns "A Homebrew tap was specified but the Homebrew publish
job is disabled". That warning is expected: the formula is still built as a
release artifact, and the custom job publishes it.

## Verify before tagging

| Check | Command |
|-------|---------|
| Config parses, release plan is what you expect | `dist plan` |
| Committed `release.yml` matches config | `dist generate --check` |
| One target builds | `dist build --artifacts=local --target <triple>` |
| Generated Homebrew formula | `dist build --artifacts=global` (look under `target/distrib/`) |

After the local build, extract the archive from `target/distrib/` and run the
binary with `--version`.

## Limits

- `[dist.dependencies.homebrew]` entries default to `stage = "build"`: they are
  installed on the build machine and do not become `depends_on` in the formula.
  The config reference documents `stage = ["build", "run"]` for runtime
  dependencies; confirm the generated formula with
  `dist build --artifacts=global` before relying on it.
- PR runs do only `plan` ([Working with release-please](#working-with-release-please)).

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Plan as JSON | `dist plan --output-format=json` |
| CI drift check | `dist generate --check` |
| Single-target smoke build | `dist build --artifacts=local --target <triple>` |
| Pinned dist without install | `mise exec github:axodotdev/cargo-dist@<version> -- dist plan` |
