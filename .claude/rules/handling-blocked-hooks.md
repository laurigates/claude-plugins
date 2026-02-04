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

## Key Points

- Hooks protect against common mistakes - the suggested alternative is usually correct
- For edge cases, delegate to the user with the exact command
- Explain what you tried and why the command is needed
