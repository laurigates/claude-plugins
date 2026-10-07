# Verify Before Filing — Common Mistakes

Open this when reviewing a filing run (or a plan for one) for the failure modes
that produce duplicate, stale, or rate-limited reports.

## Common Mistakes

| Mistake | Correct approach |
|---|---|
| Filing the backlog as written ("the audit already verified it") | The audit verified it *then*; verify at HEAD *now* |
| Dedup against the tracker but not your own issues | Your earlier reports' by-catch findings are duplicates too |
| Quoting your old observed version in the issue | Quote HEAD/latest-tag content; cite the refs you checked |
| Bulk-creating issues in a hand-written loop | 429 after the first create; run `scripts/file-wave.sh` (pacing + backoff + manifest) |
| Discarding gated-out candidates silently | Dispositions update docs, retire forks, close tracking issues |
| Letting verify agents have write access upstream | Read-only until the dedicated, paced filing step |
