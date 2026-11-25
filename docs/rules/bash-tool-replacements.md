# Bash → Tool Replacements: rationale and history

The always-loaded rule [`.claude/rules/bash-tool-replacements.md`](../../.claude/rules/bash-tool-replacements.md)
keeps what a turn needs: which read is blocked, what passes, and the
replacement table. This page holds the hook mechanics, the friction
measurements and the demotion history behind it, moved here verbatim on
2026-11-24 so they no longer load on every turn.

## Demotions of the `find`, `grep`/`rg`, `ls` and long-pipeline blocks

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

## The hook's logic, rule by rule

- **`grep` / `rg`** — never blocked (demoted to the opt-in teach nudge, #1909/#1871). `Grep` is the context-efficient choice when present, but the Bash form always runs.
- **`ls`** — never blocked (demoted to the opt-in teach nudge, #2036). `Glob` is the context-efficient choice for pattern listings when present, but the Bash form always runs.
- **`cat` / `head` / `tail`** — blocked for a plain file read **that is the entire command**. Exempt: a pipeline (`cat file | jq`), a here-doc (`cat <<EOF`), a `/dev/stdin` or `/dev/null` path, and **any compound command** — a `&&`/`||` chain, a `;`-separated sequence, a subshell, or a command substitution (#2148). A trailing `# comment` does not count as a second statement, so `cat f.md  # notes` still blocks. As of #2008 this (and the `echo`/`printf`/`cat`-write and `sed -i` blocks) is decided **structurally** by `ast-grep --lang bash` rather than regex — a real parse tells a command apart from a string/heredoc-body/pipeline/argument, so the block **fails open** (no-op) where `ast-grep` is unavailable. It is a style block with no regex twin, kept at exit 2 as the deliberate exception named in `.claude/rules/hook-block-vs-nudge.md`; the safety blocks (`chmod 777`, `curl|bash`, `git add -A`, …) live in the separate `bash-safety.sh` hook (#2788), stay pure-regex and fire everywhere.
- **`cat` writes and `sed -i`** — unchanged by #2148. They guard file *mutation*, not context budget, so they still fire inside a compound command. Scratch writes pass: `/tmp`, a `mktemp -d` dir, or a git-ignored project `tmp/` (#2892, #2837); `sed -i` also passes in the harness scratchpad under `~/tmp/claude-<uid>/…/scratchpad/` (#3525). `sed -i` also passes when each edited file was copied with `cp` earlier in the same command (a mutation probe).
- **`echo`/`printf` writes** — a non-blocking nudge: the command runs and the model gets a PreToolUse `additionalContext` note preferring Write. The rationale is in `.claude/rules/hook-block-vs-nudge.md`.

## Remote-exec commands are exempt (issue #1900)

A read that runs on another host or container — `ssh host 'cat /r/f'`,
`ssh host <<EOF … cat /r/f … EOF`, `kubectl exec … -- cat` — targets the
**remote** filesystem, which `Read`/`Grep`/`Glob` cannot reach, so nudging is
pointless. Since #2008 this needs **no guard code**: the structural parse makes
those reads a string / heredoc-body / argument node, never a command node, so
they are never detected in the first place. (The `IS_REMOTE_EXEC` first-token
suppression #1900 shipped was deleted by #2114.) Safety blocks are pure-regex
and still fire on remote-exec commands — those hazards apply on the remote host
too. The one text they skip is the body of a quoted heredoc (or an unquoted one
with no `$(`/backtick) fed to `cat`/`tee`/`gh`/`git` with no pipe (#3363).

## Why the block exists

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

Two upstream fixes do not change that rationale. Since Claude Code 2.1.293 a
single-file `cat`/`head`/`tail`/`sed -n`/`grep` in Bash loads path-scoped rules
and nested CLAUDE.md files the same way `Read` does, and since 2.1.295 a Bash
`cat` that printed nothing no longer marks the file as read. The block never
rested on rule loading: it rests on line-numbered output, the token budget and
the parallel-batch cost, which still favour `Read`.
