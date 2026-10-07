# git-pr-feedback - Addressing Feedback

Verification discipline and the per-comment-shape decision table for Step 3, and filing follow-up issues for deferred feedback (Step 3a).

## Step 3: Address Feedback

**Verify before accepting — especially claims from an automated reviewer.** Before accepting or acting on any suggestion, independently verify the claim against the actual source, the live system, or upstream documentation. This matters most for automated reviewers (Gemini Code Assist, Copilot, and other bot authors), whose suggestions are frequently confidently-wrong: read the code/config the claim is about, check the rendered/live behaviour, and confirm against docs rather than applying a bot suggestion on trust. A claim that fails verification is **refuted** — reply with the refutation and the supporting evidence, and do **not** change the code. A written refutation with evidence is a legitimate way to resolve a thread (see Step 6).

Work through actionable items systematically. For each thread, decide using the table below — see [REFERENCE.md](../REFERENCE.md) for the full decision tree.

| Comment shape | Action |
|---------------|--------|
| Contains a ` ```suggestion ` block, fix is correct | **Accept the suggestion**: apply the suggestion's exact replacement to the file (see [REFERENCE.md](../REFERENCE.md) "Accepting Suggestions"). Record the comment author's `login` and `name`/`email` for co-author attribution in Step 4. |
| Contains a ` ```suggestion ` block, fix needs adjustment | Implement an improved variant; explain the deviation in the reply. Record the suggester for co-author attribution. |
| Inline code comment without suggestion | Read context, implement fix, verify no regressions |
| Claim that verification refutes (wrong on the facts) | **Refuted**: do not change the code. Reply with the refutation and the evidence that disproves it (the source line, rendered config, live behaviour, or doc that contradicts the claim), then resolve. Apply this whenever a bot/automated-reviewer suggestion does not survive verification. |
| Question / clarification | Skip code change; draft an inline reply for Step 4 |
| Blocking review (`REQUEST_CHANGES`) | Address every concern before resolving any thread |
| Failed CI check | Identify failure type (lint/type/test/build), fix locally, run to verify |
| Out-of-scope feedback | Do not implement in this PR. Open a follow-up issue (see Step 3a) and reference its number in the reply. |

Mark each item in progress while working it and done once the file change (if any) lands locally. Do **not** resolve threads yet — replies and resolution happen after the commit so reviewers see the linked SHA.

## Step 3a: File follow-up issues for out-of-scope feedback

For any thread categorised as out-of-scope (or where the user opts to defer rather than implement now):

1. Draft a one-line title and short body that quotes the reviewer comment and links the PR thread URL.
2. Use `mcp__github__issue_write` (action `create`) or `gh issue create -R <owner>/<repo> --title "<title>" --body "<body>"` to file the issue.
3. Capture the returned issue number — Step 6's reply uses it (`Deferred to #<n> — <reason>.`).

Skip this step if the user has explicitly said not to file follow-ups. When ambiguous, ask via `AskUserQuestion` before creating an issue.
