# Tool Result Traps — A Rejected Flag Looks Like "No Results"

Moved verbatim from [SKILL.md](../SKILL.md). Open when a `cmd … | jq/grep`
pipeline returned nothing, or a mutating `gh`/`git` call printed nothing, and that
is about to be reported as a result or as done.

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
