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

Group related fixes into logical commits:

```bash
git add <files-for-fix-1>
git commit -m "fix: address review feedback - <specific change>"
```

For multi-fix commits:

```
fix: address PR review feedback

- <Change 1 description>
- <Change 2 description>

Co-authored-by: <reviewer> (if they provided specific code)
```

Run pre-commit hooks if configured:

```bash
pre-commit run --all-files
git add -u  # Stage any formatter changes
```

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

### Threads Left Open
- <thread URL>: <why it's still open>

### Next Steps
- [ ] Re-request review from <reviewer>
- [ ] Monitor CI for new run
- [ ] Follow up on <deferred item>
```
