---
created: 2026-04-24
modified: 2026-04-24
reviewed: 2026-04-24
---

# Parallel-Safe Queries

Commands that **exit 1 on empty result** silently cancel every sibling tool
call in the same parallel Bash batch. The failure is invisible — no error
message, no partial results, just missing tool outputs.

## The Rule

> In a parallel Bash batch, always use the variant of a query command that
> emits empty-but-valid output and exits 0 — not the variant that exits 1
> when there is "nothing to report."

Parallel batches die at the first non-zero exit. A zero-result `task list`
or `gh pr list` looks identical to a failure, and the harness reaps the
whole batch.

## The Pattern

| Prefer | Over | Why the alternative fails in parallel |
|--------|------|---------------------------------------|
| `task <filter> export \| jq …` | `task <filter> list` | `list` exits 1 when the filter matches nothing |
| `gh pr list --json … \| jq …` | `gh pr list` with no matches | Exits 1 on empty; also sensitive to rate limits |
| `gh issue list --json … \| jq …` | `gh issue list` when filter may be empty | Same class of empty-result exit code |
| `rg -q pattern; echo $?` (explicit) | `rg pattern` (bare) | `rg` exits 1 by design when no matches |
| `grep -c … \|\| echo 0` | bare `grep -c` on a possibly-empty input | `grep` exits 1 on no match |
| `find <path> -name …` | `ls <glob>` | `ls` fails on missing glob expansion |

The common fix: pick the machine-readable variant (`--json`, `export`,
`--output=json`) and post-process with `jq`. Empty JSON (`[]` or `{}`) is
exit-0 and valid input for `jq`.

## Verification

When authoring a skill that runs queries in parallel, run the query
against an empty state and check the exit code:

```bash
# Should exit 0 even with no matching tasks
task status:pending export | jq '.[]'
echo "exit: $?"
```

If the exit code is non-zero, the command will cancel siblings. Switch
to the machine-readable variant.

## Why This Lives Here (for now)

This rule is broadly applicable across many plugins (taskwarrior, gh,
ripgrep, grep). It lives as a claude-plugins project rule first so the
claude-plugins skills that run queries in parallel can cite it while the
pattern is settled. Promote to a shared-rules section of a plugin if it
earns dedicated reference from more than a handful of skills.

## Related

- `.claude/rules/friction/2026-W16-frictions.md` — cancelled-parallel-call
  friction pattern; the same class of failure manifests when `find` is
  used instead of Glob
- `agent-patterns-plugin:parallel-agent-dispatch` — the broader
  orchestrator contract that this rule slots into
