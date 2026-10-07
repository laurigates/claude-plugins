# Agent Teams — Key Paths and Common Mistakes

Moved verbatim from [SKILL.md](../SKILL.md). Open when a message misroutes, team
or task state looks wrong, or before reviewing a team setup.

### Key Paths

| Path | Contents |
|------|----------|
| `~/.claude/teams/` | Implicit-team state (members: name, agentId, agentType) |
| `~/.claude/tasks/` | Shared task list state |

Address teammates by the `name` you gave them at spawn — that is the reliable
handle, independent of any on-disk layout.

### Common Mistakes

| Mistake | Correct Approach |
|---------|-----------------|
| Using agentId as recipient | Use the `name` given at spawn |
| Calling the removed `TeamCreate`/`TeamDelete` | The team is implicit (2.1.178); spawn with `Agent`, shut down with `shutdown_request` |
| Passing `team_name` and expecting routing | It is accepted but ignored — there is one implicit team |
| Sending broadcast for every update | Use `message` for single-recipient comms |
| Polling for messages | Messages delivered automatically — just wait |
| Sending JSON status messages | Use `TaskUpdate` for status, plain text for messages |
| Sub-agent pushes to remote | Delegate push to lead orchestrator |
