---
paths:
  - "git-repo-agent/**"
  - "vault-agent/**"
---
# Typer/Click CLI Completion: Bypass shellingham

Python CLIs built on [Typer] (and [Click] under it) ship `--install-completion`
and `--show-completion` flags that rely on
[`shellingham`](https://github.com/sarugaku/shellingham) to detect the parent
shell. `shellingham` walks the **parent process tree** (`/proc/$PPID/comm`-style),
not `$SHELL`. When the parent is anything other than a known shell, detection
raises `ShellDetectionFailure` and Typer prints the unhelpful:

```
Shell None is not supported.
```

This rule documents the fix that lets the CLI's completion generator slot
into a chezmoi-style registry without the bypass voodoo.

## When the failure mode bites

| Parent process | Outcome |
|---|---|
| Your interactive zsh / bash | Works — shellingham detects the shell |
| Claude Code (`node` runtime) | Fails — `node` isn't a shell |
| GitHub Actions runner | Fails — `bash -e` invocation from `Runner.Worker` doesn't always classify |
| Docker entrypoint (`sh -c …`) | Often fails — depends on the entrypoint chain |
| uv-installed tool invoked via subprocess from Python | Fails — parent is `python`, not a shell |
| `chezmoi apply` running the dotfiles completion generator | Fails — parent is `chezmoi`, not a shell |

Setting `$SHELL=/bin/zsh` does **not** help. `shellingham` ignores the env
var by design; the whole point is to detect the real running shell, not
trust whatever the user claims.

## The fix: an explicit `completion <shell>` subcommand

Add a Typer subcommand that takes the shell name as an argument and uses
Click's completion machinery directly, bypassing `shellingham`:

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
    (Claude Code, CI, Docker, chezmoi).
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

After this lands:

```bash
my-cli completion zsh > ~/.zfunc/_my-cli
```

works from any parent process — Click renders the completion script
without touching `shellingham`.

`complete_var` is the env var Click reads at completion time to
dispatch the runtime callback. Use the conventional Click form:
`_<PROG_NAME>_COMPLETE` with `-` replaced by `_` and uppercased.

## Wiring to a chezmoi-style completion registry

The dotfiles pattern under `~/.local/share/chezmoi/.chezmoidata/completions.toml`
iterates a `tool → command` table and runs each command, writing
`~/.zfunc/_<tool>`. Once your CLI ships the subcommand above, add one line:

```toml
[packages.completion_tools.zsh_completions]
  "my-cli" = "my-cli completion zsh"
```

`chezmoi apply` picks it up — no second outlier like the
`generate-claude-completion-simple.sh` parser is needed, because Typer
already knows every flag the CLI exposes.

## Required regression test

Per `.claude/rules/regression-testing.md`, every CLI that adds this
pattern needs at least one test that the subcommand emits a usable
script for each supported shell and a non-zero exit for unsupported
shells:

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

Markers per shell: zsh emits `#compdef` / `compdef`, bash emits
`complete -o nosort -F`, fish emits `complete -c …`.

## Why not just patch Typer's `--install-completion`?

Typer's existing callbacks are wired tightly to `shellingham` and don't
expose a fallback hook. Forking that path means monkey-patching a
private API; the explicit subcommand is one Click call and lives in
your own code. Same reason the patch goes here, not upstream — Typer's
maintainers have repeatedly punted on this issue because shellingham
*should* work in the happy path.

## Canonical implementation

- `git-repo-agent/src/git_repo_agent/main.py` (`completion` command)
- `git-repo-agent/tests/test_completion.py` (4 regression tests)

Mirror that layout when adding the pattern to a new CLI.

## Scope

Applies to every Python/Typer CLI in the laurigates portfolio —
currently `git-repo-agent` and `vault-agent`, plus any future sibling
built on `claude-agent-sdk` + Typer. Same scope as
`agent-cli-worktree-safety.md`.

## Related rules

- [`agent-cli-worktree-safety.md`](agent-cli-worktree-safety.md) — sibling-project family conventions for data-loss prevention
- [`gh-json-fields.md`](gh-json-fields.md) — format inspiration: concrete pitfall, concrete fix, canonical impl reference
- [`regression-testing.md`](regression-testing.md) — every bug fix gets a test

[Typer]: https://typer.tiangolo.com/
[Click]: https://click.palletsprojects.com/
