# AI Review — Cause 2: Turn-Ceiling Overrun

Detail for the second row of the four-causes table in [SKILL.md](../SKILL.md).

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

**Fix it upstream**, not in your PR — raise `--max-turns`, or grant the tool the
scan keeps being denied. Re-running just re-rolls the count.
