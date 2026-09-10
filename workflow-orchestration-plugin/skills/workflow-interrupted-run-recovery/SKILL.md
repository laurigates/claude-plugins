---
name: workflow-interrupted-run-recovery
description: Recover a Workflow run killed mid-flight: salvage killed agents' worktrees, resume without duplicating PRs already opened. Use when a run reports agents_error after a session limit, kill, or crash.
user-invocable: false
allowed-tools: Bash, Read, Glob, Grep
created: 2026-09-08
modified: 2026-09-08
reviewed: 2026-09-08
---

# Recovering an Interrupted Workflow Run

A `Workflow` run that dies partway leaves the world in two states at once.
Agents that **completed** have already had their effects: branches pushed, PRs
opened, issues filed. Agents that were **killed** left a git worktree holding
uncommitted work. Neither is visible in the run's return value, which reports
only that some agents errored.

The two mistakes both follow from treating the run as atomic:

- Re-running it as-authored, and **duplicating** the PRs the completed agents
  opened.
- Re-running the killed agents from scratch, and **discarding** work that is
  sitting on disk.

> Observed 2026-09-07 (`ForumViriumHelsinki/infrastructure` #2305): a 13-agent
> run hit a session limit with 6 done and 7 killed. Two of the six had opened
> PRs. One of the killed agents had written 20 source files, a test suite and a
> golden-vector fixture into its worktree and was killed before its first
> commit. A naive resume would have duplicated two PRs and thrown away the 20
> files.

## 1. Read the journal before deciding anything

The run's summarized return value truncates. The journal has one line per agent
with its full return:

```bash
cd <transcriptDir>
python3 -c "
import json
for l in open('journal.jsonl'):
    d = json.loads(l)
    print(d.get('type'), d.get('key', '')[:24])
"
```

Then dump each `result` to a file and read them — a completed agent's return
usually names the PR it opened and the contract later stages depend on. Do not
assume a cached result is non-empty; check.

## 2. Inventory the real-world side effects

Everything below is state the workflow cannot roll back:

```bash
gh pr list --state open --json number,title,headRefName,isDraft
gh issue list --state open --limit 20 --json number,title
git fetch origin && git branch -r --list 'origin/<your-prefix>/*'
```

Anything already here must **not** be produced again.

## 3. Salvage the killed agents' worktrees

Worktrees are removed only if unchanged, so a killed agent's survives with its
work in it — usually untracked, because it died before committing:

```bash
git worktree list                                  # find <repo>/.claude/worktrees/wf_<runid>-N
git -C <worktree> status --short                   # '??' entries are the salvage
git -C <worktree> log --oneline origin/main..HEAD  # empty = it never committed
```

Copy those files into the new run's worktree rather than regenerating them, and
brief the new agent to **review them critically** rather than trust them — they
were written by an agent that never got to run its own gates, and any
corrections discovered after it died will be missing.

## 4. Prefer a new, narrowed script over `resumeFromRunId`

`resumeFromRunId` replays the longest **unchanged prefix** of `agent()` calls.
That is the trap: editing one prompt invalidates that call *and everything after
it*, so agents that already opened PRs re-run and open them again. Sibling calls
inside the same `parallel()` are not individually addressable either.

Resume is right when the script is genuinely unchanged and no completed agent
had an external side effect. Otherwise write a **new script containing only the
work that did not happen**, and hard-code the completed agents' outputs as
inputs:

```js
// PRs B and D are already open; do not re-run their agents.
const B_URL = 'https://github.com/<org>/<repo>/pull/2327'
const C_PROMPT = `${COMMON}
PR B is open as ${B_URL}. Do not touch its files.
The contract from the agent that completed: ${savedContract}
...`
```

Carry the verified findings forward as **files on disk**, referenced by absolute
path in the new prompts, rather than pasting them into the script. It keeps the
orchestrator's context free and gives the new agents the full detail:

```js
const FACTS = '/abs/path/to/repo/tmp/<run>/facts'
// ...
`READ FIRST, IN FULL: ${FACTS}/chart.md`
```

Note that a gitignored scratch directory does **not** appear in a fresh
worktree, so reference it by absolute path into the main checkout, or add it to
`.worktreeinclude`.

## 5. Free the branches before re-running

Git refuses to check out a branch that is live in another worktree, so a fresh
`isolation: "worktree"` agent cannot take a branch a stale worktree still holds:

```
fatal: 'feat/x' is already checked out at '.../worktrees/agent-...'
```

Remove the stale worktrees first — after salvaging anything in them:

```bash
git worktree remove --force <repo>/.claude/worktrees/wf_<runid>-N
git worktree prune
git worktree list | grep -E '<your-branch-pattern>' || echo "branches free"
```

## 6. Re-verify the parts that were mid-flight

An agent killed between "wrote the files" and "ran the gates" leaves work whose
gates were never run, and the resumed agent inherits the files without
inheriting that knowledge. State it in the brief, and make the new run re-run
every gate rather than trusting the salvaged tree.

## Checklist

1. Read `journal.jsonl` — what actually returned, and what it returned.
2. `gh pr list` / `gh issue list` / `git branch -r` — what already exists.
3. `git worktree list` + `status --short` — what is salvageable.
4. Write a narrowed script for the remaining work; hard-code completed outputs.
5. Remove the stale worktrees so the branches are free.
6. Brief the new agents that salvaged files are unverified.

## Related

- `workflow-checkpoint-refactor` — surviving *your own* context limit during a
  long refactor, with checkpoint files. This skill covers a `Workflow` **run**
  being killed, where the state to recover is other agents' worktrees and their
  already-landed side effects.
- `workflow-preflight` — checking for an existing PR before starting work; the
  same question, asked before the first run rather than after a failed one.
- `git-plugin:git-coworker-check` — a live peer in a shared checkout, which
  produces similar-looking "my work vanished" symptoms from a different cause.
