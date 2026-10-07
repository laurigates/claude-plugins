# Tool Result Traps — Search and Exit-Status Traps

Moved verbatim from [SKILL.md](../SKILL.md). Open when a search came back empty or
partial, or a piped command reported success, and that result is about to gate an
action.

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
