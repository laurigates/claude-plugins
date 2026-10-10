# AI Review — Cause 5: Bot-Actor Refusal After Approval

Detail for the bot-actor row of the five-causes table in [SKILL.md](../SKILL.md).

## Cause 5 — the action refuses a run whose actor is a bot

Claude never started. `anthropics/claude-code-action` checks the run's `actor`
before it launches the agent, and fails the step when that actor is a bot not
named in `allowed_bots`:

```
Action failed with error: Workflow initiated by non-human actor: github-actions (type: Bot). Add bot to allowed_bots list or use '*' to allow all bots.
```

None of the other four rows can match it, because every one of them reads the
result of a run that happened. This one has **no execution file, no `is_error`,
no `subtype` and no `num_turns`**. A triage that greps for those finds nothing
and is tempted to call the red unexplained. The `subtype` + `is_error`
discriminator in SKILL.md therefore applies only once Claude ran: rule out the
`non-human actor` line before reading it.

### The signature

| Field | Value |
|---|---|
| Step log | `non-human actor: <name> (type: Bot)` |
| `run_attempt` | 2 or more after a `github.token` push that a maintainer approved; 1 for a PR a bot authored (Renovate, Dependabot, release-please) |
| `actor` vs `triggering_actor` | `github.token`-push case: different, `actor` is the bot and `triggering_actor` is the maintainer who approved; bot-authored PR: the same bot |
| Execution file / `num_turns` | absent |

The `non-human actor` log line is the discriminator on its own. The
`run_attempt` and `actor` rows only describe the `github.token`-push variant, so
an attempt-1 run with `actor` equal to `triggering_actor` does not rule Cause 5
out.

```sh
gh run view <run-id> -R <o>/<r> --json attempt,event,headSha \
  --jq '{attempt, event, headSha}'
gh api repos/<o>/<r>/actions/runs/<run-id> \
  --jq '{run_attempt, actor: .actor.login, triggering_actor: .triggering_actor.login}'
```

### The mechanism

1. A workflow pushes to the PR branch with `github.token`, for example an
   auto-fix workflow whose caller passed no PAT.
2. The `pull_request` run that push triggers has `github-actions[bot]` as its
   `actor`. GitHub holds it, and attempt 1 ends `action_required`.
3. A maintainer approves it. Attempt 2 keeps `actor=github-actions[bot]`;
   only `triggering_actor` becomes the maintainer. The action reads `actor`,
   sees a bot, and refuses.

Approving or re-running again does not help: a re-run replays the original
event, so `actor` stays the bot. `github-actions-plugin:multirepo-ci-cd` covers
the same replay mechanic for Renovate and release-please PRs.

This is the flip side of an actor gate going blind. When an agent pushes under
a human account, a `github.actor` gate in the workflow admits everything; when
a workflow pushes under `github.token`, the action's own actor gate fires on
every review of that commit.

### The fix

Either one closes it; pick by who should own the push:

- **Admit the bot.** Add `allowed_bots: "github-actions"` to the
  claude-code-action step. The action lowercases both sides and strips a
  trailing `[bot]` before comparing, so `github-actions` and
  `github-actions[bot]` both match.
- **Change who pushes.** Have the pushing workflow use a PAT or a GitHub App
  token. The push is then attributed to that account rather than
  `github-actions[bot]`, and an App token also triggers CI without the
  `action_required` hold.

The `allowed_bots` input is covered in
`github-actions-plugin:claude-code-github-workflows` § Bots are blocked by
default.

### Counting it across a repo

To sort a repo's failed review runs, scan each failed log for the refusal line:

```sh
for id in $(gh run list -R <o>/<r> --workflow <file>.yml --status failure -L 50 --json databaseId --jq '.[].databaseId'); do
  gh run view "$id" -R <o>/<r> --log-failed 2>/dev/null \
    | grep -o 'non-human actor: [a-z-]*' | head -1 | sed "s/^/$id /"
done
```

Every hit is a run that said nothing about the code; subtract them before
reading any of the other four causes' rates.

> Evidence (2026-09-25, ForumViriumHelsinki/thelma): over 90 days, 10 of 21
> failed a11y reviews and 1 of 8 failed code-smell reviews were this refusal.
> Every one was `run_attempt=2` on a PR head commit written by `claude[bot]`
> and pushed by an auto-fix workflow with `github.token` (runs 36188462614,
> 36188435649 and 36188421065). Fixed in ForumViriumHelsinki/thelma#1641 by
> adding `github-actions` to `allowed_bots`.
