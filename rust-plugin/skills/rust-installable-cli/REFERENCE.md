# rust-installable-cli — Reference Code

Code for each section of [SKILL.md](SKILL.md). Every block was compiled and its
tests run against clap 4.6 and toml 1.2. Names (`tools`, `plugins`, `ffmpeg`,
`--start`, `run`) are placeholders for the project's own.

## Embedded defaults and the drift test

Keep a copy of the defaults inside the package when the crate is published,
and pin it to the repo file:

```rust
/// Built-in layer. `include_str!` paths are relative to this source file.
pub const DEFAULTS: &str = include_str!("defaults.toml");

pub fn builtin() -> toml::Table {
    DEFAULTS.parse().expect("embedded defaults parse")
}

#[cfg(test)]
mod embed_tests {
    #[test]
    fn embedded_defaults_match_repo_file() {
        let repo = std::fs::read_to_string(concat!(
            env!("CARGO_MANIFEST_DIR"),
            "/../configs/defaults.toml"
        ))
        .expect("repo defaults file");
        assert_eq!(super::DEFAULTS, repo, "copy drifted from the repo file");
    }
}
```

When the crate is never published, `include_str!` can point at the repo file
directly; the drift test is then unnecessary, and `builtin()` parsing in a test
is the check that remains.

## Deep merge with whole-entry tables

```rust
use toml::{Table, Value};

/// Tables whose entries a higher layer replaces whole instead of merging.
const REPLACE_ENTRIES: &[&str] = &["tools", "plugins"];

/// Deep-merge `over` into `base`; scalars and arrays from `over` win.
pub fn merge(base: &mut Table, over: Table) {
    merge_at(base, over, false);
}

fn merge_at(base: &mut Table, over: Table, replace_entries: bool) {
    for (key, value) in over {
        match (base.get_mut(&key), value) {
            (Some(Value::Table(b)), Value::Table(o)) if !replace_entries => {
                let child_replaces = REPLACE_ENTRIES.contains(&key.as_str());
                merge_at(b, o, child_replaces);
            }
            (_, value) => {
                base.insert(key, value);
            }
        }
    }
}
```

`REPLACE_ENTRIES` matches a key at any depth. If the same name can appear
nested with a different meaning, match on the full key path instead.

## Hermetic loader

The library takes every layer as data. It never resolves a directory or reads
an environment variable:

```rust
/// Hermetic: never reads $HOME. The caller passes the user layer.
pub fn load(user: Option<Table>, layers: Vec<Table>, overrides: Table) -> Table {
    let mut cfg = builtin();
    for layer in user.into_iter().chain(layers).chain(std::iter::once(overrides)) {
        merge(&mut cfg, layer);
    }
    cfg
}
```

