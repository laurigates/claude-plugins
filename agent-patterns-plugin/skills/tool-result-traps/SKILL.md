---
name: tool-result-traps
description: Tool results that mean something other than they look — a pattern that never compiled, a glob that cannot match a directory, one tier searched but reported absent, a rejected flag reading as "no results". Use when an empty result is about to gate an action, land in a doc, or be reported as done.
allowed-tools: Read, Glob, Grep, Bash(rg *), Bash(git grep *), Bash(git log *), Bash(git status *), Bash(git worktree *), Bash(gh api *), Bash(gh pr view *), Bash(python3 *), TodoWrite
model: opus
created: 2026-08-21
modified: 2026-08-26
compatibility: claude-code
reviewed: 2026-08-21
---

# Tool Result Traps

Promoted from the always-loaded `~/.claude/rules/tool-use-patterns.md` rule,
whose stub points here. The section bodies below are that rule's verbatim text.

One law across all of them: **an empty result, a green exit, and a well-formed
line of output are each claims about *mechanics*, not about *content*.** Every
trap here produces output that is indistinguishable from a correct answer —
no error, no warning, nothing on stderr — and the damage lands when that
output is used as a verdict: "no duplicate exists", "the rename is complete",
"nothing was lost", "the agent got its input".

The recurring fix is equally uniform: **control-test any negative that gates an
action.** Re-run the same command shape against something you *know* is
present. If the control also comes back empty, the tool is broken, not the tree
clean. One control run is cheap; a wrong negative is a confidently-reported
non-finding.

## When to Use This Skill

| Use this skill when... | Skip when... |
|---|---|
| A zero-match or empty result is about to be reported as "clean", "complete", or "none found" | The result is non-empty and you are acting on what it contains |
| Deduping before filing an issue, or concluding nobody reported something | Reading a single known file whose path you just listed |
| Declaring a bulk rename, migration, or sweep finished | Mid-sweep, still transforming matches |
| A verification loop's input set is built from a relative path | The path was resolved absolutely in the same command that used it |
| Batching parallel tool calls whose siblings may exit non-zero | A single call, or a batch of confirmed-present paths |
| A `Workflow` script's agents report thin or generic findings on rich material | Agents are returning specific, grounded detail |
| An `rg`/`git grep` result contradicts something you read directly | Output matches an independent read of the same file |
| Concluding a skill, command, recipe, or binary "does not exist" | You enumerated every tier it could be defined in |
| A `-g`/`--glob` filter is doing the narrowing, and the name you want is a directory | The glob is `**/<name>/**`, or the search is on content not names |

## The traps

## Grep / rg — `-r` is `--replace`, not a bundled short flag

`rg`'s `-r` takes an argument: it **rewrites every match in the output**. Bundling
it into a short-flag cluster silently consumes the next letter as the replacement
string, so the tool prints *fabricated* lines that look like real file contents.

```
# Wrong — reads as "recursive + line numbers"; actually means --replace=n
rg -rn "yolo" .
./conf/cli_clients/gemini.json:    "--n"      ← the file says "--yolo"; rg rewrote it

# Right
rg -n "yolo" .
./conf/cli_clients/gemini.json:    "--yolo"
```

The failure is **silent and confident**: no error, no warning, and the output is
well-formed — it just doesn't match the file on disk. Observed 2026-07 building a
false picture of a config file that was then nearly acted on; caught only because
the doctored line contradicted an earlier direct `Read` of the same file.

- **`rg` is recursive by default** — there is no `-r` to add. The instinct is
  imported from `grep -r`, and that's the trap.
- **Never bundle `-r` into a cluster.** If an `rg` result contradicts something you
  read directly, suspect the flags before you suspect the file.
- **Prefer the Grep tool** over `rg` in Bash: it has no `--replace` surface, so
  this class of error cannot occur.

## `git grep -E` has no `\b` — the pattern matches nothing, silently

