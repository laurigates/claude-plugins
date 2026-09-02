---
created: 2026-09-02
modified: 2026-09-02
reviewed: 2026-09-02
name: typer-cli-completion
description: Generate Typer/Click shell completions from a non-shell parent, bypassing shellingham. Use when `--install-completion` prints "Shell None is not supported", or when generating them in CI or Docker.
user-invocable: false
allowed-tools: Glob, Grep, Read, Edit, Write, Bash
---

# Typer/Click CLI Completion: Bypass shellingham

Python CLIs built on [Typer] (and [Click] under it) ship `--install-completion`
and `--show-completion`, which rely on
[`shellingham`](https://github.com/sarugaku/shellingham) to detect the parent
shell. `shellingham` walks the **parent process tree** (`/proc/$PPID/comm`-style),
not `$SHELL`. When the parent is anything other than a known shell, detection
raises `ShellDetectionFailure` and Typer prints:

```
Shell None is not supported.
```

Setting `$SHELL=/bin/zsh` does **not** help. `shellingham` ignores the env var
by design — the point is to detect the real running shell, not to trust what
the environment claims.

## When the failure mode bites

| Parent process | Outcome |
|---|---|
| Your interactive zsh / bash | Works — shellingham detects the shell |
| An agent runtime (Claude Code, a `node` host) | Fails — `node` isn't a shell |
| GitHub Actions runner | Fails — `bash -e` from `Runner.Worker` doesn't always classify |
| Docker entrypoint (`sh -c …`) | Often fails — depends on the entrypoint chain |
| A uv-installed tool invoked as a subprocess from Python | Fails — parent is `python` |
| A dotfiles manager running a completion generator (`chezmoi apply`) | Fails — parent is `chezmoi` |

The common shape: **anything that generates completions non-interactively**.
That is precisely when you want to generate them — at install time, in a
container build, from a dotfiles apply — so the happy path is the one case that
does not need the feature.

## The fix: an explicit `completion <shell>` subcommand

Take the shell name as an argument and call Click's completion machinery
directly:

```python
import typer
from rich.console import Console

app = typer.Typer(name="my-cli")
console = Console()
EXIT_CONFIG_ERROR = 2  # or whatever your CLI uses


@app.command()
def completion(
    shell: str = typer.Argument(
        ...,
        help="Shell type: bash, zsh, or fish.",
    ),
) -> None:
    """Print a shell completion script to stdout.

    Bypasses ``shellingham`` so it works from non-shell parents
    (agent runtimes, CI, Docker, chezmoi).
    """
    from click.shell_completion import get_completion_class

    cls = get_completion_class(shell)
    if cls is None:
        console.print(
            f"[red]Shell '{shell}' is not supported.[/red] "
            "Choose one of: bash, zsh, fish."
        )
        raise typer.Exit(code=EXIT_CONFIG_ERROR)

    click_cmd = typer.main.get_command(app)
    comp = cls(
        cli=click_cmd,
        ctx_args={},
        prog_name="my-cli",
        complete_var="_MY_CLI_COMPLETE",
    )
    print(comp.source())
```

After this lands, generation works from any parent process:

```bash
my-cli completion zsh > ~/.zfunc/_my-cli
```

`complete_var` is the env var Click reads at completion time to dispatch the
runtime callback. Use the conventional Click form: `_<PROG_NAME>_COMPLETE`,
with `-` replaced by `_`, uppercased. Getting it wrong fails silently — the
script installs and simply never completes.

## Wiring to a completion registry

A dotfiles-style registry that iterates a `tool → command` table and writes
`~/.zfunc/_<tool>` needs one line per CLI once the subcommand exists. The
chezmoi form (`.chezmoidata/completions.toml`):

```toml
[packages.completion_tools.zsh_completions]
  "my-cli" = "my-cli completion zsh"
```

No bespoke parser is needed, because Typer already knows every flag the CLI
exposes.

## Required regression test

Assert the subcommand emits a usable script for each supported shell and exits
non-zero for unsupported ones:

```python
from typer.testing import CliRunner
from my_cli.main import app

runner = CliRunner()


def test_completion_zsh_emits_script() -> None:
    result = runner.invoke(app, ["completion", "zsh"])
    assert result.exit_code == 0, result.output
    assert "compdef" in result.output


def test_completion_bash_emits_script() -> None:
    result = runner.invoke(app, ["completion", "bash"])
    assert result.exit_code == 0, result.output
    assert "complete" in result.output


def test_completion_unsupported_shell_exits_nonzero() -> None:
    result = runner.invoke(app, ["completion", "tcsh"])
    assert result.exit_code != 0
    assert "not supported" in result.output.lower()
```

Per-shell markers to assert on: zsh emits `#compdef` / `compdef`, bash emits
`complete -o nosort -F`, fish emits `complete -c …`.

## Why not patch Typer's `--install-completion`?

Typer's callbacks are wired tightly to `shellingham` and expose no fallback
hook, so overriding that path means monkey-patching a private API. The explicit
subcommand is one Click call in your own code. It is also why the fix belongs
downstream rather than upstream: Typer's maintainers have repeatedly declined
this, on the grounds that `shellingham` *should* work — which it does, in the
one case where you do not need it.

## Canonical implementation

- [`git-repo-agent/src/git_repo_agent/main.py`](https://github.com/laurigates/git-repo-agent/blob/main/src/git_repo_agent/main.py) — the `completion` command
- [`git-repo-agent/tests/test_completion.py`](https://github.com/laurigates/git-repo-agent/blob/main/tests/test_completion.py) — four regression tests

## Related

- `python-plugin:python-packaging` — `[project.scripts]` entry points, which is what gives the CLI a `prog_name` to complete
- `agent-patterns-plugin:agent-cli-worktree-safety` — sibling conventions for Typer CLIs that drive an agent SDK

[Typer]: https://typer.tiangolo.com/
[Click]: https://click.palletsprojects.com/
