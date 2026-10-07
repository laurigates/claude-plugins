---
created: 2026-01-30
modified: 2026-09-26
reviewed: 2026-09-02
allowed-tools: Bash(gh pr checks *), Bash(gh pr view *), Bash(gh pr diff *), Bash(gh run view *), Bash(gh run list *), Bash(gh api *), Bash(gh repo view *), Bash(gh issue create *), Bash(git status *), Bash(git diff *), Bash(git log *), Bash(git add *), Bash(git commit *), Bash(git push *), Bash(git switch *), Bash(git pull *), Bash(git fetch *), Bash(pre-commit *), Bash(npm run *), Bash(uv run *), Bash(bash *), Read, Edit, Write, Grep, Glob, Task, mcp__github__pull_request_read, mcp__github__add_reply_to_pull_request_comment, mcp__github__pull_request_review_write, mcp__github__issue_write
args: "[pr-number] [--commit] [--push] [--all] [--dry-run] [--limit N] [--include-automation]"
argument-hint: "[pr-number | --all] [--commit] [--push] [--dry-run] [--limit N] [--include-automation]"
disable-model-invocation: true
description: "Address PR review comments and resolve threads. Use when CHANGES_REQUESTED is set, working through unresolved review threads, or replying to reviewer feedback."
name: git-pr-feedback
agent: general-purpose
---

## Context

- Repo: !`git remote -v`
- Current branch: !`git branch --show-current`
- Git status: !`git status --porcelain=v2 --branch`

## Parameters

Parse these parameters from the command (all optional):

| Parameter | Description |
|-----------|-------------|
| `$1` | PR number (if omitted, use PR of current branch; if no such PR, list actionable PRs). Mutually exclusive with `--all`. |
| `--commit` | Create commit(s) after addressing feedback. |
| `--push` | Push changes after committing (implies `--commit`). |
| `--all` | Address feedback on every actionable open PR. Dispatches one subagent per PR in an isolated worktree; the orchestrator pushes, replies, and resolves. Implies `--commit --push` unless `--dry-run` is set. Mutually exclusive with `$1`. |
| `--dry-run` | With `--all`, print the dispatch plan and stop — no subagents spawned, no commits, no pushes. Ignored without `--all`. |
| `--limit N` | Maximum concurrent subagents under `--all` (default `3`). Use a small number to stay under GitHub rate limits and avoid API rate-limit cascades from many concurrent subagents — the hazard bites 1M-context sessions, which on Fable is every session, since 1M is its default window (see [`skill-fork-context.md`](../../../.claude/rules/skill-fork-context.md)). |
| `--include-automation` | With `--all`, also surface automation-authored PRs (release-please, dependabot, renovate, `*[bot]`, `*-bot`). Excluded by default because they carry no human review feedback and their CI failures are resolved by automation re-running, not hand edits. |

**Mode selection**:

| Mode | Triggered when | Flow |
|------|----------------|------|
| Single-PR | No `--all` | Steps 1–7 below operate on one PR. |
| Multi-PR | `--all` is passed | **Step 1A** dispatches subagents; the orchestrator finalises (push, reply, resolve, re-request) and writes a combined summary. Skip Steps 1–6. |

If both `$1` and `--all` are given, error and stop with: `--all is mutually exclusive with a PR number argument.`

## When to Use This Skill

| Use this skill when... | Use another skill instead when... |
|------------------------|----------------------------------|
| A PR has reviewer comments to address | CI checks are failing with no review comments -> use `git-fix-pr` |
| You need to systematically work through review feedback | You're creating a new PR -> use `git-commit-push-pr` |
| A reviewer has requested changes | You want to understand PR workflow patterns -> use `git-branch-pr-workflow` |

## Your Task

Review PR workflow results and reviewer comments, then address substantive feedback.

For feedback categorization, decision trees, commit format, and report templates, see [REFERENCE.md](REFERENCE.md).

---

### Step 1: Determine PR and Gather All Data

> If `--all` is set, **skip this step** and jump to **Step 1A: Multi-PR Mode** below.

1. **Parse owner/repo** from the git remote URL.