`git grep`'s `-E` is POSIX ERE, where `\b` is undefined. A word-boundary pattern
therefore matches **nothing at all** — no error, nothing on stderr, just an empty
result and exit 1. Exit 1 from grep *means* "no matches", which is precisely what
a genuinely clean result looks like, so nothing anywhere signals that the pattern
was never valid.

```
git grep -nE '\bprisma\b' -- package.json    # rc=1, 0 lines, stderr empty
git grep -nP '\bprisma\b' -- package.json    # rc=0, 19 lines   ← PCRE, works
git grep -nwE 'prisma'    -- package.json    # rc=0, 19 lines   ← -w, works
grep     -nE '\bprisma\b'    package.json    # rc=0, 19 lines   ← GNU/BSD extension
```

The trap is that `\b` **does** work in plain `grep`/`rg`, so the habit is
well-formed everywhere except the one tool that silently drops it. Worst case is
a **completion verdict on a bulk sweep**: `git grep -E '\btrends\b'` returning
empty reads as "the rename is complete" when it never searched for anything.
Observed 2026-08 on a 112-file rename; caught only by the known-good control run
that `never-fabricate-test-identifiers.md` requires.

- **Use `-w` for word boundaries in `git grep`**, or `-P` for full PCRE. Reach for
  plain `grep -E` / `rg` outside a git-tracked scope.
- **A zero-match sweep verdict must be control-tested** — re-run the same pattern
  shape against a term you know is present. If the control is also empty, the
  pattern is broken, not the tree clean.
- Piping (`| wc -l`) masks the exit code entirely, so even the rc=1 tell is gone.

## A `-g '*name*'` glob cannot match a **directory** name

Two composing rules decide what a glob matches, and neither is visible in the
output:

1. **A glob containing no `/` is matched against the *basename* only** — at any
   depth. This is why `-g '*.md'` works recursively.
2. **A glob containing any `/` is anchored to the full path from the search
   root**, and `*` does not cross `/`. Only `**` spans depth.

So a name you are hunting that is a **directory** — a skill dir, a package dir,
a fixture dir — is unreachable by the glob everyone reaches for first:

```
tree:  skills/sentry-triage/SKILL.md

rg -uu --files -g '*.md'                  -> skills/sentry-triage/SKILL.md   ← basename
rg -uu --files -g '*sentry-triage*'       -> (nothing)   ← basename is SKILL.md
rg -uu --files -g '*sentry-triage*/**'    -> (nothing)   ← has '/', now anchored at root
rg -uu --files -g '*/SKILL.md'            -> (nothing)   ← '*' can't cross the 2nd '/'
rg -uu --files -g '**/sentry-triage/**'   -> skills/sentry-triage/SKILL.md   ← works
```

**The failure is worse than an empty result.** `-g '*name*'` still matches
*sibling files* whose basename contains the string, so a real tree returns
`sentry-triage-notes.md` — one plausible hit. An empty result at least invites
suspicion; a partial one reads as "the search ran fine, the file isn't there,"
and it is the sibling that sells it.

> Observed 2026-08 (`repos-claude-config#32`): confirming whether a
> `/sentry-triage` command existed. `rg --files -g '*sentry-triage*'` over
> `~/repos ~/.claude` returned only a stray `.md`, which was written into a
> published doc and a PR body as "no command by that name exists". It existed —
> `ForumViriumHelsinki/infrastructure/.claude/skills/sentry-triage/SKILL.md`.
> Caught only by a known-good control (`repo-activity`, a skill known to be on
> disk) returning zero through the identical glob.

- **Matching a directory name → `-g '**/<name>/**'`.** Nothing shorter works.
- **Prefer `rg -l <pattern>` or `find -type d -name` when hunting a *name*** —
  a content search has no basename rule to trip over.
- **Control-test with a name you know is present**, through the byte-identical
  glob. The control is what separates "not there" from "unmatchable".

## One search tier is not the search universe

A Claude Code skill or command resolves from **three independent tiers**, and
finding nothing in one says nothing whatsoever about the others:

