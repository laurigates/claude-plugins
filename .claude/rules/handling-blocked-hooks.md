---
created: 2026-01-01
modified: 2026-03-07
reviewed: 2026-03-07
---

# Handling Blocked Hooks

When a PreToolUse hook blocks a command, follow this decision process.

## How Hook Blocks Work

Hooks block commands with exit code 2. The block is definitive - use the suggested alternative or delegate to the user.

## Decision Process

### Step 1: Read the Hook Message

The blocking message explains:
- Why the command was blocked
- What alternatives to use instead
- When the command might be legitimate

### Step 2: Use the Suggested Alternative

| Hook suggests... | Action |
|------------------|--------|
| Use a different tool | Use that tool (e.g., Read instead of cat) |
| Use a safer flag | Modify the command accordingly |
| A different workflow | Follow the suggested workflow |

### Step 3: When Alternatives Are Insufficient

When the blocked command is genuinely required and alternatives are insufficient:

1. Explain to the user why the command is needed
2. Describe what alternatives you considered
3. Provide the exact command for the user to run manually
4. Let the user decide whether to run it themselves

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

## Branch Protection: Do Not Self-Serve the Bypass

The `branch-protection.sh` hook in `hooks-plugin` blocks writes on `main`/`master`. When it blocks you, the correct moves — in order — are:

1. **Create a feature branch**: `git checkout -b feature/your-change`, then re-run the command.
2. **Explicit-refspec push** (for `git push` only): `git push origin main:feature/your-change` is allowed by the hook and is the right way to move local `main` commits onto a remote feature branch.
3. **Delegate to the user** per the template above.

Do **not** attempt to prefix commands with `CLAUDE_HOOKS_DISABLE_BRANCH_PROTECTION=1` as a self-serve override. The hook only honors that variable when the **human operator** has exported it in their shell environment — inline prefixes on an agent-emitted command are intentionally ignored. If the repo legitimately uses main-branch-dev (personal repo, dotfiles), ask the user to export the variable for their session rather than injecting it into the command.

## Key Points

- Hooks protect against common mistakes - the suggested alternative is usually correct
- For edge cases, delegate to the user with the exact command
- Explain what you tried and why the command is needed
