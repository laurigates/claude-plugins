---
created: 2026-01-01
modified: 2026-11-24
reviewed: 2026-09-02
---

# Handling Blocked Hooks

When a PreToolUse hook blocks a command, follow this decision process.

Unscoped on purpose: a block can land on any command in any session, which no
`paths:` glob can see.

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

The response template, a worked example and a table of legitimate use cases are in [`docs/rules/handling-blocked-hooks.md`](../../docs/rules/handling-blocked-hooks.md).

## Branch Protection: Do Not Self-Serve the Bypass

The `branch-protection.sh` hook in `hooks-plugin` blocks writes on `main`/`master`. When it blocks you, the correct moves — in order — are:

1. **Create a feature branch**: `git switch -c feature/your-change`, then re-run the command.
2. **Explicit-refspec push** (for `git push` only): `git push origin main:feature/your-change` is allowed by the hook and is the right way to move local `main` commits onto a remote feature branch.
3. **Delegate to the user** per the template above.

Do **not** attempt to prefix commands with `CLAUDE_HOOKS_DISABLE_BRANCH_PROTECTION=1` as a self-serve override. The hook only honors that variable when the **human operator** has exported it in their shell environment — inline prefixes on an agent-emitted command are intentionally ignored. If the repo legitimately uses main-branch-dev (personal repo, dotfiles), ask the user to export the variable for their session rather than injecting it into the command.

## Key Points

- Hooks protect against common mistakes - the suggested alternative is usually correct
- For edge cases, delegate to the user with the exact command
- Explain what you tried and why the command is needed
- A block is on the *hazard*, not the spelling. Take the hook's suggested alternative if it offers one; otherwise do not re-issue the same operation in a different form (split into pieces, reordered flags, quoting, `$(…)` or `bash -c` wrapping, a wrapper script) to get past it — treat a second block on a variant as confirmation to delegate.
- Never restate authorization the user did not literally give. Quoting or paraphrasing "the user approved this" to a hook, classifier, or subagent when the transcript does not contain it is fabrication; auto mode blocks it regardless.
