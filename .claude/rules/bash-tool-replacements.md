# Bash → Tool Replacements

Three search/list patterns in Bash are blocked by the `bash-antipatterns`
hook because dedicated Claude Code tools cover the same ground faster,
with structured output, and without paying the parallel-batch cost.

The hook is already a soft-block (exit 2) — by the time you read this,
you've probably already been blocked. Use this table to pick the right
replacement.

## The replacement table

| Wrong (Bash) | Right (tool) | When the Bash form is genuinely fine |
|---|---|---|
| `find . -name '*.ts'` | `Glob(pattern="**/*.ts")` | Need `-maxdepth`, `-mindepth`, `-type d`, `-print0`, or `-mtime` — Glob can't do directory-discovery flags |
| `find . -name '*.md' -type d` | `find . -name '*.md' -type d` | Already correct — `-type d` is the directory-discovery flag the hook explicitly allows |
| `grep -rn 'foo' src/` | `Grep(pattern="foo", path="src", -r=true, -n=true)` | Piped into another command (`gh pr list \| rg 'foo'`), or you need `-q` for an exit-code boolean check |
| `rg 'foo' --type ts` | `Grep(pattern="foo", glob="*.ts")` | Same exceptions as `grep` |
| `cat /abs/path/file.md` | `Read(file_path="/abs/path/file.md")` | Piping a *here-doc* into a command — that's a `cat <<EOF` heredoc, not a file read |
| `head -50 file.md` | `Read(file_path="/abs/path/file.md", limit=50)` | Inside a hook script where Bash is the only option |
| `tail -50 file.md` | `Read(file_path=..., offset=<lines - 50>, limit=50)` | Same |
| `ls -1 docs/` | `Glob(pattern="docs/*")` *or* `Bash("ls -1 docs/")` | `ls` is fine for directory listing — the hook only blocks `ls *.glob` patterns |

The hook's allowed-exception logic for each:

- **`find`** — passes through `-maxdepth`, `-mindepth`, `-type` (with a space after), `-print0`. Use these when Glob genuinely can't replace `find`.
- **`grep` / `rg`** — passes through any pipeline (anything with `|`), and `-q` / `--quiet` (boolean exit-code checks like `grep -q pattern file && do_thing`).
- **`cat` / `head` / `tail`** — passes through when the file path is `/dev/stdin`, `/dev/null`, or a here-doc target. The hook is checking for *file reads*, not stream handling.

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

## When to keep `find` / `grep` / `rg` in Bash

The hook allows the Bash form in four scenarios:

1. **Pipelines.** `gh pr list --json title --jq '.[].title' | rg 'feat'`
   is fine — the `|` short-circuits the hook check.
2. **Directory-discovery flags.** `find . -maxdepth 2 -type d` is the
   right form. `Glob` doesn't expose directory-type filters.
3. **Boolean exit-code checks.** `grep -q pattern file && do_thing`
   is fine. The `Grep` tool returns content; it doesn't give you a
   clean shell-conditional exit code.
4. **File-list / count filter modes.** `grep -l pattern f1 f2`
   (files-with-matches), `grep -c pattern file` (count), and
   `grep -L …` (files-without-match) are filters over a known file set,
   not codebase searches the `Grep` tool replaces. (The uppercase
   context flag `-C` is *not* exempt — it's a real search.)

In all four cases the hook silently passes the command through. If
you're getting blocked anyway, you're not in one of these cases —
switch to the tool.

## Related

- `.claude/rules/parallel-safe-queries.md` — why the Bash form is
  doubly painful in parallel batches: it both fires the hook AND
  exits non-zero on empty results, cancelling sibling tool calls
- `hooks-plugin/hooks/bash-antipatterns.sh` — the hook that
  implements all three blocks
