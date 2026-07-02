# Bash → Tool Replacements

Two search/list patterns in Bash — `grep`/`rg` and `cat`/`head`/`tail` — are
blocked by the `bash-antipatterns` hook because dedicated Claude Code tools
cover the same ground faster, with structured output, and without paying the
parallel-batch cost.

The hook is a soft-block (exit 2) — by the time you read this, you've probably
already been blocked. Use this table to pick the right replacement.

> **`find` is no longer blocked.** The `find→Glob` redirect was demoted from a
> hard block to an **opt-in teach nudge** (`bash-antipatterns-teach.sh`, enabled
> via `CLAUDE_HOOKS_ENABLE_BASH_ANTIPATTERNS_TEACH=1`). It never did safety work
> — it always exempted the dangerous `-exec` form and only blocked simple `-name`
> searches — and it hard-dead-ended subagents whose toolset doesn't grant Glob
> (PreToolUse hooks fire in every context; Glob is not always available). `find`
> in any form now passes. Glob is still the most *context-efficient* choice for a
> broad `**/*.ext` sweep in the main session, and `fd` is the more ergonomic
> shell alternative (`fd -e ts`, gitignore-aware by default) — prefer either over
> a naive recursive `find` dump, but neither is enforced.

## The replacement table

| Wrong (Bash) | Right (tool) | When the Bash form is genuinely fine |
|---|---|---|
| `grep -rn 'foo' src/` | `Grep(pattern="foo", path="src", -r=true, -n=true)` | Piped into another command (`gh pr list \| rg 'foo'`), or you need `-q` for an exit-code boolean check |
| `rg 'foo' --type ts` | `Grep(pattern="foo", glob="*.ts")` | Same exceptions as `grep` |
| `cat /abs/path/file.md` | `Read(file_path="/abs/path/file.md")` | Piping a *here-doc* into a command — that's a `cat <<EOF` heredoc, not a file read |
| `head -50 file.md` | `Read(file_path="/abs/path/file.md", limit=50)` | Inside a hook script where Bash is the only option |
| `tail -50 file.md` | `Read(file_path=..., offset=<lines - 50>, limit=50)` | Same |
| `ls -1 docs/` | `Glob(pattern="docs/*")` *or* `Bash("ls -1 docs/")` | `ls` is fine for directory listing — the hook only blocks `ls *.glob` patterns |

The hook's allowed-exception logic for each:

- **`grep` / `rg`** — passes through any pipeline (anything with `|`), and `-q` / `--quiet` (boolean exit-code checks like `grep -q pattern file && do_thing`).
- **`cat` / `head` / `tail`** — passes through when the file path is `/dev/stdin`, `/dev/null`, or a here-doc target. The hook is checking for *file reads*, not stream handling.

### Remote-exec commands are exempt (issue #1900)

When the command's **first token** is a remote-exec launcher — `ssh`, `rsh`,
`slogin`, `dokku`, `kubectl exec`, `docker exec` (and `podman`/`nerdctl`/`oc`
equivalents) — the read/list nudges (`ls`→Glob, `cat`/`head`/`tail`→Read,
`grep`/`rg`→Grep) are **suppressed** for the whole command. The Read/Grep/Glob
tools operate on the **local** filesystem via the harness; they cannot reach a
path on the remote host or inside a container, so the suggested substitution is
inapplicable. This covers both the quoted form (`ssh host 'ls /r/*'`) and the
heredoc form (`ssh host <<EOF … ls /r/*.json … EOF`), which was the concrete
false positive. Only *style* nudges are suppressed — **safety** blocks
(`curl | bash`, `chmod 777`, `git add -A`, block-device writes) still fire, since
those hazards apply on the remote host too. The guard is anchored to the first
token, so a local `cat x.txt && ssh host …` still nudges the local `cat`.

## Why this exists

Three signals from the W20 friction analysis (2026-05-11):

| Pattern | Events / sessions | Per-session rate | Same-session repeat-block rate |
|---|---|---|---|
| `find` vs `Glob` | 29 / 25 | 17% | 12% |
| `grep` / `rg` vs `Grep` | 41 / 33 | 24% | **21%** |
| `cat`/`head`/`tail` vs `Read` | 29 / 24 | 17% | low |

The `grep` / `rg` 21% same-session repeat-block rate is the outlier:
the hook is teaching less effectively for this pattern than for `find`
or `git &&` (both at 8-12%). This rule fills the gap with the same
explicit do/don't table style that worked for `find` in W16.

## When to keep `grep` / `rg` in Bash

The hook allows the `grep`/`rg` Bash form in three scenarios:

1. **Pipelines.** `gh pr list --json title --jq '.[].title' | rg 'feat'`
   is fine — the `|` short-circuits the hook check.
2. **Boolean exit-code checks.** `grep -q pattern file && do_thing`
   is fine. The `Grep` tool returns content; it doesn't give you a
   clean shell-conditional exit code.
3. **File-list / count filter modes.** `grep -l pattern f1 f2`
   (files-with-matches), `grep -c pattern file` (count), and
   `grep -L …` (files-without-match) are filters over a known file set,
   not codebase searches the `Grep` tool replaces. (The uppercase
   context flag `-C` is *not* exempt — it's a real search.)

In all three cases the hook silently passes the command through. If
you're getting blocked anyway, you're not in one of these cases —
switch to the tool.

`find` needs no exception list — it is never blocked. Reach for `Glob`
or `fd` when you want the context-efficient / ergonomic option, but the
hook won't stop a plain `find`.

## Related

- `.claude/rules/parallel-safe-queries.md` — why the Bash form is
  doubly painful in parallel batches: it both fires the hook AND
  exits non-zero on empty results, cancelling sibling tool calls
- `hooks-plugin/hooks/bash-antipatterns.sh` — the hook that
  implements the `grep`/`rg` and `cat`/`head`/`tail` blocks (and a
  comment explaining why `find` is no longer among them)
- `hooks-plugin/hooks/bash-antipatterns-teach.sh` — the opt-in teach
  hook that carries the non-blocking `find→Glob` nudge
