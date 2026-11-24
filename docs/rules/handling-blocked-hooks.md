# Handling Blocked Hooks: template and examples

The always-loaded rule [`.claude/rules/handling-blocked-hooks.md`](../../.claude/rules/handling-blocked-hooks.md)
keeps the decision process, the branch-protection moves and the key points.
This page holds the response template, a worked example and the legitimate use
cases, moved here verbatim on 2026-11-24 so they no longer load on every turn.

## Response Template

```
The hook blocked `[command]` because [reason from hook message].

I considered these alternatives:
- [Alternative 1]: [Why it's insufficient in this case]
- [Alternative 2]: [Why it's insufficient in this case]

If you need to proceed, please run this command manually:
`[exact command]`

This is needed because [specific justification for this edge case].
```

## Example

```
[Hook blocks git reset --hard]
Claude: "The hook blocked this command because git reset --hard
discards uncommitted changes. I considered these alternatives:
- git restore: Insufficient because we need to reset the index too
- git checkout: Insufficient because it preserves staged changes

If you need to proceed with the reset, please run this command manually:
git reset --hard <commit>

This is needed because the repository is in a corrupted state after
the failed merge."
```

## Legitimate Use Cases

| Blocked Command | Legitimate Use Case |
|-----------------|---------------------|
| `git reset --hard` | Recovering from corrupted git state |
| `rm -rf` | Cleaning build artifacts when other methods are insufficient |
| Chained git commands | Complex atomic operations |