| Tier | Location |
|---|---|
| User-global | `~/.claude/skills/`, `~/.claude/commands/` |
| Plugin | `~/.claude/plugins/cache/<marketplace>/<plugin>/skills/` |
| **Project** | **`<repo>/.claude/skills/`, `<repo>/.claude/commands/`** |

The project tier is the one that gets missed, because it is not under
`~/.claude/` at all — it ships inside whatever repo happens to be the checkout,
so the *same* command exists or doesn't depending on where a session is rooted.
That is a live precondition for a scheduled task or a cloud routine: a
project-scoped command resolves only when its repo is the clone.

The same shape recurs wherever definitions are tiered — shell functions vs.
`$PATH` binaries, `just -g` recipes vs. a local `justfile`, global vs. project
MCP servers, user vs. repo git config.

- **Enumerate all three before concluding a command does not exist.** In this
  portfolio, `rg -uu --files -g '**/<name>/**' ~/.claude ~/repos` covers the
  user and project tiers in one pass (note the glob form — see the trap above).
- **A marketplace search is not a project search.** `gh api search/code` over
  the plugin repo answers the plugin tier only.
- **State the tier you searched** when reporting a negative. "Not in
  `~/.claude/`" is a fact; "does not exist" is a claim about all three.

## A rejected flag looks exactly like "no results"

Any `cmd … | jq/grep` whose **non-zero exit** yields empty stdout masquerades as
a legitimate empty result. Worst case is a **dedup step**: you conclude nobody
reported the bug and file a duplicate.

Live instance: `gh search issues --state all` is invalid (that flag takes only
`{open|closed}`; `all` belongs to `gh issue list`). It prints usage to stderr,
so a `--jq` pipeline emits nothing — six consecutive false "no duplicate"
verdicts. Use `gh api --paginate "repos/O/R/issues?state=all"` + `grep` instead
(it returns PRs too; discriminate on `.pull_request`).

**The same trap on a *write*, which is worse.** A rejected flag on a command
meant to *change* something reports nothing and changes nothing, so "no output"
reads as success. Observed 2026-08: `gh issue comment <n> --body … --jq
.html_url` — `gh issue comment` has no `--jq` (it prints a URL, not JSON). The
call emitted nothing and posted no comment, so the cross-link between two
freshly-filed issues simply did not exist. Caught only by reading the issue back
afterwards. On a read you get a wrong answer; on a write you get a **silently
skipped action you will later report as done**.

**Worse still: an *accepted* flag that takes your stdin marker literally.** The
two cases above at least do nothing. A flag that is valid but means something
other than what you assumed writes **wrong content, successfully** — exit 0, a
URL printed, nothing to notice. Observed 2026-08:

```
# Wrong — --body takes a literal string, so the body becomes "-"
gh pr create --title "…" --body - <<'EOF'
## What
…
EOF
```

`gh`'s `--body` is a plain `string`; only `--body-file` documents `"-"` as
stdin (same split on `gh pr create`, `gh issue create`, `gh pr comment` — check
with `gh <cmd> --help | grep -- --body`). The heredoc was piped to a stdin
nobody read, `-` became the entire PR description, and the PR rendered as one
empty bullet. Caught only when a human said the description looked wrong.

- **Write the body to a file and pass `--body-file <path>`** (or `--body-file -`
  if you really want stdin). This also dodges the multi-line quoting mess —
  same instinct as `copy-paste-commands.md`.
- Append `; echo "EXIT=$?"` to any one-shot mutating `gh`/`git` call whose
  output you are not otherwise reading.
- **Verify the side effect, not the exit code**, for anything you will tell the
  user is complete — re-read the comment, the label, the pushed ref. For a body
  you authored, read it *back*: `gh pr view <n> --json body --jq '.body | length'`
  against a length you expect. A 1-char body is the tell.

**Control-test every negative that gates an action.** Re-run the same command
shape against a term you know is present; if the control also returns nothing,
the tool is broken, not the result empty. One control run caught all six above.
This is `never-fabricate-test-identifiers.md`'s known-good control, applied to
search.