2. **Resolve the PR number** in this order:
   1. If `$1` was provided, use it.
   2. Otherwise, try the PR for the current branch:
      ```bash
      gh pr view --json number -q '.number'
      ```
   3. If step 2 fails (no PR for the branch) **or** the command is on a detached/default branch, fall back to listing actionable PRs:
      ```bash
      bash ${CLAUDE_SKILL_DIR}/scripts/list-actionable-prs.sh <owner> <repo>
      ```
      The script emits a JSON array of open, non-draft PRs that have unresolved review threads, failing/errored CI, or `CHANGES_REQUESTED`. Handle the result as follows:

      | Result | Action |
      |--------|--------|
      | Empty array | Report "No PRs need attention." and stop. |
      | One entry | Use that PR number and continue. |
      | Multiple entries | Print a compact table (number, author, CI, unresolved, reviewDecision, title) ordered as returned, then stop and instruct the user to re-run `/git:pr-feedback <number>`. Do **not** guess which PR they meant. |

3. **Switch to PR branch** if not already on it:
   ```bash
   gh pr view $PR --json headRefName -q '.headRefName'
   git switch <branch-name>
   git pull origin <branch-name>
   ```

4. **Fetch ALL PR data** using the bundled script (single GraphQL query):
   ```bash
   bash ${CLAUDE_SKILL_DIR}/scripts/fetch-pr-data.sh <owner> <repo> <pr-number>
   ```

5. **For failed checks only**, fetch detailed logs:
   ```bash
   gh run view $RUN_ID --log-failed
   ```

| Check Status | Action |
|--------------|--------|
| All passing | Skip to Step 2 |
| Failed CI | Get logs with `gh run view`, may need fixes |
| Pending | Note status, focus on comments |

If the GraphQL query fails with a rate limit error, wait 60 seconds and retry once.

---

### Step 1A: Multi-PR Mode (--all)

Reached only when `--all` is passed. Follow [references/multi-pr-mode.md](references/multi-pr-mode.md): list actionable PRs, honour `--dry-run`, dispatch one worktree subagent per PR capped at `--limit N` (subagents commit but never push), then the orchestrator alone pushes, replies, resolves and re-requests review, and handles blocked subagents per its failure table. Then skip Steps 2–6 and go to Step 7 with a combined summary.

---

### Step 2: Analyze Feedback

Categorize all comments from the GraphQL response (see [REFERENCE.md](REFERENCE.md) for category definitions):

1. Skip any thread where `isResolved: true` or `isOutdated: true` — already handled.
2. Categorize each remaining comment as Blocking, Substantive, Suggestion, Question, or Nitpick.
3. For each actionable comment, capture: thread `id`, top-level comment `databaseId`, file, line, scope, and whether the body contains a ` ```suggestion ` block.
4. Track one item per actionable thread, including the thread `id` and `databaseId` so Steps 3–5 can reply and resolve — via `TodoWrite` when the session has the task tools (see `.claude/rules/agentic-permissions.md` § Task-tool availability), otherwise as a checklist you keep in the response.

---

### Step 3: Address Feedback

Verify every claim — especially from an automated reviewer — before acting, then decide per thread: accept or adapt a suggestion, fix, mark **Refuted** (reply with evidence, no code change), answer, or defer. For the verification discipline and the per-comment-shape decision table, see [references/addressing-feedback.md](references/addressing-feedback.md). Do **not** resolve threads yet — that happens after the commit.

### Step 3a: File follow-up issues for out-of-scope feedback

For each out-of-scope or deferred thread, file a follow-up issue and capture its number for Step 6's `Deferred to #<n>` reply. For the issue shape and when to skip or ask first, see [references/addressing-feedback.md](references/addressing-feedback.md).

---

### Step 4: Commit Changes (if --commit or --push)

Group related fixes into logical commits — one commit per logical group of accepted suggestions, not one per suggestion. See [REFERENCE.md](REFERENCE.md) for commit message format.

For any commit that contains an **accepted (or adapted) suggestion**, append a `Co-authored-by:` trailer for each unique suggester. This mirrors GitHub's "Commit suggestion" / "Add suggestion to batch" behaviour, which credits the suggester as co-author. See [REFERENCE.md](REFERENCE.md) "Co-author Attribution" for how to construct the trailer line and resolve the suggester's email.

