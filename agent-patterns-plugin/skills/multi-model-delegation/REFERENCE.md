# Multi-Model Delegation - Reference

Edge-case mechanics for consulting foreign models: diagnosing an empty
deferred-tool lookup, reading a single-model review from a PAL workflow tool,
and driving the OpenCode Go gateway directly when PAL's MCP server is
unreachable.

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

## Single-model review through PAL workflow tools

PAL's step-based workflow tools (`codereview`, `precommit`, `debug`, and the
others built the same way) send the caller's own step-2 `findings` and
`issues_found` to the expert model along with the files. The expert reads your
conclusions before it reads the code, so its analysis is anchored on them.

- **Expert agreement under `codereview`/`precommit`/`debug` is not
  corroboration.** Most of what the expert returns restates your step-2 notes,
  often at a higher severity. Count it as an echo, never as a second opinion.
- **When an independent opinion is the point, withhold your conclusions.** Keep
  step 2 to the scope and the file list, with no findings, or call `chat` with
  the files attached and a neutral question ("review this diff for defects").
  Compare its findings with your own afterwards — the disagreement is the
  payload, as in a multi-model consult.
- **Verify every finding the expert adds on its own against the code** before
  acting on it, as the user-global CLAUDE.md's PR-review guidance already
  requires for any delegated review.

Evidence: `laurigates/pal-mcp-server` PRs
[#167](https://github.com/laurigates/pal-mcp-server/pull/167),
[#168](https://github.com/laurigates/pal-mcp-server/pull/168) and
[#169](https://github.com/laurigates/pal-mcp-server/pull/169) (2026-10-07), one
`codereview` each with the caller's pre-review written into step 2. Nearly
every expert finding restated a step-2 observation. The findings it added
itself mostly failed verification: a "HIGH: sync I/O blocks the event loop"
measured at 3.4–167 ms and was downgraded to low; a suggested fix used an SDK
constant that does not exist in the installed version; a Docker failure was
impossible because `.dockerignore` keeps `.env` out of the image; an escaping
bug was in a cell that was already escaped. The files did reach the expert —
the server log shows 5 files embedded even though the response reported
`files_embedded: 0` (filed as
[pal#178](https://github.com/laurigates/pal-mcp-server/issues/178)) — so the
misses were anchoring, not missing context.

## Calling the OpenCode Go Gateway Directly

PAL is the normal route. When its MCP server is not connected to the session,
the same models are reachable at `https://opencode.ai/zen/go/v1/chat/completions`
with `OPENCODE_API_KEY` — the endpoint PAL's own `opencode_go` provider uses.
Take the key from the calling process's environment. Never have an agent read
`~/.api_tokens`: the secret-protection hook blocks `source`, and an agent blocked
that way was observed extracting the key with `sed` onto a command line
(2026-10-04), which puts it in the transcript.

Five mechanics bite there that do not bite through PAL. The first three were
measured on `qwen3.8-flash` reviewing GitHub Actions diffs (2026-09), the last
two on `deepseek-v4.1-flash` from a stdlib `urllib` client (2026-10):

| Mechanic | Symptom | Fix |
|---|---|---|
| **models.dev's catalogue is not the gateway's catalogue**, and neither is PAL's pinned `conf/opencode_go_models.json` | A model the user names is "not in the list", so you substitute a near-miss id and review with the wrong model. Observed: `qwen3.8-flash` was absent from models.dev's `opencode` provider *and* from PAL's pinned config, while the gateway's own `/v1/models` served it. The reverse also holds — models.dev listed `gemini-3.8-flash`, which the gateway rejects with `Model … is not supported` | Enumerate from the gateway itself: `curl -s $URL/models -H "Authorization: Bearer $OPENCODE_API_KEY"`. A pinned config and a third-party index are both snapshots; only the gateway answers for what it serves |
| **A non-streaming request hangs on a long generation** | `http=000` after the full `--max-time`, zero bytes, no error body — indistinguishable from a network fault. Measured: a 24 KB payload hung for the full 900 s, while a 33 KB payload of *trivial* content returned 200 in 2.4 s, so payload size is the wrong suspect | Send `"stream": true` and read the SSE deltas. The same request that hung then streamed 3.8 MB |
| **A reasoning model can spend its whole budget reasoning and emit nothing** | The stream never reaches `[DONE]` and `content` is empty while `reasoning_content` runs to six figures. Measured on a 15 KB diff: **179,283 chars of reasoning, 0 chars of content** | Cut the input until each call is small enough to answer — per file, then per hunk (~4.5 KB worked). Chunks are independent, so run them concurrently; raising `max_tokens` does not help, because the budget is going to reasoning |
| **The gateway requires an `x-opencode-session` header** | `HTTP 400 {"error":{"type":"MissingSessionID","message":"Request is missing x-opencode-session and cannot be routed efficiently…"}}` on every request, whatever the model or payload | Send one stable ID per conversation, e.g. `x-opencode-session: review-pr-<n>-<uuid>`. PAL sets it in `providers/opencode_go.py` from `utils/session_context.py` (continuation id, or a per-process fallback), which is why the same request works through PAL |
| **Cloudflare rejects the default client User-Agent** | `HTTP 403`, body `error code: 1010`, before the request reaches the gateway; no JSON error, so it reads like a bad key | Send an explicit `User-Agent` (the OpenAI SDK's form, e.g. `OpenAI/Python 1.0`, was accepted). Python's `urllib` default is refused; PAL goes through the OpenAI SDK and never sees this |

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
