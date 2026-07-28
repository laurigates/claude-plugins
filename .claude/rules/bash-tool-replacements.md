---
created: 2026-05-11
modified: 2026-07-10
reviewed: 2026-07-10
---

# Bash → Tool Replacements

One read pattern in Bash — a **whole-command** `cat`/`head`/`tail` file read — is
blocked by the `bash-antipatterns` hook because the dedicated `Read` tool covers
the same ground faster, with structured output, and without paying the
parallel-batch cost.

The hook is a soft-block (exit 2) — by the time you read this, you've probably
already been blocked. Use this table to pick the right replacement.

> **The block fires only when the read IS the whole command** (#2148). `cat
> file.md` blocks; `cd repo && cat file.md`, `ls dir/; head -20 file`, and
> `echo "===" && cat -n file` all pass — a compound command has no single-call
> `Read` substitution.

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
>
> **Long pipelines are no longer blocked either** (#1873). The 5+-pipe
> discouraged-head block (a `cat`/`echo`/`printf` or redundant `grep | grep`
> scrape head) followed the same demotion in W29: its own message exempted
> every legitimate form (style, not safety), it plateaued in the mid-20s
> same-session repeat-block rate across six friction-learner readings, and it
> summed pipe counts across *independent* statements in one Bash call —
> blocking a batch of five 1-pipe `gh issue create | tail -1` statements as a
> "6-pipe scrape" (#2051, #2052). The steer survives as the `long-pipeline`
> teach nudge, which counts pipes per pipeline, not per invocation.

## The replacement table

Only a **whole-command** `cat`/`head`/`tail` read is **blocked** (exit 2). The
`grep`/`rg`/`find`/`ls` rows are **nudges** — the Bash form runs; the tool is
the more context-efficient choice when it's available in your session.

| Bash | Preferred tool | Enforcement |
|---|---|---|
| `grep -rn 'foo' src/` | `Grep(pattern="foo", path="src", -r=true, -n=true)` | Nudge (opt-in teach hook) — Bash form runs |
| `rg 'foo' --type ts` | `Grep(pattern="foo", glob="*.ts")` | Nudge — same as `grep` |
| `cat /abs/path/file.md` | `Read(file_path="/abs/path/file.md")` | **Blocked** — only as the whole command; a here-doc (`cat <<EOF`), a pipeline (`cat file \| jq`), or any compound command passes |
| `head -50 file.md` | `Read(file_path="/abs/path/file.md", limit=50)` | **Blocked** — same whole-command scope |
| `tail -50 file.md` | `Read(file_path=..., offset=<lines - 50>, limit=50)` | **Blocked** — same |
| `cd repo && cat file.md` | (decompose only if you want to) | **Allowed** — compound command, no single-call substitution (#2148) |
| `ls -1 docs/*.md` | `Glob(pattern="docs/*.md")` | Nudge (opt-in teach hook) — Bash form runs (#2036) |

The hook's logic for each:

- **`grep` / `rg`** — never blocked (demoted to the opt-in teach nudge, #1909/#1871). `Grep` is the context-efficient choice when present, but the Bash form always runs.
- **`ls`** — never blocked (demoted to the opt-in teach nudge, #2036). `Glob` is the context-efficient choice for pattern listings when present, but the Bash form always runs.
- **`cat` / `head` / `tail`** — blocked for a plain file read **that is the entire command**. Exempt: a pipeline (`cat file | jq`), a here-doc (`cat <<EOF`), a `/dev/stdin` or `/dev/null` path, and **any compound command** — a `&&`/`||` chain, a `;`-separated sequence, a subshell, or a command substitution (#2148). A trailing `# comment` does not count as a second statement, so `cat f.md  # notes` still blocks. As of #2008 this (and the `echo`/`printf`/`cat`-write and `sed -i` blocks) is decided **structurally** by `ast-grep --lang bash` rather than regex — a real parse tells a command apart from a string/heredoc-body/pipeline/argument, so the block **fails open** (no-op) where `ast-grep` is unavailable. It is a style nudge with no regex twin; the safety blocks (`chmod 777`, `curl|bash`, `git add -A`, …) stay pure-regex and fire everywhere.
- **`echo`/`printf`/`cat` writes and `sed -i`** — unchanged by #2148. They guard file *mutation*, not context budget, so they still fire inside a compound command.

### Remote-exec commands are exempt (issue #1900)

A read that runs on another host or container — `ssh host 'cat /r/f'`,
`ssh host <<EOF … cat /r/f … EOF`, `kubectl exec … -- cat` — targets the
**remote** filesystem, which `Read`/`Grep`/`Glob` cannot reach, so nudging is
pointless. Since #2008 this needs **no guard code**: the structural parse makes
those reads a string / heredoc-body / argument node, never a command node, so
they are never detected in the first place. (The `IS_REMOTE_EXEC` first-token
suppression #1900 shipped was deleted by #2114.) Safety blocks are pure-regex
and still fire on remote-exec commands — those hazards apply on the remote host
too.

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

The `cat`/`head`/`tail` block was **narrowed** (not demoted) in W31 (#2148).
PR #2114's structural port unintentionally widened it from "a bare read as the
whole command" to "a bare read anywhere in a compound command", and the
same-session repeat-block rate broke from a stable six-reading 6.3–20.0% band
to **46.3%** (70 events / 41 sessions; ~65% of blocked commands didn't begin
with a read). The repeat rate is the diagnostic: a compound command has no
one-to-one `Read` substitution, so the agent re-attempts a variant and is
re-blocked. The three read rules now require the read to be the sole statement
of the parsed program. Full demotion was rejected — the block was never
problematic at its pre-#2114 scope, and #2114's false-positive fixes all stand.

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
  hook that carries the non-blocking `find→Glob`, `grep`/`rg`→`Grep`,
  `ls`→`Glob`, and `long-pipeline` nudges
- `.claude/rules/hook-block-vs-nudge.md` — the litigation test behind the
  `find`/`grep`/`ls` demotions (block for safety, nudge for style)