Run pre-commit hooks if configured, then stage any formatter changes.

### Step 5: Push Changes (if --push)

```bash
git push origin HEAD
```

### Step 5a: Re-request Review (if --push)

After a push addressing substantive feedback, re-request review from `CHANGES_REQUESTED` reviewers and authors of resolved threads. For reviewer selection and the `gh api` call, see [references/reply-and-resolve.md](references/reply-and-resolve.md).

### Step 6: Reply and Resolve Threads

Reply to every actionable thread, then **resolve it by default** in the same turn (GraphQL `resolveReviewThread`); leave it open only for the listed exceptions. Without `--push`, reply but defer resolution and note it in Step 7. For reply templates, resolve conditions, and the leave-open exceptions, see [references/reply-and-resolve.md](references/reply-and-resolve.md).

### Step 7: Summary Report

Provide a summary table of feedback addressed, replies posted, threads resolved, and next steps. See [REFERENCE.md](REFERENCE.md) for the report template.

---

## Workflow harness (template)

`workflows/pr-feedback-wave.workflow.js` ships beside this skill and covers the
`--all` path only. **It is a TEMPLATE to adapt, not a script to run verbatim.**
Read it, then rewrite it for the work in front of you.

**Adapt freely:** the per-PR and synthesis agent prompts, the default wave
width, the `--include-automation` and `--dry-run` handling, the ordering
heuristic inside the finalise plan, and any forge-specific commands.

**Preserve across any adaptation:** (a) the loop bound comes from
[`scripts/list-actionable-prs.sh`](scripts/list-actionable-prs.sh)'s JSON array,
passed in as `args.prs`, never from a prose "for each open PR" — and the
concurrency ceiling stays the caller's `--limit N`, because a harness that picks
its own width silently overrides the flag that exists to dodge the burst rate
limit; (b) `PR_RESULT_SCHEMA` is Step 1A.6's return contract made **enforced**
rather than requested — the closed `fix|accept|adapt|defer|answer|decline`
action enum and the boolean `resolve` make a vague "handled it" structurally
impossible, and a null agent becomes an explicit `PARSE_ERROR` row instead of a
silent pass; (c) the Finalise plan is a barrier — push, reply, resolve and
re-request all draw on one GitHub rate-limit pool against one remote, so the
ORDER is a cross-PR fact no single per-PR agent could know, and Step 7's rollup
has to see every PR at once. Two consequences of (c) that are equally
non-negotiable: the fanned-out agents **commit but never push**, and each
result's status is a pure function of the returned contract (null /
`blockers[]` / `commits[]`), never a judgement an agent re-derives.

**Agent budget:** 1 + PRs — one agent per actionable PR plus one finalise-plan
agent. The wave width bounds concurrency, not the total. The scale guard asks before every run, because the list comes from the
caller at runtime.

**Skip the harness when:** exactly one PR is actionable — the modal case, which
is the single-PR path in Steps 1–7 — or `--dry-run` is set; that is a linear
pass and the harness is pure overhead (the template aborts below two). The
steps above remain the authoritative description of *what* each stage must
produce; the harness only fixes *how* the work is split.

Two clauses this template carries. Both are unconditional here — every
fanned-out unit runs in its own worktree, and this skill's entire output is a
forge mutation:

> Never `Workflow({resumeFromRunId})` to retry a few failed worktree agents — a
> resume re-runs agents that already succeeded and opens duplicate PRs (#1868).
> Re-dispatch the failed units fresh and sequentially after checking
> `gh pr list --head <branch> --state all --json number,state`.

> Push, PR creation, replies and thread resolution happen **only** in the single
> sequential finalise stage, never inside a fanned-out agent. Here that stage is
> Step 1A.7, which the harness does not perform: it returns an ordered
> `finalisePlan` for the orchestrator to apply one PR at a time.

## Agentic Optimizations

See [references/commands.md](references/commands.md) for the command and tool for each step (fetch, list actionable PRs, dispatch, reply, resolve, re-request review, file a follow-up issue).

## See Also

- **/git:fix-pr** - Focus on CI failures specifically
- **gh-cli-agentic** skill - Optimized GitHub CLI patterns
- **git-branch-pr-workflow** skill - PR workflow patterns
