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
