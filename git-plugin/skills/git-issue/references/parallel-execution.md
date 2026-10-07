# Step 3: Parallel Execution (`--parallel`)

Moved verbatim from `SKILL.md`. Read only when `--parallel` is passed.

### Step 3: Parallel Execution (--parallel flag)

When `--parallel` is specified:

1. Group issues by dependencies (from analysis)
2. For each parallel group, spawn a Task agent:

```
Agent tool with subagent_type: "general-purpose", prompt: "Process issue #N with TDD workflow.
Cut the branch with `git fetch origin && git switch -c fix/issue-N origin/main` — never from local main..."
```

Give the subagent the issue's title and body verbatim (quoted, not summarised)
and the labels to apply, and instruct it to read the full comment thread itself
— `gh issue view N --json title,body,comments` — before planning, scoping from
the latest deciding comment rather than from your description of it. Do not
restate the scope in your own words: the subagent implements what the thread
decided, not what you paraphrased.

3. Wait for all agents to complete
4. Consolidate results