## A worktree-isolated shell can wedge — and `cd` cannot unwedge it

The Bash tool's working directory is **persistent across calls**. In a
worktree-isolated session, one `cd` into the parent (shared) checkout moves it
there permanently, and the isolation guard then refuses **every** subsequent
command — *including the `cd` back*, because it evaluates the shell's current
cwd before running anything. The state is self-reinforcing:

```
cd /repo && rg …                 # succeeds; cwd now the shared checkout
cd /repo/.claude/worktrees/wt    # REFUSED — "resolved to the shared checkout"
pwd                              # REFUSED — same reason
```

**`! <cmd>` does not escape it.** The user's own `!`-prefixed command runs in
the *same session shell*, so handing them the `cd` (the reflex from the
denial-handoff above) fails identically. This is the one case where that
handoff is wrong.

**Recovery: `EnterWorktree` with an explicit `path`** pointing at the worktree
already in use. It re-pins the session's working directory as session state
rather than going through the shell, so the guard never sees the bad cwd:

```
EnterWorktree(path="/repo/.claude/worktrees/<name>")   # then `pwd` works again
```

- **Prevention**: never `cd` outside the worktree. Use absolute paths, or
  `git -C <path>` / `grep <abs-path>` — a *parallel* batch is the usual culprit,
  since one sibling's `cd` moves the cwd for everything after it.
- If the Grep tool is unavailable in the session (it is not always registered),
  Bash is the only search path — so this wedge can take out searching too. Read
  and Edit keep working; they take absolute paths and ignore cwd.

## The same persistent cwd makes a path-scoped *verification* pass over nothing

The wedge above is loud — every command is refused. The quieter consequence of
the same persistent cwd is a **verification that reports success having checked
zero items**, because its path filter is relative and the cwd moved out from
under it. Nothing errors; the check just has an empty input set, and an empty
set satisfies every "nothing was lost" assertion you can write.

```
cd repo/subdir && …                                  # cwd now subdir, persistently
git diff --name-only HEAD -- docs/                   # → empty: no repo/subdir/docs/
# verification loops over the empty list and prints "no content lost"
```

Observed 2026-08 verifying a 26-file migration: an earlier call had left the
cwd in a plugin subdirectory, so the file list came back empty and the
body-preservation check passed instantly. Re-run from the repo root it found 26
files — and still passed, but only the second run was evidence of anything.

- **Assert the input is non-empty before verifying it.** One line, and it turns
  a silent vacuous pass into a loud failure:

  ```python
  assert files, "FIXTURE INVALID: nothing to check — this verification is vacuous"
  ```

  This is `never-fabricate-test-identifiers.md`'s known-good control and the
  guard-integrity half of `validate-adversarial-constructions.md`, applied to
  an *ad-hoc* check rather than a committed test. Ad-hoc is exactly where it
  gets skipped, and exactly where nobody reviews it afterwards.
- **Anchor the paths instead of trusting the cwd** — `git -C <abs-repo>`, or
  resolve the repo root (`git rev-parse --show-toplevel`) in the same command
  that uses it. A relative path in a long-running session is a bet on state
  several calls back.
- **Report the count, not just the verdict.** "26 files checked, none lost"
  cannot hide this; "no content lost" can. Any check whose output would read
  identically at N=0 and N=26 is not yet a check.

## Workflow `args` can arrive as a JSON **string**, silently

Passing an object to the `Workflow` tool's `args` can reach the script
JSON-**encoded**, so `args.foo` is `undefined` and every agent runs without the
input. Nothing errors — the prompts interpolate the literal text `undefined`
and the run completes normally. Observed 2026-08: a 15-agent comparison ran
end-to-end against material it never received; only the synthesis agent noticed
and said so in its report.

- **Make the script defensive**, since you cannot rely on the delivery shape:

  ```js
  const SOURCE = typeof args === 'string'
    ? (JSON.parse(args).source ?? args)
    : (args?.source ?? '')
  ```

