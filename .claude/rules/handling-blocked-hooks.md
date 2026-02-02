# Handling Blocked Hooks

When a PreToolUse hook blocks a command, follow this decision process.

## Understanding Hook Blocks

Hooks block commands for safety reasons:
- Preventing destructive operations
- Enforcing tool usage patterns
- Protecting against common mistakes

**Critical**: When a hook blocks a command with exit code 2, the command will NOT execute no matter how many times you retry. User permission does not bypass hook blocks.

## Decision Process

### Step 1: Read the Hook Message Carefully

The blocking message explains:
- Why the command was blocked
- What alternatives to use instead
- When the command might be legitimate

### Step 2: Evaluate Alternatives

| If the message suggests... | Then... |
|---------------------------|---------|
| Use a different tool | Use that tool (e.g., Read instead of cat) |
| Use a safer flag | Modify the command accordingly |
| A different workflow | Follow the suggested workflow |

### Step 3: If Alternatives Won't Work

If you've genuinely considered all alternatives and the blocked command is truly required:

**Do NOT:**
- Retry the same command (it will be blocked again)
- Try creative workarounds to achieve the same effect
- Ask user for "permission" to bypass (hooks can't be bypassed this way)

**DO:**
1. Explain to the user why the command is needed
2. Describe what alternatives you considered and why they won't work
3. Provide the exact command for the user to run manually
4. Let the user decide whether to run it themselves

## Example: Blocked git reset --hard

**Wrong approach** (what not to do):
```
[Hook blocks git reset --hard]
Claude: "Let me ask for permission"
[User says yes]
Claude: [Retries git reset --hard - blocked again]
Claude: "Let me try a workaround with git checkout"
```

**Correct approach**:
```
[Hook blocks git reset --hard]
Claude: "The hook is blocking this command because git reset --hard
is usually unnecessary. I considered these alternatives:
- git pull: Won't work because [specific reason]
- git restore: Won't work because [specific reason]

If you need to proceed with the reset, please run this command manually:
git reset --hard <commit>

This is needed because [explanation of the specific edge case]."
```

## Template Response

When a legitimately needed command is blocked:

```
The hook blocked `[command]` because [reason from hook message].

I considered these alternatives:
- [Alternative 1]: [Why it won't work in this case]
- [Alternative 2]: [Why it won't work in this case]

If you still need to proceed, please run this command manually:
`[exact command]`

This is necessary because [specific justification for this edge case].
```

## Common Legitimate Edge Cases

| Blocked Command | Legitimate Use Case |
|-----------------|---------------------|
| `git reset --hard` | Recovering from corrupted git state, reverting to known-good state after failed operations |
| `rm -rf` | Cleaning build artifacts when other methods fail |
| Chained git commands | Complex atomic operations (but usually separating them is better) |

## Remember

- Hooks exist to protect against common mistakes
- Most of the time, the suggested alternative is correct
- Asking the user to run a command manually is appropriate for rare edge cases
- Always explain why the command is needed and what you tried first
