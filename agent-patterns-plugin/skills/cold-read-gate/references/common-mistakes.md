# Cold-Read Gate — Common Mistakes

Moved verbatim from [SKILL.md](../SKILL.md). Open before dispatching a reader or
acting on its critique.

## Common Mistakes

| Mistake | Correct approach |
|---|---|
| Using opus/sonnet as the reader "for better critique" | The weak reader is the point — it measures, not advises |
| Spawning the reader with `run_in_background: true` | Run synchronously — the critique **is** the tool result of a synchronous run |
| Polling a completed background reader via `SendMessage` | It only emits `idle_notification`s there; read the task-completion result instead (#2063) |
| Pasting the artifact into the prompt | Give a path; pasted text tempts context smuggling |
| Letting the reader explore the repo | "Read ONLY this file" — exploration restores the context the test removes |
| Acting on every complaint | Triage first (Step 3); artifacts of the test produce busywork |
| Softening a claim the reader couldn't verify | Run the measurement when one exists — it often inverts the objection |
| Running the same persona twice on a two-channel artifact | One reader per channel; each gets its real audience |
| Looping until the reader is silent | One revise round; persistent confusion = structural problem |
| Gating drafts but not the docs that reference them | Anything a cold audience lands on qualifies |
