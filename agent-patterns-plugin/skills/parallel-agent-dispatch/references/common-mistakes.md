# Parallel Agent Dispatch — Common Mistakes

Moved verbatim from [SKILL.md](../SKILL.md). Open when reviewing a dispatch plan or
a lead prompt before spawning agents.

### Common Mistakes

| Mistake | Correct Approach |
|---------|-----------------|
| Spawning agents from a dirty main tree | Commit or stash first; refuse to dispatch on dirty state |
| Scope described in prose, not glob | Explicit write-path list per agent |
| "Report back when done" with no schema | Include Return Contract verbatim in every prompt |
| Treating agent silence as success | No Return Contract = stall; investigate before reporting done |
| Respawning after an `idle_notification` with no report | Check the branch, then `SendMessage` the agent to resend the report (#2039) |
| Accepting a one-word final message (`Terminal.`/`Done.`) | Mandate the loud-failure contract: push work, open a draft PR, explain |
| Centralizing pushes as a default | Agent pushes its own work; lead pushes only on sandbox/dependency exceptions |
| One constraints block, merge authorization included, pasted into every stage's brief | Merge/publish authority only in the owning stage's brief; build stages end with "stop at PR opened; do not merge" (#2902) |
| A downstream brief cites "the user's decision" without quoting it | Carry the user's decisions verbatim into every stage's brief — no stage can read another stage's prompt. Authority grants (merge/publish) are the exception: quote them only in the owning stage's brief, and in build-stage briefs replace them with the explicit stop |
| Packing several sub-tasks into one agent's brief | One bounded objective per agent; split a bundled brief into separate agents or sequential briefs. Models, Claude Opus 5 included, make more errors on tasks composed into one prompt than on each task alone, beyond what independent errors add up to (arXiv 2610.27190) |
| A brief with no context-budget exit | Add the **Budget** clause: stop before compacting and return the Return Contract as the state packet (#2818) |
