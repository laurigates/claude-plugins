---
created: 2026-10-02
modified: 2026-10-02
reviewed: 2026-10-02
paths:
  - "**/agents/**"
---

# Agent Runtime Behaviour

How a dispatched agent behaves once it runs: fork vs briefed agent, the subagent context budget, worktree isolation, background execution, dynamic workflows, MCP policy for frontmatter servers, and the `claude agents` CLI. Writing the agent file itself (frontmatter, model selection, context isolation, memory, the team-role convention) is [`agent-development.md`](agent-development.md); this file was split out of it to keep both under the per-rule size ceiling (#2857).

## Dispatch: Context and Isolation

### Runtime fork vs named agent (2.1.232+)

The `Agent` tool's `subagent_type: "fork"` inherits the parent's full conversation and its prompt cache — no re-briefing, and cache reads on Fable 5.1 cost $0.25/MTok. Fork mode is on by default in interactive sessions since 2.1.232 and off by default under `-p` and in the Agent SDK, where requesting `fork` fails with `Agent type 'fork' not found` unless `CLAUDE_CODE_FORK_SUBAGENT=1` is set ([sub-agents.md § Turn fork mode on or off](https://code.claude.com/docs/en/sub-agents#turn-fork-mode-on-or-off)). A named plugin agent starts cold with only its brief, whatever its frontmatter says. **Default to a briefed agent**; fork only when the task depends on implicit conversation state that costs more to write down than to inherit. A fork of a 400k parent starts with all 400k, stale and abandoned reasoning included; a brief bounds the task and doubles as its hand-off contract. A named agent is also the only choice when the tool boundary (`tools:`), model, or preloaded `skills:` is the point. A fork has read the user's request verbatim; a briefed agent only has the parent's paraphrase, and Fable 5.1 has a slightly higher propensity to distort user intent when briefing subagents (system card §6.2.1) — so a named-agent brief quotes the user's request rather than paraphrasing it.

### Subagent context budget

No agent frontmatter field caps a subagent's context or tunes its compaction: per agent only `maxTurns`, `model` (window size), `effort` and `omitClaudeMd` (startup size) bound it, and env vars such as `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE` apply process-wide. Bound subagents by **task size**: scope each brief to finish well under half the window, require a state-packet return (`loop-integrity.md` Pillar 2), give an early-exit rule, and verify reports against artefacts. One haiku 200k run (2026-09-23) auto-compacted at ~75% and returned its compaction summary as a false completion report; treat that as a failure mode to design around. Baseline, open questions and the probe: `experiments/subagent-compaction/README.md`.

### Worktree Isolation

For filesystem-level isolation, give agents their own git worktree so they work on an isolated copy of the repository. The worktree is automatically cleaned up if the agent makes no changes; if changes are made, the worktree path and branch are returned.

> **Note (2.1.157)**: Claude-managed worktrees are left **unlocked** when the agent finishes, so `git worktree remove` / `git worktree prune` can clean them up directly (previously the lock blocked manual cleanup). `EnterWorktree` can also now switch between Claude-managed worktrees mid-session, rather than being a one-way entry.

> **Note (2.1.203–2.1.222, isolation hardening)**: Several releases closed escape vectors where an `isolation: worktree` subagent could still touch the parent checkout: shell commands running in the parent checkout instead of the isolated worktree (2.1.203), git-mutating commands against the main repo checkout (2.1.210), and `git -C` / `--git-dir` / `GIT_DIR` / `GIT_WORK_TREE` redirection out of the isolated worktree (2.1.216). As of 2.1.222, isolation applies to both file edits and Bash in every session type, and isolated sessions can no longer run destructive git commands against the main checkout. Treat isolation as materially more trustworthy on 2.1.222+ than on older installs — see `.claude/rules/agent-coworker-detection.md` § Bare flip for how this narrows that hazard.

**Two ways to enable worktree isolation:**

1. **Agent frontmatter** — baked into the agent definition:
   ```yaml
   ---
   name: implementer
   isolation: worktree
   ---
   ```

2. **Task tool parameter** — set per invocation:
   ```
   Task tool with isolation: "worktree"
   ```

> **Note (2.1.212, deprecated)**: A call-site `mode:` parameter on `Agent`/`Task` is deprecated and silently ignored — a spawned subagent always inherits the parent session's permission mode. Use the agent-frontmatter `permissionMode:` field (`agent-development.md` § Complete Field Reference) to set a fixed mode for a *named* agent; there is no way to override the mode for an ad-hoc/inline spawn.

**Use worktree isolation when:**
- Agent will make commits on a separate branch
- Multiple agents need to work on independent changes simultaneously
- You want changes isolated until explicitly merged

**Comparison:**

| Isolation Type | Mechanism | Isolates | Use Case |
|----------------|-----------|----------|----------|
| Any named agent (default) | Fresh subagent context | Context window (no parent history) | Research, exploration |
| `isolation: worktree` | Git worktree | Filesystem + Git | Implementation, commits |
| Manual worktree | `git worktree add` | Filesystem + Git | Complex multi-issue parallel work |

### `worktree.baseRef` Setting (2.1.133+)

Controls the branch base for `--worktree`, `EnterWorktree`, and agent-isolation worktrees:

| Value | Base Branch | Notes |
|-------|-------------|-------|
| `fresh` (default) | `origin/default-branch` | Unpushed local commits NOT included |
| `head` | Local `HEAD` | Includes unpushed commits; pre-2.1.133 default |

Set `worktree.baseRef: head` to keep unpushed commits in new worktrees.

## Background Execution

Non-teammate spawns run in the background by default (2.1.232+); pass `run_in_background: false` to block on the result. The Agent tool's `run_in_background` parameter (previously `Task tool`) controls this explicitly:

```
Agent tool with run_in_background: true
```

**Background execution behavior (2.1.232+: background is the default for non-teammate spawns):**
- The spawn returns immediately; the agent's result is delivered to the main session as a notification when it finishes — the main session does not poll.
- To block on a specific result before proceeding, spawn with `run_in_background: false`, or `Read` the output file path the spawn result names once its completion notification arrives; the blocking `TaskOutput` tool was removed in 2.1.277.
- Use `TaskStop` to stop a background agent.
- A subagent's result reaches the main agent under a header marking it as subagent output, indented, so its text cannot pass as the session's own instructions (2.1.277, after 2.1.210 hardened the Agent tool against indirect prompt injection); background notifications between turns arrive inside `<system-reminder>` tags (2.1.234).
- A subagent cut off by a rate limit or server error returns its partial work to the parent instead of failing silently (2.1.199).

**When to use background execution:**
- Independent work that doesn't need to block the main session
- Long-running tasks where you want to continue other work
- Parallel agent pipelines where results are collected later

**When to run in the foreground instead:** only when the very next action consumes the result and nothing else can proceed meanwhile (a single blocking lookup). Otherwise spawn in the background and wait for the result at the step that needs it — a research agent's findings can be awaited when you reach that step rather than blocking the session from the moment of spawn. Asynchronous delegation outperforms synchronous delegation on Fable 5.1 (system card §8.13).

### Background Session Behavior (2.1.141+ / 2.1.143+ / 2.1.169+)

| Version | Change |
|---------|--------|
| 2.1.141 | Background agents launched via `/bg` or `←←` preserve the current permission mode (no longer silently demoted to `default`) |
| 2.1.143 | `/bg` preserves `--mcp-config`, `--settings`, `--add-dir`, `--plugin-dir`, and `--strict-mcp-config` across respawn |
| 2.1.169 | Background sessions are now told that edits to the shared checkout are blocked until `EnterWorktree` is called — the session gets explicit guidance to enter a worktree before writing, instead of silently failing edits |

> **Note (2.1.154)**: `claude agents` accepts `! <command>` to run a shell command as a background session (equivalently `claude --bg --exec '<command>'`). Use it to fire off a one-shot background job from the dashboard without a full interactive session.

### Dynamic Workflows (`/workflows`, 2.1.154+)

`/workflows` orchestrates work across tens to hundreds of background agents from a single session — a fan-out scale beyond manual `/bg` dispatch. Reach for it when a task decomposes into many independent units that each warrant their own background agent; the framework manages the dispatch and result collection.

> **Resume and completion caveats** — `resumeFromRunId` re-runs already-succeeded worktree agents and opens duplicate PRs (#1868); `Workflow` agents are not `SendMessage`-addressable and their worktrees pin branches until a scoped, non-force removal gated on the run's completion notification (#2614). Full mechanics: `agent-patterns-plugin:parallel-agent-dispatch` § "Resuming a workflow: `resumeFromRunId` re-runs succeeded worktree agents" and its `references/worktree-hazards.md` § "Workflow agents are unreachable and their worktrees pin branches"; cleanup scoping in `.claude/rules/agent-coworker-detection.md`.

> **Script-authoring caveat — a `.then` wrapper hides `agent()` failures from `filter(Boolean)`.** A failed/killed `agent()` resolves to `null`, but the idiomatic label-attaching wrapper `agent(...).then(r => ({ pair, judge, r }))` re-wraps that `null` in a **truthy object**, so `results.filter(Boolean)` passes it straight through and the `null` payload explodes later (e.g. `jr.dimensions` at the final rollup — this crashed a 24-agent run at the last step, after all judging cost was spent). Filter on the payload field, not the wrapper: `results.filter(x => x && x.r)` — and guard rollup loops (`jr && jr.dimensions`) so one dead agent degrades to a gap instead of aborting the run. (Benchmark run `wf_9e402a8b`, 2026-07-03.)

> **Resume caveat — delete dead agents' output files before resuming.** An agent killed mid-run (session limit, API error) may have died **after** `Write`-ing its output file but **before** returning structured output. The workflow marks it failed, but its complete-looking file remains on disk. On `resumeFromRunId`, the re-run agent's `Write` to that same path fails with *"File has not been read yet"* (fresh subagents must Read an existing file before overwriting). Before resuming: delete output files belonging to **failed** agents; keep files from cached-successful ones (they won't re-run). Cross-check the failure list against the files on disk — "wrote its file" and "counted as done" are different claims. (Same run: 2 of 6 wave-1 judges died between `Write` and structured output.)

### `worktree.bgIsolation: "none"` (2.1.143+)

By default, background sessions launch into a fresh `EnterWorktree`. For repositories where worktrees are impractical (submodule-heavy repos, repos with paths longer than the OS-permitted symlink depth, host machines that share the worktree directory with other tools), set:

```json
{
  "worktree": {
    "bgIsolation": "none"
  }
}
```

The background session then edits the working copy directly. Trade-off: concurrent edits between the foreground and background sessions are no longer isolated — see `.claude/rules/agent-coworker-detection.md` for how to detect and avoid clobbering a coworker's in-flight changes.

### Worktree Cleanup Safety (2.1.143+)

When `git worktree remove` fails (e.g., gitignored build artifacts or in-progress files in the worktree), the harness used to fall back to `rm -rf` — silently destroying any non-tracked work. As of 2.1.143, the fallback is gone: the cleanup logs the failure and leaves the worktree in place. Inspect manually with `git worktree list` and remove with `git worktree remove --force <path>` once you have rescued any wanted files.

## MCP Servers Declared in Agent Frontmatter (2.1.153+)

Subagent-frontmatter `mcpServers` respect `--strict-mcp-config`, `--bare`, remote mode, enterprise managed MCP config, and managed-settings MCP allow/deny policies — before 2.1.153 these constraints were ignored for servers declared in agent frontmatter. `--strict-mcp-config` no longer strips inline `mcpServers` from explicitly-passed agent definitions (`--agents` / SDK `agents`), and a subagent MCP server blocked by policy surfaces a visible warning instead of failing silently.

## `claude agents` CLI (2.1.139+, Research Preview)

`claude agents` opens a dashboard listing all Claude Code sessions on the host — running, blocked on a permission prompt, or finished. Use it to attach to a background session, surface a blocked prompt, or list sessions per directory.

```bash
claude agents                              # full dashboard
claude agents --cwd ~/projects/my-repo     # scope list to a single directory (2.1.141+)
```

### Launch Flags (2.1.142+ / 2.1.143+)

The dashboard's "new session" launcher accepts the same flags as the top-level `claude` CLI, so a background session can match the foreground's configuration exactly:

| Flag | Effect |
|------|--------|
| `--add-dir <path>` | Add an extra directory to the session's working set |
| `--settings <file>` | Use a non-default settings.json |
| `--mcp-config <file>` | Load an MCP server config file |
| `--plugin-dir <path>` | Add a plugin directory (in addition to discovered ones) |
| `--permission-mode <mode>` | Start in `default`, `acceptEdits`, `dontAsk`, `bypassPermissions`, or `plan` |
| `--model <model>` | Pick the model (`opus`, `sonnet`, `haiku`, `fable`, `best`, or a full ID such as `claude-fable-5-1`) |
| `--effort <level>` | Set effort (`low`, `medium`, `high`, `xhigh`, `max`) |
| `--dangerously-skip-permissions` | Skip permission prompts — use only in trusted sandboxes |

Pair `--cwd` with the launch flags to spin up isolated, per-directory background sessions without leaving the dashboard.

## Related Rules

- `.claude/rules/agent-development.md` — agent file structure, model selection, context isolation, memory, team-role convention
- `.claude/rules/agent-coworker-detection.md` — detecting in-flight coworker changes before destructive git ops (relevant when `worktree.bgIsolation: "none"`)
- `.claude/rules/skill-fork-context.md` — the skill-frontmatter `context: fork` background default, distinct from `Agent`-tool background execution
- `agent-patterns-plugin:parallel-agent-dispatch` — fan-out contract, worktree hazards, workflow resume/cleanup
