# AI Review — Cause 2: Turn-Ceiling Overrun

Detail for the second row of the five-causes table in [SKILL.md](../SKILL.md).

## Cause 2 — turn-ceiling overrun on a run that succeeded

Distinct from Cause 1: nothing died. The model returned a normal successful
result, and the *action wrapper* then failed the job because the turn count
exceeded `--max-turns`. The scan's own verdict is discarded along with it.

```sh
gh run view --job <job-id> -R <o>/<r> --log | grep -E '"is_error"|"subtype"|"num_turns"|exceeding the configured maximum'
```

```
"subtype": "success",
"is_error": false,
"num_turns": 53,
##[error]Claude reported a successful result after 53 turns, exceeding the configured maximum of 50
```

Nondeterministic in exactly the way Cause 1 is — same check, same tree,
different turn count. Do not read a pass on the next run as evidence a change
fixed anything.

> Evidence (2026-08-28, pal-mcp-server#87): `secrets-scan / scan` passed, then
> failed after a rebase that changed no scanned content, at `num_turns: 53`
> against a max of 50 with `permission_denials_count: 6` and no finding. It
> passed again on the next push. The diff was comment-only edits to
> `.env.example`; the scan had nothing to report either time.

The `permission_denials_count` interaction from Cause 3 applies here too: denied
tool calls get retried, and the retries are what push a scan over the ceiling.
So a high denial count is a cause of this failure, not a signal about the code.

### Where the turns went

The turn count says the budget ran out, not what spent it. The run's
`claude-execution-output.json` holds every tool call, so list them before
deciding which fix applies. The action writes the file to
`$RUNNER_TEMP/claude-execution-output.json` but does not upload it; the
workflow has to (see `github-actions-plugin:claude-code-github-workflows`
§ Denials are a count). With an uploaded artifact:

```sh
gh api repos/<o>/<r>/actions/runs/<run-id>/artifacts --jq '.artifacts[].name'
gh run download <run-id> -R <o>/<r> -n <artifact> -D exec
python3 - exec/claude-execution-output.json <<'EOF'
import json, sys
calls, n = {}, 0
for msg in json.load(open(sys.argv[1])):
    content = (msg.get("message") or {}).get("content")
    for block in content if isinstance(content, list) else []:
        if block.get("type") == "tool_use":
            calls[block["id"]] = (block["name"], json.dumps(block.get("input"))[:70])
        elif block.get("type") == "tool_result":
            name, arg = calls.get(block.get("tool_use_id"), ("?", ""))
            out = block.get("content")
            if isinstance(out, list):
                out = " ".join(x.get("text", "") for x in out if isinstance(x, dict))
            n += 1
            err = "ERR" if block.get("is_error") else "ok "
            print(f"{n:3} {err} {name:5} {arg} -> {str(out)[:60]!r}")
EOF
```

Read the result prefixes in sequence. Runs of denials, retries of the same
call with small variations, and calls that re-read a file already read are the
waste; the rest is the scan.

### Named waste: base-branch config restore

On a `pull_request` run, `anthropics/claude-code-action` treats the PR head as
untrusted and restores agent configuration from `origin/<base>` before Claude
starts: `.claude/`, `CLAUDE.md`, `CLAUDE.local.md`, `.mcp.json`, `.claude.json`,
`.gitmodules`, `.ripgreprc` and `.husky`. The PR's own copies go to
`.claude-pr/`. The action log says so:

```
Restoring .claude, .mcp.json, .claude.json, .gitmodules, .ripgreprc, CLAUDE.md, CLAUDE.local.md, .husky from origin/main (PR head is untrusted)
```

On a PR that edits any of those paths, `Read`, `Glob` and `Grep` see the base
versions. Files the PR adds look missing, files it deletes look present, and
`git status` shows the restored files as modified. An agent nobody warned spends
its budget reconciling the working tree with `HEAD`.

**The tell:** `Read` reports `File does not exist` for a path that
`git show HEAD:<path>` returns.

**The fix:** one prompt line naming the restored paths and where the PR's
versions are:

```yaml
prompt: |
  The action restored .claude/, CLAUDE.md, CLAUDE.local.md, .mcp.json,
  .claude.json, .gitmodules, .ripgreprc and .husky from the base branch, so the
  working tree does not show this PR's versions of them. Read the PR's copies
  with `git show HEAD:<path>` or under .claude-pr/, and search them with
  `git grep <pattern> HEAD -- <path>`.
```

Grant those commands in `--allowedTools` (`Bash(git show *)`,
`Bash(git grep *)`); a prompt that points at a denied command trades one kind
of waste for another.

**Pitfall: `grep -r <pattern> HEAD` is not a search of the commit.** It searches
a *directory* named `HEAD`, which does not exist, so it prints nothing on stdout.
An agent reads that empty result as a clean check. `git grep <pattern> HEAD`
is the command that searches the commit.

> Evidence (ForumViriumHelsinki/infrastructure run 36528848302, PR #2479, which
> mostly edits `.claude/rules/`): the docs validator ended `subtype: success`,
> `is_error: false`, `num_turns: 41` against `--max-turns 40`, with the report
> written and published. Of 40 tool calls, about 14 went to finding that `Read`
> disagreed with `HEAD` and switching to `git show HEAD:`, four to allowlist
> denials of compound Bash commands, and two to `grep -r … HEAD` returning an
> empty result that looked clean. Fixed in ForumViriumHelsinki/infrastructure#2480.

### Fix it upstream

Not in your PR. Three options, in rising order of how much they change:

1. **Raise `--max-turns`.** Cheapest, and right when the listing shows the scan
   itself needed the turns.
2. **Remove the waste.** Grant the tool the scan keeps being denied, or add the
   restore prompt line when the listing shows config-restore churn.
3. **Stop the turn count deciding the job's colour.** Set
   `continue-on-error: true` on the Claude step, and add a later step that fails
   the job only when the deliverable is missing:

   ```yaml
   - id: review
     uses: anthropics/claude-code-action@v1
     continue-on-error: true
     with:
       prompt: |
         ...write the report to review-report.md...

   - name: Require the report
     if: always()
     env:
       REPORT_FILE: review-report.md
       CLAUDE_OUTCOME: ${{ steps.review.outcome }}
     run: |
       [ -s "$REPORT_FILE" ] || {
         echo "::error::no report produced (Claude step outcome: $CLAUDE_OUTCOME)"
         exit 1
       }
   ```

   A report written incrementally can survive a run that died mid-flight
   (Cause 1), so have the agent write it once, at the end.

Re-running just re-rolls the count.