- **Re-run without re-paying for the good agents.** The cache key is the
  agent's `(prompt, opts)`, so *freeze the phases that were already correct
  byte-identical* — keep the broken interpolation literal (`undefined`) in
  their prompt template, add a corrected template for the affected phases only
  — then `Workflow({scriptPath, resumeFromRunId})`. The untouched phases replay
  from cache at zero cost. Changing a shared template string changes every
  prompt and forfeits the whole cache.
- **The tell is absence, not error**: agents reporting thin, generic, or
  hedged findings on material you know is rich. Have at least one agent state
  what it actually received.
## Parallel tool calls

### Do not parallel-batch a tool whose siblings can exit non-zero

When one call in a parallel batch exits non-zero, **every sibling is
marked cancelled** and wasted. Specific offenders to avoid in a batch:

- `task <filter> list` — exits 1 on empty result; use
  `task <filter> export | jq '.[]'` (always exit-0) instead.
- `tar -xzf <archive>` — fails on missing archive; verify path first.
- `ls <glob>` — fails on no-match; verify or use Glob.
- `jq` on possibly-empty pipelines.
- `Read` on a possibly-missing path (see above).

Pattern: when a batch's siblings depend on existence, do a single
existence-check call first (`Glob`, `ls -1`), then issue the parallel
batch over confirmed-present paths.

### Agent fan-out rate limits and mid-run kills

Promoted to a skill: see `agent-patterns-plugin:parallel-agent-dispatch`
(§ Concurrent Rate-Limit Risk → `references/failure-recovery.md`) before
fanning out more than ~3 heavy agents, and after any wave dies mid-run — it
carries the server burst limit vs session usage limit discrimination, safe
starting concurrency per agent profile, serialize-or-wave mitigation, the
audit-remote-before-resume protocol (`gh pr list`, `git ls-remote --heads`),
and why `resumeFromRunId` re-runs already-succeeded worktree agents.

For mechanical work (parsing, counting, audits) prefer one inline `python3`/`rg`
pass over an agent fan-out — see `offload-to-deterministic-substrate.md`.

### The remote is not the whole audit — a dead agent's work may be in a worktree

Step 2 above says audit the **remote**. That is only sufficient when the agent
actually ran remotely, and you cannot assume it did: `isolation: "remote"` can
resolve to a **local git worktree** in the shared checkout. Nothing in the
dispatch result distinguishes the two — the completion notification's
`worktreePath` field does, and so does `git worktree list`.

> Observed 2026-08-19 (claude-plugins). Three agents dispatched with
> `isolation: "remote"` all ran in `.claude/worktrees/agent-<id>/`. Two were
> killed by a 600s stall watchdog. For one, `gh pr list` and
> `git ls-remote --heads origin` were both empty, and its work was reported to
> the user as unrecoverable — twice. `git worktree list` showed its branch
> carrying a **complete** commit (both intended edits plus a 28-line doc table)
> that had simply never been pushed. The remote audit was correct and the
> conclusion drawn from it was wrong.

- **Audit local worktrees alongside the remote**, before concluding anything was
  lost:

  ```
  git worktree list
  git log --oneline origin/main..<branch>    # per stale worktree branch
  ```

- **An empty remote is evidence about the push, not about the work.** The two
  come apart precisely when an agent dies between committing and pushing — the
  most likely single point to die, since the push is the last step.
- **Mitigate at dispatch**: brief agents to commit, push, and open a *draft* PR
  before the bulk of the work, then push after each subsequent commit. The same
  session's retry survived having its branch merged and deleted mid-task because
  it had pushed early; the recovery cost was one cherry-pick onto a fresh branch.
- Cleanup of the leftover worktrees is governed by `agent-coworker-detection.md`
  (claude-plugins): gate removal on the agent's completion notification, never on
  PR state, and never `--force` — a non-forced `git worktree remove` refuses on a
  dirty tree, which is the property that makes it safe.

