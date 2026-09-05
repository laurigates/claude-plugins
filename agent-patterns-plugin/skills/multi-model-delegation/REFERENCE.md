# Multi-Model Delegation - Reference

Edge-case mechanics for consulting foreign models: diagnosing an empty
deferred-tool lookup, and driving the OpenCode Go gateway directly when PAL's
MCP server is unreachable.

## `No matching deferred tools found` has two causes

Do not read that message as proof the prefix is wrong — under the **correct**
prefix it means something else entirely, and the two want different responses:

| What you observe | Cause | Do this |
|---|---|---|
| The prefix you tried is not the key `claude mcp list` reports | Wrong prefix | Retry with the reported key |
| The **correct** prefix also finds nothing, PAL's tools never appear in any deferred-tool reminder, yet `claude mcp list` says Connected | The server's tools were never registered *in this session* — likely it connected after session start | Restart the session, or drive the server directly over stdio JSON-RPC (issue #2437) |

One trap in that direct-stdio workaround, worth stating because its symptom
misleads: **keep stdin open until the response arrives.**
`subprocess.run(..., input=...)` closes stdin after writing, so the server shuts
down mid-call and returns an empty result that looks exactly like a hung or
non-responding model rather than a transport error.

## Calling the OpenCode Go Gateway Directly

PAL is the normal route. When its MCP server is not connected to the session,
the same models are reachable at `https://opencode.ai/zen/go/v1/chat/completions`
with `OPENCODE_API_KEY` — the endpoint PAL's own `opencode_go` provider uses.
Three mechanics bite there that do not bite through PAL, all measured on
`qwen3.8-flash` reviewing GitHub Actions diffs (2026-09):

| Mechanic | Symptom | Fix |
|---|---|---|
| **models.dev's catalogue is not the gateway's catalogue**, and neither is PAL's pinned `conf/opencode_go_models.json` | A model the user names is "not in the list", so you substitute a near-miss id and review with the wrong model. Observed: `qwen3.8-flash` was absent from models.dev's `opencode` provider *and* from PAL's pinned config, while the gateway's own `/v1/models` served it. The reverse also holds — models.dev listed `gemini-3.8-flash`, which the gateway rejects with `Model … is not supported` | Enumerate from the gateway itself: `curl -s $URL/models -H "Authorization: Bearer $OPENCODE_API_KEY"`. A pinned config and a third-party index are both snapshots; only the gateway answers for what it serves |
| **A non-streaming request hangs on a long generation** | `http=000` after the full `--max-time`, zero bytes, no error body — indistinguishable from a network fault. Measured: a 24 KB payload hung for the full 900 s, while a 33 KB payload of *trivial* content returned 200 in 2.4 s, so payload size is the wrong suspect | Send `"stream": true` and read the SSE deltas. The same request that hung then streamed 3.8 MB |
| **A reasoning model can spend its whole budget reasoning and emit nothing** | The stream never reaches `[DONE]` and `content` is empty while `reasoning_content` runs to six figures. Measured on a 15 KB diff: **179,283 chars of reasoning, 0 chars of content** | Cut the input until each call is small enough to answer — per file, then per hunk (~4.5 KB worked). Chunks are independent, so run them concurrently; raising `max_tokens` does not help, because the budget is going to reasoning |

Two consequences for the protocol. **A chunked review is partial by
construction**: record how many chunks failed and say so wherever the findings
are used — absence of a finding in a region that never returned is not evidence
that region is clean. And **an empty findings array from a broken reviewer is
indistinguishable from a clean review**, so control-test the harness against a
diff with a defect you planted before trusting any negative
(`agent-patterns-plugin:tool-result-traps`).

**Isolate a model failure with controlled probes before believing your first
theory.** The intuitive suspects (big prompt, file attachments) were innocent
twice — a bug filed on either would have sent the maintainer down the wrong
path. A two-word prompt plus the one suspect parameter settles it in one call.
