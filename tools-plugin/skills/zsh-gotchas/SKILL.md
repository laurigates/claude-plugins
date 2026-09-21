---
name: zsh-gotchas
description: "Four zsh expansions that silently rewrite a command: $VAR:word modifiers, a leading =, no word splitting, `path` tied to PATH. Use when a zsh one-liner gives a wrong result or a tool seems missing."
allowed-tools: Bash, Read
created: 2026-09-21
modified: 2026-09-21
reviewed: 2026-09-21
---

# Zsh Gotchas — Four Expansions That Rewrite Your Command

Four zsh behaviours with no bash equivalent. Each one fires on **ordinary
commands**, including the one-liners an agent runs through the Bash tool — not
just on `.zsh` files — so a snippet lifted from a bash-tested doc breaks only
here.

What makes them expensive is that three of the four **fail silently or
misattribute**: the command runs, exits, and reports something that looks like a
real answer about the world. Every one below was diagnosed the wrong way first.

| Symptom | Mechanism | Section |
|---|---|---|
| A URL/path with `$var:` hits the wrong endpoint; fast empty 404 | `$VAR:x` is a history modifier | [1](#1-varword-is-a-modifier-not-a-colon-after-a-variable) |
| A later command in a `;` chain produced no output | a word starting with `=` is a command lookup | [2](#2-a-word-starting-with--is-a-command-lookup) |
| `$2` empty after `set -- $spec`; tool prints its usage text | zsh does not word-split | [3](#3-zsh-does-not-word-split-an-unquoted-parameter) |
| `command not found` for a tool that is installed | `path` is tied to `PATH` | [4](#4-path-is-not-a-free-variable-name) |

Sibling: zsh-vs-POSIX pattern expansion and extended glob, which is scoped to
`.zsh` / `zshrc` files rather than to every command.

## When to Use This Skill

| Use this skill when... | Use `shell-expert` instead when... |
|---|---|
| A zsh command ran and returned a result that does not match what you typed | Writing a shell script, function, or pipeline from scratch |
| An unexpected 404, an empty positional, or a missing chunk of output from a chain | Choosing portable constructs across bash / zsh / POSIX |
| `command not found` names a tool you know is installed | Structuring error handling, `set` flags, or CLI argument parsing |
| A bash-tested snippet behaves differently once run through the Bash tool | The question is shell *style* rather than a wrong runtime result |

The split is runtime versus authoring: this skill covers four expansions that
make a correct-looking zsh command do something else, three of them silently.

## 1. `$VAR:word` Is a Modifier, Not a Colon After a Variable

Zsh applies history-style **modifiers** directly to a bare parameter expansion:
`$f:h` (dirname), `$f:t` (basename), `$f:r`, `$f:e`, `$f:s/a/b/`, `$f:g…`. So a
URL that puts a variable straight before a colon is not the URL you wrote:

```zsh
# Wrong — `:g` is read as the start of a global-substitution modifier
curl "https://…/v1beta/models/$MODEL:generateContent"
```

Observed 2026-09-05 (robocar-unified, probing a replacement Gemini model): three
requests came back `HTTP 404` in **60 ms with an empty body**, and were nearly
reported as "the new model does not support generateContent". The empty body and
the sub-100 ms turnaround were the tell — a real API 404 carries a JSON error and
takes a round trip. The same request with braces returned 200.

### The fix

Brace the expansion. Braces end the parameter name, so the colon is literal:

```zsh
curl "https://…/v1beta/models/${MODEL}:generateContent"
```

Double quotes do **not** protect you — modifiers apply inside them.

### When it bites

- Gemini-style `model:method` REST paths, `host:port`, `user:group`,
  `file:line`, `scp`/`rsync` `host:path` targets — any `$var:` with a letter
  after the colon.
- A modifier letter that zsh does not recognise errors loudly
  (`unrecognized modifier`); the recognised ones (`g`, `h`, `t`, `r`, `e`, `s`,
  `a`, `A`, `l`, `u`, `q`, `Q`, `x`, `c`, `P`) fail silently by rewriting the
  string.

## 2. A Word Starting With `=` Is a Command Lookup

With `EQUALS` set (the zsh default), an unquoted word that begins with `=` is
replaced by the path of the command named after it: `=ls` becomes `/bin/ls`.
When no such command exists, the expansion is a **fatal error that aborts the
rest of the command line**, not just that word, and `;` does not contain it:

```zsh
zsh -fc 'echo a; echo ======; echo b'
# a
# zsh:1: ===== not found        ← `echo b` never runs, exit 1
```

Observed 2026-09-15 (claude-plugins, session-end): `survey.sh …; echo ======;
distill-survey.sh …` printed the survey, then `(eval):1: ===== not found`, and
the second collector silently never ran. The error names the word minus its
leading `=`, which reads like a missing command rather than a separator.

### The fix

Quote the word (`echo '======'`), or use a separator that does not start with
`=` (`echo ---`). `setopt noequals` also works but changes the shell for
everything after it.

### When it bites

- Section separators in chained diagnostics (`echo =====`, `print ==== x`).
- Arguments that start with `=`: `--flag =value`, `git log =main`, a jq or awk
  program passed unquoted.
- Mid-chain placement: everything after the bad word is lost, so the symptom is
  missing output from a later command, not an error at the one you wrote.

## 3. Zsh Does Not Word-Split an Unquoted Parameter

Bash splits an unquoted `$var` on `IFS`; zsh does not, because `SH_WORD_SPLIT`
is off by default. The whole string stays one word, so `$1` is everything and
`$2` is empty:

```zsh
# Wrong — $2 is empty, so gh runs without a PR number
for spec in "ForumViriumHelsinki/infrastructure 2379" "ForumViriumHelsinki/.github 127"; do
  set -- $spec
  gh pr view "$2" -R "$1" --json state
done
```

Observed 2026-09-16 (verifying three PRs after a merge): the loop printed gh's
usage text three times — *"argument required when using the --repo flag"* — and
verified nothing. The message names a **flag**, so it reads as a wrong invocation
rather than an empty variable, and the obvious next move is to rewrite the `gh`
call that was already correct.

### The fix

Force splitting with `${=var}`, or read into named variables:

```zsh
for spec in "ForumViriumHelsinki/infrastructure 2379"; do read -r repo num <<< "$spec"; gh pr view "$num" -R "$repo" --json state; done
```

Named variables are the better habit: they survive a copy into a bash script,
and they say what each field is.

### When it bites

- `set -- $line` / `set -- $spec` over a list of space-separated records — the
  natural way to unpack "repo number" or "host port" pairs.
- `cmd $args` where `args` holds several flags. Zsh passes them as **one**
  argument; the tool reports an unknown option containing spaces.
- Splitting on something other than whitespace: `${(s:,:)csv}` in zsh, not
  `IFS=, read`.

### The failure looks like a clean result, not an error

Both halves of that session's evidence were silent. The `gh` loop printed usage
text, and a malformed taskwarrior query minutes later (`task export
status:pending` — taskwarrior wants the filter **before** the command) returned
three empty lists that read exactly like an empty queue. A control re-run with
the correct order returned 457 tasks. Control-test any negative that gates an
action.

## 4. `path` Is Not a Free Variable Name

Zsh **ties `path` to `PATH`**: `path` is the array view, `PATH` the scalar view,
and writing either rewrites the other. Assigning a string to `path` therefore
destroys the search path for the rest of the shell.

The usual way in is a loop variable chosen for readability:

```zsh
# Wrong — `path` is special; PATH is destroyed on the FIRST iteration
while IFS=$'\t' read -r key title labels path; do
  gh issue create --title "$title" --body-file "$path" ...
done < list.tsv
```

Observed 2026-09-02 (silverbucket-helper, filing eight issues): every iteration
printed `command not found: tail`, and **nothing was created** — `gh` was already
unreachable by the time the body ran.

Zsh's tied variables are a small set, and the rest are just as ordinary looking:
`path`, `cdpath`, `fpath`, `manpath`, `fignore`, `mailpath`, `module_path`,
`prompt`, `psvar`, `status`, `argv`. `path` and `fpath` are the two a script is
most likely to reach for by accident.

### The fix

Pick a name that is not tied. Any of `bodyfile`, `file`, `p`, `target` works; the
rename is the whole fix.

```zsh
while IFS=$'\t' read -r key title labels bodyfile; do gh issue create --title "$title" --body-file "$bodyfile"; done < list.tsv
```

`typeset` does not rescue you — `local path` inside a function still shadows the
tied parameter and still breaks command lookup for that function's body.

### Check whether anything actually ran

The failure is loud but **misattributed**: zsh reports the missing command, not
the cause, so the obvious next move is to fix the "missing" tool. Before retrying
a loop that had side effects, establish whether the side effects happened — a
partially-completed run retried from the top creates duplicates.

```zsh
gh issue list --state open --limit 30 --json number,createdAt
```

In the case above the answer was none, because `PATH` died on iteration one
before `gh` was reached. Had it died later, some issues would exist and a blind
retry would have double-filed them.

## Verifying a Suspected Hit

All four are testable in one line against a pristine shell (`zsh -f` skips
rc files, so the result is the language's behaviour and not this machine's):

```zsh
zsh -fc 'M=models/x; echo "$M:generateContent"; echo "${M}:generateContent"'
```

```zsh
zsh -fc 'v="a b"; set -- $v; echo "bare: 1=[$1] 2=[$2]"; set -- ${=v}; echo "split: 1=[$1] 2=[$2]"'
```

If the braced or `${=…}` form differs from the bare one, the expansion is the
bug — not the tool you were calling.
