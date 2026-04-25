# ADR-008: Two-Phase Interaction for the Onboard Workflow

- **Status:** Accepted
- **Date:** 2026-04-25
- **Deciders:** @laurigates

## Context

The `git-repo-agent onboard` command runs the blueprint state-machine driver
(ADR-006) followed by an LLM orchestrator under `ClaudeAgentOptions` (SDK
subprocess transport). Until this ADR, the orchestrator prompt
(`onboard.md`) instructed the model to "present the plan to the user via
`AskUserQuestion`" before making changes.

ADR-003 already established that `AskUserQuestion` does not work in SDK
subprocess mode: the CLI's stdin/stdout carry the SDK JSON protocol, the
tool has no terminal to render to, and the call fails silently. ADR-003
ported the maintain workflow to a two-phase pattern (analysis →
`console.input()` → execution) but onboard kept the single-session flow.

### The failure

In production, the symptom for onboard mirrored the original maintain
bug:

1. `BlueprintDriver` runs to completion and writes `docs/blueprint/`,
   ADRs, rules, etc. into the worktree.
2. Orchestrator phase prints tool calls culminating in two
   `AskUserQuestion` calls.
3. Session ends with `Onboarding complete.` and no commits.
4. Pre-fix, `cleanup_worktree --force` then destroyed the blueprint
   driver's uncommitted output.

The data-loss part was mitigated by the `auto_commit_if_dirty()` /
uncommitted-aware `worktree_has_changes()` work captured in
`agent-cli-worktree-safety.md`. The interaction failure — the user
never seeing the plan they were promised — remained.

## Decision

**Apply the ADR-003 two-phase pattern to `onboard`.** Reuse the
`_stream_interactive` plumbing from maintain by parameterising the
phase-2 prompt builder and the user-input label, so the same Python
runner serves both workflows.

### Implementation

Three coordinated changes:

**`orchestrator.py`** — generalise `_stream_interactive`:

```python
async def _stream_interactive(
    prompt, options, completion_msg,
    user_input_label,                    # caller-supplied prompt copy
    build_phase2_prompt,                 # callable(text, selection, branch) -> str
    worktree_branch=None,
    none_message="No actions selected.",
):
    ...
```

`run_onboard` routes interactive (non-dry-run, non-non-interactive) runs
through `_stream_interactive` with `_build_onboard_phase2_prompt`. The
Phase 2 prompt embeds the planning-phase plan verbatim plus the user's
selection. `_phase2_system_prompt` (already maintain-tested) appends the
"Phase 2 Override (execution)" block to the system prompt to negate the
"stop after presenting plan" anchor from `onboard.md`.

`AskUserQuestion` is removed from the base `allowed_tools` list for
onboard — it never works in subprocess mode for any onboard mode, so
making accidental use fail loudly is preferable to silent no-op.

**`onboard.md`** — Operating Modes section + Step 2 update:

- New "Operating Modes" table mirroring maintain.md (planning,
  execution, direct, dry-run).
- Step 2 now produces a numbered plan (`1. [claude-md] …`, etc.) and
  ends the response in interactive planning mode.
- Step 4 now expects a fresh user prompt with the plan + selection
  embedded, mirroring the maintain Step 4 contract.
- `INTERACTIVE_MODE` env var documented.

**`run_onboard`** — adds `INTERACTIVE_MODE` env var, removes
`AskUserQuestion` from `allowed_tools`, branches to `_stream_interactive`
when `non_interactive is None and not dry_run`.

### User input contract

The Phase 1 → user → Phase 2 selection grammar matches maintain:

| Input | Meaning |
|-------|---------|
| `all` / `yes` / `y` | Apply every numbered step in the plan |
| `1,3,5` (comma-separated digits) | Apply only those steps |
| `none` / `no` / `n` / empty | Skip all execution; emit a brief "no changes" summary |

## Alternatives Considered

### 1. Add a callback for `AskUserQuestion`

- **Rejected:** `claude-agent-sdk` 0.1.39 has no programmatic callback
  for tool prompts. Re-evaluate if upstream adds one.

### 2. Pre-collect via CLI flags (e.g. `--apply=1,3,5`)

- **Rejected:** Users need to see the plan derived from the live
  repository state before selecting. A flag-driven interface forces a
  two-step CLI workflow for what the two-phase pattern handles
  in-session.

### 3. Always auto-execute and rely on PR review

- **Rejected:** Onboarding can land high-impact changes (CI workflows,
  pre-commit hooks, README). The auto-fix mode is appropriate for
  scheduled non-interactive runs but not as the only behaviour for an
  interactive command. Users want a plan-review checkpoint.

### 4. Reuse a single `ClaudeSDKClient` across phases

- **Rejected:** ADR-003 Revision 2026-04-12 documented why this fails
  for maintain — the Phase 1 "stop after presenting" anchor in the
  system prompt dominates the Phase 2 follow-up message, and the agent
  wraps up with no tool calls. Two separate sessions with a Phase 2
  Override block is the only pattern that has held in production.

## Consequences

### Positive

- Users see the onboarding plan and can approve / reject / select before
  changes land.
- `AskUserQuestion` in `allowed_tools` no longer hides silent failures
  for onboard.
- One generalised `_stream_interactive` serves both onboard and maintain;
  any future workflow that needs the same shape only writes a
  `_build_<workflow>_phase2_prompt`.

### Negative

- Two `ClaudeSDKClient` sessions per interactive onboard run (two
  `ResultMessage`s, two cost entries).
- The agent must reliably output the numbered plan in the documented
  format for the user prompt to make sense. Drift in `onboard.md` Step 2
  can break Phase 2's plan parsing (mitigated: Phase 2 embeds the
  Phase 1 text verbatim, so the agent rather than Python interprets the
  plan).

### Neutral

- `INTERACTIVE_MODE` env var joins `DRY_RUN`, `SKIP_CI`, `SKIP_BLUEPRINT`
  and `ONBOARD_BRANCH` as a workflow-mode signal.
- Dry-run interactive runs continue to use single-phase
  `_stream_messages` since they make no changes — there is nothing for
  the user to approve.

## Relationship to ADR-003

ADR-003 introduced the two-phase pattern for maintain. ADR-008 extends
it to onboard and refactors the helpers so the pattern is reusable
without copy-paste. The "Phase 2 Override" override block, the
two-separate-sessions decision, and the `_phase2_system_prompt` /
`_build_*_phase2_prompt` split all originated in ADR-003.

## Re-evaluation Triggers

- If `claude-agent-sdk` adds a programmatic callback for
  `AskUserQuestion`.
- If a third workflow needs the same pattern — at that point promote
  the per-workflow Phase 2 builder protocol into a `Protocol` /
  dataclass instead of three loose callables.
- If the onboarding plan format diverges so far from maintain's
  numbered findings that the shared Phase 2 plumbing stops fitting.
