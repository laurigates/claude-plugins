---
created: 2026-11-06
modified: 2026-11-14
reviewed: 2026-11-06
name: rust-installable-cli
description: "Installable Rust CLI: embedded default config, config layers, user dirs, clap input beside subcommands. Use when making a binary run outside its repo."
user-invocable: false
allowed-tools: Bash(cargo test *), Bash(cargo package *), Bash(grep *), Read, Write, Edit, Grep, Glob, AskUserQuestion, TodoWrite
---

# rust-installable-cli — Patterns for a Rust CLI That Runs Outside Its Repo

A CLI that only ever ran from its own checkout can read `configs/` by relative
path, write into the working tree and keep its cache beside the sources. Once it
is installed (`cargo install`, a release archive, a Homebrew formula) none of
that exists. This skill covers what replaces it: config embedded in the binary,
a layered config with a user file, user directories, a clap shape that accepts
an input file next to subcommands, and copying results out of a cache.

Code for every section is in [REFERENCE.md](REFERENCE.md). The snippets were
compiled and tested against clap 4.6 and toml 1.2.

## When to Use This Skill

| Use this skill when... | Use instead when... |
|------------------------|---------------------|
| The binary must work from any directory after install | Building and publishing release archives, installers or a formula: `rust-plugin:cargo-dist` |
| Moving default config out of the repo and into the binary | Shell completions for the installed binary: `configure-plugin:configure-completions` |
| Adding a user config file or a cache directory | Everyday Rust language and cargo work: `rust-plugin:rust-development` |
| A positional input and subcommands must share one `clap` parser | Starting a new crate from a template: `rust-plugin:cargo-generate` |

## Take project facts from the project, or ask

Nothing here assumes an application name, config file name or variable prefix.
Read them from the project, and ask with `AskUserQuestion` for what the files do
not settle:

| Fact | Where to look first |
|------|---------------------|
| Binary and app name | `Cargo.toml` (`[[bin]]`, `[package] name`) |
| Default config file | The repo's `configs/` or equivalent, and the code that opens it |
| Override variable names (`<APP>_CONFIG_DIR`, `<APP>_CACHE_DIR`) | Existing `env::var` calls, the README |
| Which tables replace whole entries | Config tables keyed by tool or plugin name |
| Supported OSes | CI matrix, release targets |

## 1. Embed the defaults, layer the rest

Compile the default config into the binary with `include_str!`, so the binary
needs no file beside it. Build the effective config from layers, lowest first:

1. built-in defaults (embedded)
2. the user's `config.toml` in the config directory ([section 3](#3-user-directories-without-a-dependency))
3. config files beside the input
4. the input file's own config
5. command-line overrides

Merge each layer into the result as a `toml::Table`, recursing into nested
tables. Tables keyed by tool or plugin name are the exception: a higher layer's
entry replaces the lower entry whole. A user who redefines `[tools.<name>]`
means "use this definition", and a field-by-field merge keeps defaults they
never wrote, such as extra `args`.

`include_str!` paths are relative to the source file. A path that leaves the
package directory works for `cargo install --git` and release builds, but
`cargo package` leaves the file out of the tarball and its verify build fails
with `couldn't read`, so the crate cannot be published. Either keep the path
inside the package, or keep a copy there and add a test that the copy equals the
repo file, so the two cannot drift.

## 2. Keep the library's loader hermetic

The library's `load()` takes the user layer as a parameter and never reads
`$HOME` or the process environment. Only `main` (or the CLI module) resolves the
config directory, reads `config.toml` and passes it in. Tests, recipes and CI
then get the same result on every machine, whatever the developer has in their
own config.

## 3. User directories without a dependency

Write the lookup as pure functions that take an injected environment lookup
(`&dyn Fn(&str) -> Option<OsString>`) and the OS name (`std::env::consts::OS`).
Tests pass a closure over a map, so they never set process environment
variables, which are shared across test threads.

| Directory | Order |
|-----------|-------|
| Config | `<APP>_CONFIG_DIR`, then `$XDG_CONFIG_HOME/<app>`, then `$HOME/.config/<app>` |
| Cache | `<APP>_CACHE_DIR`, then `$XDG_CACHE_HOME/<app>`, then `$HOME/Library/Caches/<app>` on macOS or `$HOME/.cache/<app>` elsewhere |

Ignore `XDG_*` values that are not absolute paths; the XDG Base Directory spec
says to treat them as unset. Config stays in `~/.config` on macOS too, where
users of command-line tools look for it. This covers Linux and macOS; Windows
needs `%APPDATA%` and `%LOCALAPPDATA%`, or the `directories` crate.

## 4. clap: a positional input next to subcommands

A CLI that takes `tool <video>` and also `tool run <config>` needs an optional
positional and an optional subcommand in one parser.

`args_conflicts_with_subcommands = true` looks like the fit, but it also
rejects **global** flags placed before a subcommand: `tool --tools x run c.toml`
fails with `ArgumentConflict`, while `tool run c.toml --tools x` parses. Use
this shape instead:

- `#[command(arg_required_else_help = true)]`, so a bare `tool` prints help
- `video: Option<PathBuf>` and `command: Option<Command>`
- after parsing, a manual check that returns
  `Cli::command().error(ErrorKind::ArgumentConflict, …)` when a video option or
  the video itself is set together with a subcommand

Test it with `Cli::command().debug_assert()` and a `try_parse_from` matrix:
video alone, video with its options, each subcommand, a global flag before and
after a subcommand, a video option with a subcommand (error), and no arguments
(`DisplayHelpOnMissingArgumentOrSubcommand`).

## 5. Copy results out of the cache

When outputs are produced in a cache and delivered to a user-chosen directory:

- **Copy, do not hard-link.** A hard link shares the file with the cache entry,
  so a user editing the output in place changes the cached result, and hard
  links fail across filesystems.
- **Write to a temporary name in the destination directory, then rename.** A
  rename within one directory is atomic, so an interrupted run never leaves a
  half-written file under the final name.
- **Refuse names that are not a single plain path component** (empty, `.`,
  `..`, anything with a separator, absolute paths, hidden names).
- **Leave unrelated files alone.** Write only the names this run produces;
  never clear the output directory.

## 6. Keep cache keys stable when a stage becomes optional

When a pipeline stage becomes optional and the cache key is a fingerprint over
a stage's dependencies, build the "on" variant's dependency list in the old
order, so fingerprints computed before the change still hit. Pin that order with
a test. If you also pin a golden fingerprint, compute it with a hash whose
output is specified (SHA-256, BLAKE3); `std`'s `DefaultHasher` algorithm is
unspecified and may change between Rust releases.

## Tests to add

| Pattern | Test |
|---------|------|
| Embedded defaults | The embedded copy parses, and equals the repo file when they are separate files |
| Layering | A tool entry in a higher layer replaces the whole entry; a plain table merges field by field |
| Hermetic loader | `load()` gives the same result with a different `HOME` |
| User dirs | Override variable wins, relative `XDG_*` is ignored, macOS cache path |
| clap | `debug_assert()` plus the `try_parse_from` matrix in [section 4](#4-clap-a-positional-input-next-to-subcommands) |
| Copy-out | Unsafe names rejected, unrelated files untouched |
| Cache keys | The "on" dependency order equals the pre-change order |

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Run only the CLI parse tests | `cargo test -q cli::` |
| Check the installed binary outside the repo | `cargo install --path . --root "$(mktemp -d)"`, then run it from another directory |
| Confirm the defaults ship in the package | `cargo package --list \| grep -F <defaults-file>` |
