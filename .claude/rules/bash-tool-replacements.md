---
created: 2026-05-11
modified: 2026-11-24
reviewed: 2026-07-10
---

# Bash → Tool Replacements

Unscoped on purpose: the block fires on a Bash **command**, which no `paths:`
glob can see (`.claude/rules/context-engineering.md`).

The `bash-antipatterns` hook blocks (exit 2) one pattern: a `cat`/`head`/`tail`
file read **that is the whole command**. Use `Read` instead; it gives
line-numbered output without the parallel-batch cost. A compound command
(`cd repo && cat f`, `ls d; head f`), a pipeline (`cat f | jq`), a here-doc
(`cat <<EOF`) and a `/dev/stdin` or `/dev/null` path all pass (#2148). A
trailing `# comment` is not a second statement, so `cat f.md  # notes` still
blocks.

`find`, `grep`/`rg`, `ls` and long pipelines are **never blocked**. They are
opt-in teach nudges (`bash-antipatterns-teach.sh`,
`CLAUDE_HOOKS_ENABLE_BASH_ANTIPATTERNS_TEACH=1`) because those blocks did style
work, not safety work, and dead-ended subagents without `Glob`/`Grep` (#1871,
#1909, #2036, #1873). `Glob`/`Grep`/`fd` stay the context-efficient choice for a
broad sweep when the session has them.

## The replacement table

| Bash | Preferred tool | Enforcement |
|---|---|---|
| `grep -rn 'foo' src/` | `Grep(pattern="foo", path="src", -r=true, -n=true)` | Nudge (opt-in teach hook) — Bash form runs |
| `rg 'foo' --type ts` | `Grep(pattern="foo", glob="*.ts")` | Nudge — same as `grep` |
| `cat /abs/path/file.md` | `Read(file_path="/abs/path/file.md")` | **Blocked** — only as the whole command |
| `head -50 file.md` | `Read(file_path="/abs/path/file.md", limit=50)` | **Blocked** — same whole-command scope |
| `tail -50 file.md` | `Read(file_path=..., offset=<lines - 50>, limit=50)` | **Blocked** — same |
| `cd repo && cat file.md` | (decompose only if you want to) | **Allowed** — compound command (#2148) |
| `ls -1 docs/*.md` | `Glob(pattern="docs/*.md")` | Nudge (opt-in teach hook) — Bash form runs (#2036) |

## Write guards in the same hook

- **`cat` writes and `sed -i`** guard file *mutation*, so they still fire inside
  a compound command. Scratch writes pass: `/tmp`, a `mktemp -d` dir, a
  git-ignored project `tmp/`, the harness scratchpad (`sed -i`), or a file
  copied with `cp` earlier in the same command.
- **`echo`/`printf` writes** get a non-blocking nudge toward `Write`.
- **Remote-exec reads** (`ssh host 'cat /r/f'`, `kubectl exec … -- cat`) are
  never detected: the structural parse sees them as strings, not commands
  (#1900, #2008). The safety blocks in `bash-safety.sh` are pure regex and still
  fire there.

## When `grep` / `rg` in Bash is the right tool

1. **Pipelines** — `Grep` cannot sit mid-pipeline.
2. **Boolean exit-code checks** — `grep -q pattern file && do_thing`.
3. **File-list / count modes** — `grep -l`, `grep -c`, `grep -L` over a known
   file set.
4. **Sessions without the `Grep` tool** — some subagents have only Bash.

Hook mechanics (the `ast-grep` structural parse, fail-open behaviour), the
friction measurements behind each demotion, and why the `cat`/`head`/`tail`
block keeps exit 2: [`docs/rules/bash-tool-replacements.md`](../../docs/rules/bash-tool-replacements.md).

## Related

- `.claude/rules/parallel-safe-queries.md` — exit-1-on-empty queries in parallel batches
- `.claude/rules/hook-block-vs-nudge.md` — block for safety, nudge for style
- `hooks-plugin/hooks/bash-antipatterns.sh`, `bash-antipatterns-teach.sh`, `bash-safety.sh` — the hooks
