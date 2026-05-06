# git-pr-feedback Reference

## Feedback Categories

| Category | Description | Priority |
|----------|-------------|----------|
| **Blocking** | "Request changes" reviews, critical bugs | Must address |
| **Substantive** | Code improvements, logic issues, missing tests | Should address |
| **Suggestions** | Style preferences, optional enhancements | Consider |
| **Questions** | Clarification requests | Respond inline |
| **Nitpicks** | Minor style/formatting | Low priority |
| **Resolved** | Already addressed or outdated | Skip |

## Decision Tree: Handling Different Feedback Types

```
Is the thread isResolved or isOutdated?
├─ Yes → Skip
└─ No → Is it a "Request Changes" review?
         ├─ Yes → Must address all blocking concerns before resolving any thread
         └─ No → Is it an inline code comment?
                  ├─ Yes → Does the body contain a ```suggestion block?
                  │        ├─ Yes, fix is correct → Accept the suggestion verbatim
                  │        ├─ Yes, fix needs adjustment → Apply a variant; explain in reply
                  │        └─ No → Analyze and implement best fix
                  └─ No → Is it a general comment/question?
                           ├─ Question → Reply inline; resolve only after answering
                           └─ Statement → Evaluate importance; reply if action taken
```

## Accepting Suggestions

GitHub review comments can embed a code-block proposal that replaces the lines the comment is anchored to:

````
```suggestion
new line of code here
another new line
```
````

**To accept**: Replace the targeted lines (`comment.line` through `comment.originalLine` if multi-line) in `comment.path` with the exact contents between the suggestion fences. Use `Edit` with the original lines (visible in `comment.diffHunk`) as `old_string` and the suggestion body as `new_string`.

**Rules**:
- Preserve indentation **as written in the suggestion block** — GitHub renders the block with absolute indentation.
- A suggestion may span multiple lines; replace the entire range, not just the anchor line.
- If the suggestion conflicts with another reviewer's request or with intent established elsewhere in the PR, apply a variant and explain in the reply.
- After applying, include the file in the next commit so the reply can reference the resolving SHA.

## Reply Templates

Keep replies concise. Use these templates with `mcp__github__add_reply_to_pull_request_comment` (the `commentId` is the top-level `databaseId` of the thread, an integer).

| Situation | Template |
|-----------|----------|
| Suggestion accepted as-is | `Accepted in <sha>.` |
| Suggestion adapted | `Applied a variant in <sha>: <one-line reason>.` |
| Code change made (no suggestion) | `Fixed in <sha> — <one-line summary>.` |
| Question answered | `<direct answer>. <optional code/file reference>.` |
| Deferred to follow-up | `Deferred to #<issue> — <reason>.` |
| Declined nitpick | `Leaving as-is: <reason>. Happy to revisit if you feel strongly.` |
| Partial fix | `Partially addressed in <sha>: <what was done>. <what remains>.` |

## Resolution Criteria

Resolve a thread with `mcp__github__resolve_review_thread` (threadId is the `PRRT_…` GraphQL node ID) when **all** of these hold:

