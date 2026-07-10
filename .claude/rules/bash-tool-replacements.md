---
created: 2026-05-11
modified: 2026-07-10
reviewed: 2026-07-10
---

# Bash → Tool Replacements

One list pattern in Bash — `cat`/`head`/`tail` — is blocked by the
`bash-antipatterns` hook because the dedicated `Read` tool covers the same ground
faster, with structured output, and without paying the parallel-batch cost.

The hook is a soft-block (exit 2) — by the time you read this, you've probably
already been blocked. Use this table to pick the right replacement.

> **`find`, `grep`/`rg`, and `ls` are no longer blocked.** All three redirects
> were demoted from a hard block to an **opt-in teach nudge**
> (`bash-antipatterns-teach.sh`, enabled via
> `CLAUDE_HOOKS_ENABLE_BASH_ANTIPATTERNS_TEACH=1`). None did safety work: the
> `find→Glob` block always exempted the dangerous `-exec` form and only
> blocked simple `-name` searches; the `grep/rg→Grep` block always exempted
> pipelines, boolean `-q` checks, and `-l/-c/-L` filter modes, blocking only
> benign line-numbered file reads; the `ls→Glob` block guarded a read-only
> listing whose regex (`^\s*ls\s+.*\*`) also false-positived on compound
> commands that merely *start* with `ls` and contain a `*` anywhere later
> (#2036). All three hard-dead-ended subagents whose toolset doesn't grant
> `Glob`/`Grep` (PreToolUse hooks fire in every context; those tools are not
> always available — #1909, where `ToolSearch(select:Grep)` returned "No
> matching deferred tools found" and every blocked search cost a retry; #1416
> for the `ls`→Glob branch). `find`, `grep`/`rg`, and `ls` in any form now
> pass. `Glob`/`Grep`/`fd` remain the most *context-efficient* choices for a
> broad sweep in the main session — prefer them, but none is enforced.

## The replacement table

Only the `cat`/`head`/`tail` rows are **blocked** (exit 2). The
`grep`/`rg`/`find`/`ls` rows are **nudges** — the Bash form runs; the tool is
the more context-efficient choice when it's available in your session.

| Bash | Preferred tool | Enforcement |
|---|---|---|
| `grep -rn 'foo' src/` | `Grep(pattern="foo", path="src", -r=true, -n=true)` | Nudge (opt-in teach hook) — Bash form runs |
| `rg 'foo' --type ts` | `Grep(pattern="foo", glob="*.ts")` | Nudge — same as `grep` |
| `cat /abs/path/file.md` | `Read(file_path="/abs/path/file.md")` | **Blocked** — except a *here-doc* (`cat <<EOF`) or a pipeline (`cat file \| jq`) |
| `head -50 file.md` | `Read(file_path="/abs/path/file.md", limit=50)` | **Blocked** — except in a pipeline, or inside a hook script |
| `tail -50 file.md` | `Read(file_path=..., offset=<lines - 50>, limit=50)` | **Blocked** — same |
| `ls -1 docs/*.md` | `Glob(pattern="docs/*.md")` | Nudge (opt-in teach hook) — Bash form runs (#2036) |

The hook's logic for each:

- **`grep` / `rg`** — never blocked (demoted to the opt-in teach nudge, #1909/#1871). `Grep` is the context-efficient choice when present, but the Bash form always runs.
- **`ls`** — never blocked (demoted to the opt-in teach nudge, #2036). `Glob` is the context-efficient choice for pattern listings when present, but the Bash form always runs.
- **`cat` / `head` / `tail`** — blocked for a plain file read; passes through when the file path is `/dev/stdin`, `/dev/null`, a here-doc target, or a pipeline. The hook is checking for *file reads*, not stream handling.

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

The `grep` / `rg` 21% same-session repeat-block rate was the outlier — the
hard block taught *less* effectively than it cost, and it dead-ended subagents
lacking the `Grep` tool. That block has since been **demoted to the opt-in teach
nudge** (#1909), following the same litigation as `find` (#1871): a block that
exempts every dangerous form is doing style work, not safety work, and style
wants a nudge (see `.claude/rules/hook-block-vs-nudge.md`).

The `ls`→Glob block followed in W28 (#2036): 63 events / 44 sessions with a
**31.8%** same-session repeat-block rate on the 2026-07-10 re-run (33.3% on
2026-07-06) — sustained ≥30% over two consecutive readings, the same
"resistant to teaching" profile that justified the `find` and `grep`
demotions. Its regex also false-positived on compound commands that merely
start with `ls` and contain a `*` anywhere later (e.g.
`ls -1 dir | head; find . -name '*.jsonl'`). Only the `cat`/`head`/`tail`
blocks remain — those prevent real context-budget waste on plain file reads
with a clean `Read` substitution, and never dead-end anyone (pipelines and
heredocs pass).

## When to reach for `grep` / `rg` in Bash

`grep`/`rg` are no longer blocked in any form — the Bash command always runs.
Reach for the `Grep` tool when it's available and you want the context-efficient
codebase search; keep `grep`/`rg` for the cases where the tool doesn't fit:

1. **Pipelines.** `gh pr list --json title --jq '.[].title' | rg 'feat'` —
   `Grep` can't sit mid-pipeline.
2. **Boolean exit-code checks.** `grep -q pattern file && do_thing` — the
   `Grep` tool returns content, not a clean shell-conditional exit code.
3. **File-list / count filter modes.** `grep -l pattern f1 f2`
   (files-with-matches), `grep -c pattern file` (count), `grep -L …`
   (files-without-match) — filters over a known file set, not codebase searches.
4. **Sessions without the `Grep` tool.** If `Grep` isn't in the session's
   toolset (some subagents), `grep`/`rg` is the only search you have — and the
   hook won't stop it (#1909).

`find` and `ls` are likewise never blocked. Reach for `Glob` or `fd` when you
want the context-efficient / ergonomic option, but the hook won't stop a plain
`find` or an `ls` glob (#2036).

## Related

- `.claude/rules/parallel-safe-queries.md` — why the Bash form is
  doubly painful in parallel batches: it both fires the hook AND
  exits non-zero on empty results, cancelling sibling tool calls
- `hooks-plugin/hooks/bash-antipatterns.sh` — the hook that
  implements the `cat`/`head`/`tail` blocks (and comments explaining why
  `find`, `grep`/`rg`, and `ls` are no longer among them)
- `hooks-plugin/hooks/bash-antipatterns-teach.sh` — the opt-in teach
  hook that carries the non-blocking `find→Glob`, `grep`/`rg`→`Grep`, and
  `ls`→`Glob` nudges
- `.claude/rules/hook-block-vs-nudge.md` — the litigation test behind the
  `find`/`grep`/`ls` demotions (block for safety, nudge for style)
