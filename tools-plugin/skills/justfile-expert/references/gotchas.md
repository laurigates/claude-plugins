# Justfile Expert — Gotchas

Five just behaviours that pass a quick test and break in real use, for
[SKILL.md](../SKILL.md). Each section names the symptom, the cause, and the
fix. Module path functions (`source_directory()` vs `justfile_directory()`)
are in [REFERENCE.md](../REFERENCE.md) § Module System.

## Sub-justfiles

Moving recipes into a separate justfile (for example `tools/bench/justfile`,
run with `just -f tools/bench/justfile <recipe>`) changes the directory every
relative path resolves against: that justfile's own directory becomes the
working directory.

```just
# tools/bench/justfile
set working-directory := '../..'
set dotenv-path := '../../.env'
```

- `set working-directory` points recipes back at the repository root, so
  existing relative paths keep working.
- `set dotenv-path` loads the root `.env`; it is resolved against the
  justfile's directory, not the new working directory.

A recipe in that file that calls another recipe in the same file must pass the
file explicitly, and quoted:

```just
all:
    just -f {{quote(justfile())}} build
    just -f {{quote(justfile())}} report
```

`{{justfile()}}` interpolates unquoted, so a checkout under a path with a
space splits it into two arguments. With `working-directory` pointing at the
root, a bare `just build` finds the root justfile and runs its `build`, not
this file's.

## Path arguments

Recipes run with the justfile's directory (or `working-directory`) as the
current directory, not the directory the user typed the command in. A
relative path the user passes in therefore resolves against the wrong place:

```console
$ cd configs && just run local.toml     # recipe looks for <justfile dir>/local.toml
```

Join it to the caller's directory with `invocation_directory()`:

```just
run file:
    ./bin/run --config {{quote(join(invocation_directory(), file))}}
```

`join()` returns an absolute second argument unchanged, so absolute paths
still work. When a parameter accepts either a file path or a bare name (`a
.toml path or a preset name`), decide by the explicit form — "ends in `.toml`
means a path, anything else is a preset name" — rather than probing with
`[[ -f "$x" ]]`. The probe resolves against the recipe's directory, so it
answers a different question than the user asked.

## Top-level backticks

A variable assigned from a backtick at the top level of a justfile is
evaluated whenever just evaluates the file, which happens for every recipe
that runs, not only the recipes that use it:

```just
set shell := ["bash", "-euo", "pipefail", "-c"]

latest := `ls runs/ | grep -E '^run-' | tail -1`   # evaluated for EVERY recipe
```

With no matching file, `grep` exits 1, `pipefail` makes the pipeline fail, and
just aborts with `Backtick failed with exit code 1` — while running `just fmt`,
a recipe that never reads `latest`. `just --dry-run <recipe>` exits 0 on the
same justfile (checked with just 1.59), so the failure only shows up on a real
run.

Fix: move the logic into a script that exits 0 on an empty result and prints
nothing, call it from inside the recipes that need it, and give the script a
unit test for the empty case:

```bash
#!/usr/bin/env bash
# scripts/latest-run.sh — print the newest run dir, or nothing; always exits 0
set -uo pipefail
find runs -maxdepth 1 -name 'run-*' -type d 2>/dev/null | sort | tail -1
```

```just
report:
    ./bin/report "$(scripts/latest-run.sh)"
```

## Keep-awake wrappers

A long recipe (a benchmark, a batch job) often wraps itself to stop the
machine sleeping. The wrapper differs per platform:

| Platform | Wrapper |
|----------|---------|
| macOS | `caffeinate -i <command>` |
| Linux with systemd-logind | `systemd-inhibit --what=idle:sleep <command>` |

`systemd-inhibit` is installed in many containers and WSL distributions that
have no logind, and there it fails at once. Started in the background
(`nohup systemd-inhibit … &`), the recipe prints "started" and runs nothing.
Probe it before using it, and fall back to running the command directly:

```just
batch *args:
    #!/usr/bin/env bash
    set -euo pipefail
    if command -v caffeinate >/dev/null; then
      exec caffeinate -i ./bin/batch {{args}}
    elif systemd-inhibit --what=idle:sleep true >/dev/null 2>&1; then
      exec systemd-inhibit --what=idle:sleep ./bin/batch {{args}}
    else
      exec ./bin/batch {{args}}
    fi
```

## Hooks instead of personal tools

A recipe that calls one person's notifier or helper by name (a chat-bot CLI,
a desktop notification script) fails for everyone else. Read the command from
an environment variable with an empty default, and run it only when set:

```just
notify_cmd := env("NOTIFY_CMD", "")

batch:
    ./bin/batch
    if [ -n "{{notify_cmd}}" ]; then bash -c "{{notify_cmd}} \"\$@\"" _ "batch finished" "exit 0"; fi
```

`bash -c "$CMD \"\$@\"" _ args…` passes each argument through as one word, so
a message with spaces stays intact; the `_` fills `$0`. Interpolating the
arguments into the command string instead re-splits them.

The same applies to platform-specific flags. `stat -f %z <file>` (file size)
is BSD-only; GNU `stat` reads `-f` as "file system". Use `wc -c < <file>`,
which prints the byte count on both.