- [ ] The reviewer's concern is fully addressed by a pushed commit, OR a question has been answered, OR a nitpick was explicitly declined with reasoning.
- [ ] No follow-up question to the reviewer is pending in your reply.
- [ ] The reviewer has not asked for the thread to remain open.
- [ ] You authored or own-pushed the change (or the user explicitly approved resolving on a PR you don't own).

Leave the thread open when:

- [ ] Your reply asks the reviewer something.
- [ ] The fix is partial or deferred.
- [ ] You disagree without making a change — let the reviewer decide.
- [ ] No commit has been pushed yet (resolution should reference a SHA).

## Commit Message Format

Group related fixes into logical commits — typically one commit per logical group of accepted suggestions, not one per individual suggestion:

```bash
git add <files-for-fix-1>
git commit -m "fix: address review feedback - <specific change>"
```

For multi-fix commits, list each change and append a `Co-authored-by:` trailer per unique suggester (see "Co-author Attribution" below):

```
fix: address PR review feedback

- <Change 1 description>
- <Change 2 description>

Co-authored-by: Octo Cat <octocat@users.noreply.github.com>
Co-authored-by: Mona Lisa <mona@example.com>
```

Run pre-commit hooks if configured:

```bash
pre-commit run --all-files
git add -u  # Stage any formatter changes
```

## Co-author Attribution

When you apply a `\`\`\`suggestion` block — verbatim or as an adapted variant — the suggester should be credited as a commit co-author. GitHub's "Commit suggestion" UI does this automatically; when applying suggestions through file edits we have to add the trailer ourselves.

**Trailer format** (one per unique suggester, blank line before the trailer block):

```
Co-authored-by: <Name> <email>
```

**Resolving the email**:

| Source available in PR data | Use |
|----------------------------|-----|
| Comment author has `User.email` set publicly | `<author.name> <author.email>` |
| Public email not set, but `databaseId` available | `<login> <id>+<login>@users.noreply.github.com` |
| Only `login` available | `<login> <login>@users.noreply.github.com` (legacy form, still accepted by GitHub) |

The `<id>+<login>@users.noreply.github.com` form is GitHub's privacy-preserving address; it always links the contribution to the account.

**Rules**:

- One `Co-authored-by:` trailer per **unique** suggester per commit. If two suggestions from the same reviewer land in the same commit, do not duplicate the trailer.
- Adapted variants count: the suggester gave the seed even if the final code differs. Credit them.
- Multi-author commits: list trailers in the order suggestions were authored on the PR.
- Verify locally with `git log -1 --format='%(trailers:key=Co-authored-by)'` before pushing.

## Re-request Review

After pushing changes that address substantive feedback, ask the affected reviewers to re-review. This mirrors the **sync icon** in the GitHub Conversation tab.

**When to re-request**:

| Situation | Re-request? |
|-----------|-------------|
| Reviewer left `CHANGES_REQUESTED` and concerns are now addressed | Yes |
| Reviewer left inline threads that were resolved this push | Yes |
| Only nitpicks were declined | No (no new code to review) |
| Only a question was answered (no code change) | No |
| Reviewer is the PR author (self-review) | No |

**Command**:

```bash
gh api -X POST \
  /repos/<owner>/<repo>/pulls/<pr>/requested_reviewers \
  -f 'reviewers[]=<login1>' \
  -f 'reviewers[]=<login2>'
```

**Failure modes**:

- HTTP 422 "Reviews may only be requested from collaborators" — the reviewer is an outside contributor who reviewed by being @-mentioned. Note in the summary and skip.
- HTTP 422 "Review cannot be requested from pull request author" — filter the PR author out of the list before calling.

## Out-of-Scope Feedback → Follow-up Issue

When a reviewer raises a valid concern that is genuinely out of scope for the current PR, file a follow-up issue rather than expanding the PR's diff.

**Decision**:

| Comment shape | Action |
|---------------|--------|
| Bug or improvement clearly outside the PR's stated goal | File issue, defer in reply |
| Refactor opportunity adjacent to changed code | File issue, defer (or implement if trivial and the user agrees) |
| Concern that contradicts the PR's purpose | Discuss inline; do not file an issue until resolved |
| Suggestion the user explicitly rejects | Decline inline; do not file an issue |

**Issue body template**:

```markdown
Raised in <PR-URL>#discussion_r<comment-id> by @<reviewer>.

> <quoted reviewer comment, prefixed with `> `>

<one-line context: what file/area this concerns and why we're deferring>
```

**Reply on the original thread** (after issue is filed):

```
Deferred to #<issue> — <one-line reason>.
```

Then resolve the thread (the deferral itself is the resolution).

## Multi-PR Subagent Prompt

Used by Step 1A when `--all` is passed. The orchestrator dispatches one subagent per actionable PR via the `Task` tool with `isolation: "worktree"`. Substitute the placeholders (`<owner>`, `<repo>`, `<n>`, `<head-ref>`) before calling `Task`.

### Prompt template

```
You are addressing review feedback for ONE pull request inside a fresh git worktree.

Repository: <owner>/<repo>
PR number: #<n>
PR head branch: <head-ref>

Constraints (the orchestrator handles these instead — do NOT do them yourself):
- Do NOT git push.
- Do NOT post replies via the GitHub MCP tools.
- Do NOT resolve review threads.
- Do NOT re-request reviewers.

Steps:

1. You start in an isolated worktree on a fresh branch. Switch to the PR branch:
     git fetch origin <head-ref>
     git switch <head-ref>
     git pull --ff-only origin <head-ref>
   If `--ff-only` fails (branch diverged), abort with a `blocked: branch-out-of-sync` entry in your final report.

2. Run the single-PR flow of the `git-pr-feedback` skill (Steps 1–4 of SKILL.md) for PR #<n> in <owner>/<repo>:
   - Use scripts/fetch-pr-data.sh to gather all PR data.
   - Categorise feedback (Blocking / Substantive / Suggestion / Question / Nitpick).
   - Make file edits and commits inside this worktree, grouping related fixes.
   - For accepted or adapted suggestion blocks, record co-author trailers.
   - For out-of-scope feedback, file follow-up issues per Step 3a and capture the issue number.

3. For each actionable thread, draft (but do NOT post) a reply text using the templates in REFERENCE.md "Reply Templates". When the reply needs to reference the resolving commit SHA, write the literal placeholder `{{SHA}}` — the orchestrator substitutes the pushed SHA before posting.

4. Stop. Do NOT push, reply, or resolve.

5. Return your final message as a single fenced JSON block matching the schema below. The orchestrator parses it programmatically; freeform prose outside the block is ignored.

```json
{
  "pr": <n>,
  "branch": "<head-ref>",
  "worktree_path": "<absolute path to your worktree>",
  "commits": [
    {"sha": "<full-sha>", "summary": "<one-line>"}
  ],
  "co_authors": ["<Name> <email>"],
  "addressed": [
    {
      "thread_id": "<PRRT_… node id>",
      "database_id": <integer top-level comment databaseId>,
      "action": "fix|accept|adapt|defer|answer|decline",
      "reply": "<reply text, may contain {{SHA}}>",
      "resolve": true
    }
  ],
  "deferred_issues": [<issue number>],
  "blockers": ["<one-line description of any blocker>"]
}
```

Edge cases:
- No actionable threads found: return an empty `addressed[]` and `commits[]` and exit cleanly — no error.
- A thread the reviewer asked to keep open: include it with `"resolve": false`.
- A nitpick declined with reasoning: include it with `"action": "decline"`, `"resolve": true`, and the explanation in `reply`.
```

### Orchestrator handling of subagent output

| Subagent return | Orchestrator action |
|-----------------|---------------------|
| Valid JSON, `commits[]` non-empty, no `blockers[]` | `git push origin <branch>` from main checkout, capture the resolving SHA, post replies (substituting `{{SHA}}`), resolve threads where `resolve: true`, re-request reviewers per Step 5a |
| Valid JSON, `commits[]` empty | Skip push and SHA capture; post any replies (substituting nothing), resolve only threads where `resolve: true` and the reply does not contain `{{SHA}}` |
| Valid JSON with `blockers[]` | Surface blockers in the summary; do not push partial work; do not resolve threads |
| Invalid JSON | Surface raw output in the summary as `blocked: parse-error` |

Worktrees share the underlying `.git/` of the main repo, so commits made by the subagent on `<head-ref>` are already visible from the main checkout. The orchestrator never needs to `cd` into the subagent's worktree to push.

## Summary Report Template

```markdown
## PR Feedback Summary

### Workflow Status
- CI Checks: [PASS/FAIL] - <details>
- Review Status: [Approved/Changes Requested/Pending]

### Feedback Addressed

| Category | Count | Code Change | Replied | Resolved |
|----------|-------|-------------|---------|----------|
| Blocking | N | ✅ N | ✅ N | ✅ N |
| Substantive | N | ✅ N | ✅ N | ✅ N |
| Suggestions accepted | N | ✅ N | ✅ N | ✅ N |
| Suggestions adapted | N | ✅ N | ✅ N | ✅ N |
| Questions | N | — | 💬 N | ⏸ N |
| Nitpicks declined | N | — | ✅ N | ✅ N |

### Changes Made
- <File 1>: <description of change> (commit <sha>)
- <File 2>: <description of change> (commit <sha>)

### Co-authored Commits
- <sha>: Co-authored-by <suggester1>, <suggester2>

### Follow-up Issues Filed
- #<n>: <title> (deferred from <thread URL>)

### Re-requested Reviewers
- @<login1> (CHANGES_REQUESTED → addressed)
- @<login2> (resolved threads on this push)

### Threads Left Open
- <thread URL>: <why it's still open>

### Next Steps
- [ ] Monitor CI for new run
- [ ] Track follow-up issue #<n>
```

### Multi-PR Rollup (--all)

When `--all` was passed, prepend a rollup section above the per-PR sections:

```markdown
## Multi-PR Rollup

| Metric | Count |
|--------|-------|
| PRs dispatched | N |
| PRs succeeded (pushed) | N |
| PRs blocked | N |
| Total commits pushed | N |
| Total threads resolved | N |
| Total replies posted | N |
| Follow-up issues filed | N |

### Per-PR results
| PR | Status | Commits | Replies | Resolved | Blockers |
|----|--------|---------|---------|----------|----------|
| #123 | ✅ pushed | 2 | 4 | 4 | — |
| #145 | ⚠ blocked | 1 | 0 | 0 | branch-out-of-sync |
| #160 | ✅ pushed (no commits — questions only) | 0 | 2 | 1 | — |
```

Then emit one of the per-PR templates above for each dispatched PR, scoped to that PR's threads and commits.
