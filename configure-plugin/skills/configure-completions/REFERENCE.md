# configure-completions Reference

Templates for the three requirements in [SKILL.md](SKILL.md). Worked example:
laurigates/shore-recon#96 (Rust, clap, cargo-dist, a Homebrew tap).

## Homebrew's helper

`generate_completions_from_executable(*commands, shell_parameter_format:, shells:)`
runs the binary once per shell at install time and installs the output into
`bash_completion`, `zsh_completion` and `fish_completion`. Default shells are
bash, zsh and fish (`:cobra` and `:typer` add pwsh). How the shell name is
passed, from `Library/Homebrew/utils/shell_completion.rb`:

| `shell_parameter_format` | Invocation |
|--------------------------|------------|
| omitted (`nil`) | `<commands…> bash` — the bare shell name appended |
| `:cobra` | `<commands…> completion bash` |
| `:clap` | env `COMPLETE=bash` (clap_complete's dynamic `CompleteEnv`) |
| `:typer` | `<commands…> --show-completion bash` |
| `:click` | env `_<PROG>_COMPLETE=bash_source` |
| `:arg` | `<commands…> --shell=bash` |
| `:flag` | `<commands…> --bash` |

So a clap `completions <shell>` subcommand needs no format:
`generate_completions_from_executable(bin/"tool", "completions")`.

## Rust / clap

### Generator

```toml
# Cargo.toml (workspace deps pinned like the rest)
clap_complete = "=4.6.11"
```

```rust
use clap::CommandFactory;
use clap_complete::Shell;

#[derive(Debug, Subcommand)]
enum Command {
    // ...
    /// Print the completion script for a shell, e.g.
    /// `eval "$(tool completions zsh)"` in ~/.zshrc.
    Completions { shell: Shell },
}

const BIN: &str = "tool";

fn completions(shell: Shell) -> Vec<u8> {
    let mut script = Vec::new();
    clap_complete::generate(shell, &mut Cli::command(), BIN, &mut script);
    script
}

// in main's match:
Command::Completions { shell } => {
    std::io::Write::write_all(&mut std::io::stdout(), &completions(shell))?;
}
```

`Shell` is a `ValueEnum`: bash, elvish, fish, powershell, zsh.

### Drift test

```rust
/// The scripts in completions/ ship in the release archives;
/// regenerate them with `just completions` after changing the CLI.
#[test]
fn shipped_completions_match_the_cli() {
    let dir = Path::new(env!("CARGO_MANIFEST_DIR")).join("completions");
    for (shell, file) in [
        (Shell::Bash, "tool.bash"),
        (Shell::Zsh, "_tool"),
        (Shell::Fish, "tool.fish"),
    ] {
        let shipped = std::fs::read(dir.join(file)).unwrap_or_default();
        assert!(
            shipped == completions(shell),
            "completions/{file} is out of date with the CLI: run `just completions`"
        );
    }
}
```

`assert!(a == b)` rather than `assert_eq!` keeps a failure to one line instead
of two full scripts.

### Regenerate recipe

```just
# Regenerate the shell completion scripts shipped in the release archives
completions:
    cargo build -q -p tool
    mkdir -p crates/cli/completions
    target/debug/tool completions bash > crates/cli/completions/tool.bash
    target/debug/tool completions zsh > crates/cli/completions/_tool
    target/debug/tool completions fish > crates/cli/completions/tool.fish
```

### cargo-dist

Archives: `include` is package-local and relative to the config file.

```toml
[package.metadata.dist]
dist = true
include = ["completions/"]
```

Homebrew: dist's `homebrew.rb.j2` installs only executables (and libraries when
enabled), then moves every other archive file into `pkgshare` — so the
`completions/` directory lands in `share/<tool>/`, not in the completion paths.
Patch the generated formula in the publish job, after the artifacts are
downloaded and before `brew style`, and fail when the anchor line is gone:

```bash
# dist's formula installs only the binary; have Homebrew install the
# completions from it. Fail if dist's template no longer matches.
sed -i 's|^    install_binary_aliases!$|&\n\n    generate_completions_from_executable(bin/"tool", "completions")|' "Formula/${filename}"
grep -q generate_completions_from_executable "Formula/${filename}"
```

GNU sed syntax (the runner is Linux); macOS sed needs `-i ''` and does not
expand `\n` in the replacement. This works only with a custom publish job
(`publish-jobs = ["./publish-homebrew"]`); dist's built-in homebrew job has no
hook between generating and committing the formula.

The shell installer copies only executables, so it needs the docs lines.

## Go / cobra

Cobra adds a `completion [bash|zsh|fish|powershell]` command to the root by
default; `rootCmd.CompletionOptions.DisableDefaultCmd = true` removes it and
`HiddenDefaultCmd = true` hides it from help. Check neither is set.

GoReleaser `homebrew_casks` (the `brews` formula section is deprecated since
v2.10) runs the generator at install (v2.15+):

```yaml
homebrew_casks:
  - name: tool
    generate_completions_from_executable:
      shell_parameter_format: cobra   # adds `completion <shell>` itself
```

`executable` defaults to the cask's first binary; set it when the cask ships
more than one. Check the field list in GoReleaser's `homebrew_casks` docs for
the version the repo pins.

Archives: generate in a `before` hook and add the files, so no committed copy
exists and no drift test is needed:

```yaml
before:
  hooks:
    - sh -c 'mkdir -p completions && for s in bash zsh fish; do go run . completion "$s" > "completions/tool.$s"; done'
archives:
  - files:
      - completions/*
```

The cask can instead install those files with its `completions:` map
(`bash: completions/tool.bash`, …).

## Python / Typer or Click

Typer's `--show-completion <shell>` and Click's `_<PROG>_COMPLETE=<shell>_source`
env var both print the script; `python-plugin:typer-cli-completion` covers
generating them outside an interactive shell, where Typer's shell detection
fails. Homebrew: `shell_parameter_format: :typer` or `:click`. For a committed
copy, the drift test is a pytest that runs the generator with the same env and
compares the bytes.

## Documentation block

Every channel without a Homebrew formula gets this in the usage doc, with the
README's install section linking to it:

```sh
eval "$(tool completions bash)"     # ~/.bashrc
eval "$(tool completions zsh)"      # ~/.zshrc, after compinit
tool completions fish | source      # ~/.config/fish/config.fish
```

Name the archive's `completions/` directory as the alternative for users who
copy the scripts into a completion directory.
