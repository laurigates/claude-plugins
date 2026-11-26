# session-end — Handoff prompt

The handoff prompt is the last thing session-end prints: a self-contained
prompt the user pastes into a new session to continue the work. It is written
in the same run, while the conversation is still in context and the prompt
cache is warm. Asking for it later means a cold cache, and possibly a session
already compacted into a summary that has lost the detail the prompt needs.

## Rules

- **Every run.** Emit it even when no pass qualified and when the Step 4
  question was skipped. A session with nothing to file can still have work to
  continue. When the session finished everything, say so in `Current state`
  and keep `Next steps` to what remains, or `none`.
- **Last in the final message**, after the Step 5 report, as one fenced
  `text` block so it copies cleanly. Nothing follows the fence.
- **Self-contained.** The reader is a new session with none of this
  conversation. Write full paths, repo names (`owner/repo`), branch names,
  PR and issue numbers, and task UUIDs. No "as above", "the PR", or session
  shorthand.
- **Facts from tool results.** Branch, PR and task state come from the Step 1
  survey and the Step 3/4 results, not from memory. Mark anything not checked
  as unverified.
- **Reflect this run.** Items Step 3 filed or closed appear as done; Ask-lane
  items the user declined or left unanswered appear under `Open items`.
- **No secrets.** Tokens, credentials and private hostnames stay out; name the
  file or environment variable that holds them instead.
- **Short.** Aim for under 40 lines. Omit a section that would be empty,
  except `Goal` and `Next steps`.

## Template

```text
Continue work from a previous session.

Goal: <one or two sentences: what the work is for, in the user's terms>

Current state: <what is done and what is in progress, as of this session's end>

Repos and branches:
- <owner/repo> @ <branch> (<clean | N uncommitted files | N unpushed commits>)

PRs and issues:
- <owner/repo>#<n> <title> — <open/draft/merged, CI state, review state>

Key files:
- <path> — <why it matters>

Decisions made:
- <decision> — <reason, and who decided>

Open items:
- <unresolved question, failing check, declined or unanswered Ask-lane item>

Next steps:
1. <first concrete action, with the command or file to start from>
2. <...>

Start by verifying the state above (git status, the PRs listed) before acting on it.
```

The closing line asks the new session to re-check the state, because branches
and PRs can move between sessions.