`layers` holds the files beside the input, then the input file's own config,
in that order. In the binary, resolve the user file with
[`config_dir`](#user-directories) and read it if it exists; a missing user file
is `None`, not an error.

Test for both rules:

```rust
#[test]
fn tools_entries_replace_whole() {
    let user: Table = "[tools.ffmpeg]\nbin = \"/opt/ffmpeg\"\n[output]\nformat = \"mkv\"\n"
        .parse()
        .unwrap();
    let cfg = load(Some(user), vec![], Table::new());
    let ff = cfg["tools"]["ffmpeg"].as_table().unwrap();
    assert_eq!(ff.get("args"), None, "entry replaced whole, args dropped");
    assert_eq!(cfg["output"]["dir"].as_str(), Some("out"), "plain tables deep-merge");
    assert_eq!(cfg["output"]["format"].as_str(), Some("mkv"));
}
```

## User directories

```rust
use std::ffi::OsString;
use std::path::PathBuf;

pub type Env<'a> = &'a dyn Fn(&str) -> Option<OsString>;

fn abs(env: Env, key: &str) -> Option<PathBuf> {
    env(key).map(PathBuf::from).filter(|p| p.is_absolute())
}

fn non_empty(env: Env, key: &str) -> Option<PathBuf> {
    env(key).filter(|v| !v.is_empty()).map(PathBuf::from)
}

pub fn config_dir(env: Env, app: &str, override_var: &str) -> Option<PathBuf> {
    non_empty(env, override_var)
        .or_else(|| abs(env, "XDG_CONFIG_HOME").map(|p| p.join(app)))
        .or_else(|| abs(env, "HOME").map(|h| h.join(".config").join(app)))
}

pub fn cache_dir(env: Env, os: &str, app: &str, override_var: &str) -> Option<PathBuf> {
    non_empty(env, override_var)
        .or_else(|| abs(env, "XDG_CACHE_HOME").map(|p| p.join(app)))
        .or_else(|| {
            let home = abs(env, "HOME")?;
            Some(match os {
                "macos" => home.join("Library/Caches").join(app),
                _ => home.join(".cache").join(app),
            })
        })
}
```

Production wiring passes the real environment:

```rust
let dir = config_dir(&|k| std::env::var_os(k), "<app>", "<APP>_CONFIG_DIR");
let cache = cache_dir(&|k| std::env::var_os(k), std::env::consts::OS, "<app>", "<APP>_CACHE_DIR");
```

Tests pass a map instead, so no test touches the process environment:

```rust
fn env_of(pairs: &[(&str, &str)]) -> impl Fn(&str) -> Option<OsString> {
    let m: std::collections::HashMap<String, OsString> =
        pairs.iter().map(|(k, v)| (k.to_string(), OsString::from(v))).collect();
    move |k| m.get(k).cloned()
}

#[test]
fn dirs_order() {
    let e = env_of(&[("HOME", "/home/u"), ("XDG_CONFIG_HOME", "rel")]);
    assert_eq!(config_dir(&e, "t", "T_CONFIG_DIR"), Some(PathBuf::from("/home/u/.config/t")));
    let e = env_of(&[("HOME", "/home/u"), ("XDG_CONFIG_HOME", "/x")]);
    assert_eq!(config_dir(&e, "t", "T_CONFIG_DIR"), Some(PathBuf::from("/x/t")));
    let e = env_of(&[("HOME", "/Users/u")]);
    assert_eq!(cache_dir(&e, "macos", "t", "T_CACHE_DIR"), Some(PathBuf::from("/Users/u/Library/Caches/t")));
    assert_eq!(cache_dir(&e, "linux", "t", "T_CACHE_DIR"), Some(PathBuf::from("/Users/u/.cache/t")));
    let e = env_of(&[("T_CACHE_DIR", "/c")]);
    assert_eq!(cache_dir(&e, "linux", "t", "T_CACHE_DIR"), Some(PathBuf::from("/c")));
}
```

## clap: positional input beside subcommands

The shape to avoid. A global flag before the subcommand is rejected:

```rust
#[derive(Parser)]
#[command(name = "tool", args_conflicts_with_subcommands = true)]
pub struct Conflicting {
    #[arg(long, global = true)]
    pub tools: Option<String>,
    pub video: Option<PathBuf>,
    #[command(subcommand)]
    pub command: Option<Command>,
}
// try_parse_from(["tool", "--tools", "x", "run", "c.toml"]) -> Err(ArgumentConflict)
// try_parse_from(["tool", "run", "c.toml", "--tools", "x"]) -> Ok
```

The shape to use:

```rust
use clap::{error::ErrorKind, CommandFactory, Parser, Subcommand};
use std::path::PathBuf;

#[derive(Parser, Debug)]
#[command(name = "tool", arg_required_else_help = true)]
pub struct Cli {
    /// Global: allowed before or after a subcommand.
    #[arg(long, global = true)]
    pub tools: Option<String>,
    /// Video mode input.
    pub video: Option<PathBuf>,
    /// Video-mode only option.
    #[arg(long)]
    pub start: Option<f64>,
    #[command(subcommand)]
    pub command: Option<Command>,
}

#[derive(Subcommand, Debug)]
pub enum Command {
    Run { config: PathBuf },
}

impl Cli {
    pub fn parse_checked(args: &[&str]) -> Result<Self, clap::Error> {
        let cli = Self::try_parse_from(args)?;
        if cli.command.is_some() && (cli.video.is_some() || cli.start.is_some()) {
            return Err(Self::command().error(
                ErrorKind::ArgumentConflict,
                "video options cannot be combined with a subcommand",
            ));
        }
        Ok(cli)
    }
}
```

In `main`, call the same check on `Cli::parse()`'s result and `e.exit()` on
error, so the message and exit code match clap's own.

The test matrix:

```rust
#[test]
fn debug_assert() {
    Cli::command().debug_assert();
}

#[test]
fn matrix() {
    let ok = |a: &[&str]| Cli::parse_checked(a).unwrap_or_else(|e| panic!("{a:?}: {e}"));
    let err = |a: &[&str]| {
        Cli::parse_checked(a).map(|c| panic!("{a:?} parsed: {c:?}")).unwrap_err().kind()
    };

    assert!(ok(&["tool", "v.mp4"]).video.is_some());
    assert!(ok(&["tool", "v.mp4", "--start", "5"]).start.is_some());
    assert!(ok(&["tool", "run", "c.toml"]).command.is_some());
    let c = ok(&["tool", "--tools", "x", "run", "c.toml"]);
    assert!(c.command.is_some() && c.tools.as_deref() == Some("x"));
    assert!(ok(&["tool", "run", "c.toml", "--tools", "x"]).tools.is_some());
    assert_eq!(err(&["tool", "--start", "5", "run", "c.toml"]), ErrorKind::ArgumentConflict);
    assert_eq!(err(&["tool", "v.mp4", "run", "c.toml"]), ErrorKind::ArgumentConflict);
    assert_eq!(err(&["tool"]), ErrorKind::DisplayHelpOnMissingArgumentOrSubcommand);
}
```

## Copy-out

```rust
use std::fs;
use std::io;
use std::path::{Component, Path, PathBuf};

fn is_plain_name(name: &str) -> bool {
    let mut parts = Path::new(name).components();
    matches!((parts.next(), parts.next()), (Some(Component::Normal(_)), None))
        && !name.starts_with('.')
}

pub fn copy_out(src: &Path, out_dir: &Path, name: &str) -> io::Result<PathBuf> {
    if !is_plain_name(name) {
        return Err(io::Error::new(
            io::ErrorKind::InvalidInput,
            format!("not a plain file name: {name:?}"),
        ));
    }
    let dest = out_dir.join(name);
    let tmp = out_dir.join(format!(".{name}.partial-{}", std::process::id()));
    fs::copy(src, &tmp)?;
    if let Err(e) = fs::rename(&tmp, &dest) {
        let _ = fs::remove_file(&tmp);
        return Err(e);
    }
    Ok(dest)
}
```

The temporary name sits in `out_dir`, not in the system temp directory: a
rename across filesystems fails, and only a rename within one filesystem is
atomic.

```rust
#[test]
fn plain_names() {
    for bad in ["", ".", "..", "../x", "a/b", "/abs", ".hidden"] {
        assert!(!is_plain_name(bad), "{bad}");
    }
    assert!(is_plain_name("clip.mp4"));
}
```

## Cache-key order

```rust
/// The order is part of the cache key. The "on" variant keeps the order
/// that existed before the stage became optional.
pub fn deps(denoise: bool) -> Vec<&'static str> {
    let mut d = vec!["decode", "denoise", "detect"];
    if !denoise {
        d.retain(|s| *s != "denoise");
    }
    d
}

#[test]
fn deps_on_order_pinned() {
    assert_eq!(deps(true), ["decode", "denoise", "detect"]);
    assert_eq!(deps(false), ["decode", "detect"]);
}
```
