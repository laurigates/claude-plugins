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
