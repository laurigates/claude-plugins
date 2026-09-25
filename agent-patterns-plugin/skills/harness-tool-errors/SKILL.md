---
name: harness-tool-errors
description: Claude Code harness tool errors — Read on a missing path, directory or oversized file; Edit before Read or after a formatter; Bash permission denials. Use when a Read, Edit, Write or Bash call errors.
allowed-tools: Read, Glob, Grep, Edit, Bash(ls *), Bash(git status *), TodoWrite
created: 2026-09-24
modified: 2026-09-25
reviewed: 2026-09-24
---

# Harness Tool Errors

Promoted from the always-loaded `~/.claude/rules/tool-use-patterns.md` rule,
whose stub points here. The sections below are that rule's text for the Read,
Edit/Write, WebFetch and Bash-denial failure modes.

Durable patterns distilled from weekly friction-learner reports. The
loud `bash-antipatterns` / `branch-protection` / `agent-coworker-detection`
hooks already enforce most of the recurring findings (git `&&` chains, `find`
vs Glob, `cat`/`head`/`tail`, sleep-chains, etc.); the patterns below
are the failure modes those hooks don't catch.

## When to Use This Skill

| Use this skill when... | Use something else when... |
|---|---|
| `Read` errors on a missing path, `EISDIR`, or "exceeds maximum allowed tokens" | An empty *search* result is about to gate an action → `tool-result-traps` |
| `Edit`/`Write` refuses with "has not been read yet" or "modified since read" | Finding every reference to a symbol before changing it → `code-quality-plugin:ast-grep-search` |
| A Bash call returns "Permission to use Bash has been denied" | A hook blocked the command with a message → `handling-blocked-hooks.md` |
| A WebFetch returns 404/403/timeout | The fetch worked but the page is empty → `documentation-plugin:docs-fetch-fallbacks` |

## Read tool

### Verify the path before calling Read

Read on a missing path is the dominant Read-side failure. The cause is
almost always an **assumed cwd**: the session's working directory moved
(worktree switch, prior `cd`, agent thread reset) and the cached path
no longer resolves.

```
# Wrong — three Reads against guessed paths
Read("/abs/a"); Read("/abs/b"); Read("/abs/c")

# Correct — one Glob tells you which exist
Glob(pattern="/abs/*")
```

**Agent threads always reset cwd between Bash calls.** Always pass
absolute paths from an agent prompt; never assume the cwd is preserved.

### Read is for files, not directories

`Read` on a directory errors with `EISDIR: illegal operation on a
directory`. The error message doesn't suggest the alternative.

```
# Wrong
Read(file_path="/abs/path/to/dir")     # → EISDIR

# Correct
Glob(pattern="/abs/path/to/dir/**/*.md")
Bash("ls -1 /abs/path/to/dir")
```

### Read refuses files >25000 tokens

```
File content (164836 tokens) exceeds maximum allowed tokens (25000).
```

Common offenders: vendored JSON dumps, generated schemas, lockfiles,
transcripts, large generated docs. **Locate the section with Grep first,
then page Read with `offset`/`limit`.**

```
Grep(pattern="needle", path="/abs/path", output_mode="content", -n=true)
Read(file_path="/abs/path", offset=420, limit=80)
```

## Edit / Write tool

### Read in the current session before Edit / Write

The harness tracks file-read state **per session**. Reading the file in
a previous Claude Code session does not satisfy the requirement. Error
signature:

> File has not been read yet. Read it first before writing to it.

At the start of an editing turn, batch-Read every file you intend to
touch. Then do the Edits. Do not interleave a Read-immediately-before-
Edit while having already batched Edits for other files.

### Re-Read after a formatter, hook, or coworker may have run

Distinct from "Edit before Read." The file *was* read this session,
but a formatter (`prettier`, `stylua`, `ruff format`), pre-commit hook,
build watcher, or concurrent coworker agent rewrote it between your
`Read` and your `Edit`. Error signature:

> File has been modified since read, either by the user or by a linter.

Re-trigger triggers:

| After this happens… | Re-Read before next Edit |
|---|---|
| `pre-commit run` | All staged files |
| Format command (`prettier --write`, `stylua`, `ruff format`) | Files in scope |
| `git commit` (commit hooks may rewrite) | Files just committed |
| Coworker agent detected | All in-flight files |
| A long background Bash ran while you were editing | The files it wrote |

Do not retry the Edit blindly — issue a fresh Read first, then re-craft
the Edit against the new line numbers.

### Edit surgically; don't rewrite the file

Prefer `Edit` with the smallest unique `old_string` over `Write`-ing the
whole file. A rewrite regenerates untouched lines from memory, so content
silently drifts and the diff is unreviewable. `Write` is for new files.

Programmatic rewrites count too: a `json.load` → `json.dumps` round-trip drifts
no values and still reformats untouched siblings — rewriting one `.mcp.json`
entry collapsed inline `args` across six unrelated servers, nearly shipping
that churn in ten PRs. Splice the target span in the raw text instead.

`Edit` refuses on a file unread this session, so "read it first" is already a
harness invariant. The uncovered half — checking what *else* depends on what
you are changing — has its own ladder (LSP → `ast-grep` → `rg`) in
`code-quality-plugin:ast-grep-search` § *Find references with the sharpest
instrument*.

## WebFetch — do not retry the same failing URL

Invoke `documentation-plugin:docs-fetch-fallbacks` when a WebFetch returns 404,
403, or a timeout — it carries the failure→fallback table (strip the query
string, `raw.githubusercontent.com`, `gh api repos/<o>/<r>/contents/<path>`,
alternate UA, context7/WebSearch), the two-attempt ceiling, and the rule to
surface the failure rather than loop.

A fetch that *succeeds* is still a summary: WebFetch returns a model's digest of
the page, not the page. When the answer gates real work, read the full source
(`gh api …/contents/<path>`, a raw URL, the file itself) rather than the digest.

## Bash permission denials are terminal

When a Bash call returns:

> Permission to use Bash has been denied

the denial is **final for that command**. Do not retry with cosmetic
variations (different quoting, prepended `env`, etc.) — it will be
denied again. Either:

1. Use the alternative tool suggested in the denial message.
2. Hand the exact command to the user with `! <cmd>` for them to run.

See `handling-blocked-hooks.md` (in claude-plugins) for the user-handoff
template.

## Where the rest of the rule went

| Topic from `tool-use-patterns.md` | Home |
|---|---|
| Find references: LSP → `ast-grep` → `rg` ladder, measured grep bias | `code-quality-plugin:ast-grep-search` |
| `gh api -f` sends strings; `-F` sends typed literals | `git-plugin:gh-cli-agentic` |
| Results that lie; control-test any negative; the `parseFloat` control that tested the wrong part of the pattern | `agent-patterns-plugin:tool-result-traps` (+ its REFERENCE.md) |

For mechanical work (parsing, counting, audits) prefer one inline
`python3`/`rg` pass over an agent fan-out — see
`offload-to-deterministic-substrate.md`.
