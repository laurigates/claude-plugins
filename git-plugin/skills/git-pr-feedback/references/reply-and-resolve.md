# git-pr-feedback - Re-request, Reply and Resolve

Re-requesting review after a push (Step 5a) and the reply/resolve rules for every actionable thread (Step 6).

## Step 5a: Re-request Review (if --push)

After a successful push that addresses substantive feedback, re-request review from any reviewer whose threads were resolved or who left a `CHANGES_REQUESTED` review. Skip this step when only nitpicks or questions were addressed.

Determine reviewers to re-request from the GraphQL response captured in Step 1:

- `latestReviews` entries with `state == "CHANGES_REQUESTED"`
- Authors of any review thread you resolved in Step 6

Then call:

```bash
gh api -X POST \
  /repos/<owner>/<repo>/pulls/<pr>/requested_reviewers \
  -f 'reviewers[]=<login1>' \
  -f 'reviewers[]=<login2>'
```

If `gh api` returns 422 ("Reviews may only be requested from collaborators"), the reviewer cannot be re-requested via the API — note it in the Step 7 summary and continue.

## Step 6: Reply and Resolve Threads

For every actionable thread tracked in Step 2, post a reply and then **resolve the thread by default**. Owner/repo/PR are the same values used in Step 1.

Resolving is the default action after replying — leaving threads open is the exception, reserved for the explicit cases listed in step 3. A reply alone does **not** end the conversation in GitHub's UI: the thread stays in the reviewer's "unresolved" queue until someone clicks **Resolve conversation**. Without this step the PR will continue to show unresolved feedback even after every concern has been addressed.

1. **Reply** with `mcp__github__add_reply_to_pull_request_comment` using the top-level comment's `databaseId` (a number, not the GraphQL node ID). Keep replies short — see [REFERENCE.md](../REFERENCE.md) "Reply Templates".
   - Code change made → reference the commit SHA: `Fixed in <sha> by <one-line summary>.`
   - Suggestion accepted verbatim → `Accepted suggestion in <sha>.`
   - Suggestion adapted → explain the deviation: `Applied a variant in <sha>: <reason>.`
   - Deferred / out of scope → reference the follow-up issue filed in Step 3a: `Deferred to #<issue> — <reason>.`
   - Question → answer it directly.
   - Refuting a suggestion (claim verification disproved) → state the reasoning **with evidence**: `Leaving as-is: <reason> — <evidence that disproves the claim>.`

2. **Always resolve** with the GraphQL `resolveReviewThread` mutation using the thread `id` (a `PRRT_…` GraphQL node ID). Resolution is the default after a reply — only skip when one of step 3's "leave open" exceptions applies. Call:

   ```bash
   gh api graphql -f query='mutation($id:ID!){resolveReviewThread(input:{threadId:$id}){thread{isResolved}}}' -F id="$THREAD_ID"
   ```

   Resolve when **any** of these completion conditions hold and none of step 3's "leave open" exceptions apply:
   - You pushed a commit that addresses the concern (`Fixed in <sha>`, `Accepted in <sha>`, `Applied a variant in <sha>`).
   - You answered the reviewer's question directly.
   - You refuted or declined the suggestion with explicit reasoning in the reply (a written refutation — not silence — completes the thread).
   - You deferred to a follow-up issue filed in Step 3a (the deferral and issue link are the resolution).

   Resolving must happen in the **same turn** as the reply. Treat "reply posted but thread unresolved" as an incomplete step — re-run the resolve call before reporting Step 7.

3. **Leave the thread open** only when one of these holds:
   - Your reply asks the reviewer a follow-up question (you are waiting on them).
   - The fix is partial — some of the concern still applies to this PR.
   - The reviewer explicitly asked to keep the thread open.
   - You haven't pushed yet (no resolving SHA exists) — finish Step 5, then resolve.
   - You're acting on a PR you don't own and the user has not approved resolving on third-party PRs.

If `--commit`/`--push` was not passed, still post replies for questions and refutations, but defer resolution until a future invocation with `--push` lands the SHA. Note these pending resolutions in the Step 7 summary so they're not forgotten.
