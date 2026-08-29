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
"nothing was lost", "the agent got its input". In one case the diagnostic *was*
written — and the caller's own `2>/dev/null` is what made it disappear.

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
| The command that produced the empty result had its stderr redirected away | You read the command's stderr, or have seen it fail before |

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
- Piping (`| wc -l`) masks the exit code entirely, so even the rc=1 tell is gone —
  see *A pipe discards the command's exit code* below for the general case.

## A wrapped string defeats a source grep — the code is unchanged, the grep says fixed

A string literal split across source lines for line-length reasons exists
nowhere contiguously in the file, so grepping the *rendered* message finds
nothing — and that zero reads as "the text is gone, someone fixed it."

> Observed 2026-08 (loractl). Checking whether an error still blamed f16 range
> overflow unconditionally, `git grep -c 'exceeded f16'` returned nothing and was
> recorded as "reworded — task closable." The message was fully intact; the
> source wraps it as `"...an activation exceeded \` + `f16's range; try f32..."`,
> so the phrase spans two lines. A second claim was mis-cleared the same way in
> the same pass, and both were recovered only by the control test.

- **Grep a fragment that cannot straddle a wrap** — one distinctive word, or the
  symbol that owns the message (`check_step_loss`), never the whole sentence.
- **Then read the hit.** The search locates the text; the verdict comes from
  reading it.
- The control test in the section above catches this class. Run it on any
  negative that closes a task or reports something already fixed.

## A pipe discards the command's exit code — `| tail` reports success for a failed run

A shell pipeline exits with the status of its **last** command, so `<cmd> | tail`,
`| head`, `| grep`, `| wc -l` all throw away the status of the thing you ran. The
result is not merely lossy, it is confidently wrong: a failing build reports
success. This is the general case of the `| wc -l` note in the grep section above.

> Observed 2026-08 (loractl). `just test 2>&1 | tail -25` returned exit 0 and was
> written up as "suite green" — the 0 was `tail`'s. The 25-line window also showed
> only the trailing `cargo test --examples` invocation (four targets, 0 tests
> each) while the real results had scrolled past, so both halves of the report
> were wrong. It nearly gated a commit on an unverified suite. Re-run with a
> redirect: 384 passed across 79 targets, status from `just` itself.

- **Redirect, don't pipe**, whenever the status matters:
  `cmd > out.log 2>&1; echo "EXIT=$?"` — then read the file.
- `set -o pipefail` fixes the status but **not** the truncation, and it does not
  apply to a command the harness runs on your behalf.
- **A CI watch has the same shape**: `gh pr checks <n> --watch | tail` reports the
  watcher's status, not the checks'. Read the states back explicitly
  (`--json name,state`) before calling a PR green.

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

## Your own `2>/dev/null` turns a loud rejection into a clean negative

The section above is about a tool that stayed quiet. This one is its mirror, and
the difference is the whole point: **the tool did its job.** It rejected the
command, printed a diagnostic, and exited non-zero — and the caller's own
redirect threw all three away. No tool-side improvement reaches this: the
message was written and then discarded downstream of the tool.

```
# Wrong — gh pr diff takes no pathspec, and the rejection goes to /dev/null
gh pr diff 36 -- .env.example 2>/dev/null | grep -E "^[+-]"
      ← empty stdout, reads as "this PR does not touch that file"

# The same command with the redirect dropped
gh pr diff 36 -- .env.example
accepts at most 1 arg(s), received 2      ← rc=1, and it said so all along
```

Observed 2026-08 reviewing a PR that claimed `Closes #29`: the empty result was
one step from being reported as "the change was never made". The file was
`+34/-5`. The exit code was lost as well — a pipeline reports the status of its
**last** command, so `grep`'s status is what survived, not `gh`'s.

**The control test does not catch this class.** Re-running the same shape
against a file the PR definitely touches comes back empty too — the shape is
broken for every input, so the control agrees with the false negative and
confirms it. What breaks it open is dropping the redirect, not changing the
input.

- **Suppress stderr only on a command whose failure mode you have already seen.**
  `2>/dev/null` is a claim that you know what would have been printed. On a
  first-time shape — a new flag, a new subcommand, a line copied from
  elsewhere — it mutes the one channel that would say the command never ran.
- **Re-run without the redirect before believing a negative that gates an
  action.** One run, and the diagnostic is either there or it is not. Prefer
  keeping stderr and reading it (`2>&1`) over muting it while you are still
  learning a command's shape.
- **Correct forms for the case above**: `gh pr diff <N>` and filter the unified
  diff yourself, or `gh pr view <N> --json files` for per-file additions and
  deletions.

For the worktree-shell wedge, the vacuous path-scoped verification, the
`Workflow` `args` JSON-string trap, and the parallel-batch / agent fan-out
hazards, see [REFERENCE.md](REFERENCE.md).
