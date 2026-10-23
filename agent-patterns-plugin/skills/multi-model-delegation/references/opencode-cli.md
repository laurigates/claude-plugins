# Multi-Model Delegation — Driving the `opencode` CLI Unattended

Open this before scripting `opencode run` to get a review or consult from a
non-Claude model with no human at the terminal. Measured on opencode 1.19.3,
macOS, 2026-10-21, while trying to review six PR diffs with free models.

**Short version:** for unattended diff review, send a plain chat request with
no agent loop — PAL `chat` with a model it can reach, or the direct gateway
route in [REFERENCE.md](../REFERENCE.md#calling-the-opencode-go-gateway-directly).
`opencode run` drives an agent that can stop on a permission prompt nobody
answers, and the free tier cannot be reached any other way. In the session
behind this file, none of the six reviews completed through opencode; they were
run with Claude subagents instead.

## CLI and runtime traps

| Trap | Symptom | Fix |
|---|---|---|
| `-f` is an array option | `opencode run -f diff.patch "review this"` fails with `Error: File not found: review this` — the message was taken as a second file | Put the message before `-f`, or end the array with `--` |
| Parallel runs share one SQLite store (`~/.local/share/opencode/opencode.db`) | Of six concurrent `opencode run` processes, one failed `database is locked` and five hung with empty output until a 20-minute timeout | Run sequentially |
| A `-f` file outside the working directory triggers the `external_directory` permission | The log stops after `init`, with no further lines even at `--log-level DEBUG`, and the run never returns. The user config set `external_directory: ask`, and `opencode run` has no one to answer | Put inputs inside the run directory, or inline them in the message |
| Review-style prompts stall the same way | A multi-paragraph instruction ("report findings with severity…") stalled even with the diff inline, while a one-line instruction over the same 128-line diff ("count the files… reply with the number") answered in 3 s | Inference, not confirmed: the default `build` agent (`"*": allow`, but `doom_loop` and `external_directory` set to `ask`, plus a question tool) reaches an `ask` that nobody answers. `--auto` approves asks, but it also lets the model's agent read outside the directory, including the home directory and `auth.json` |
| `.opencode/agent/<name>.md` in a scratch directory | In an empty, non-git directory, `opencode agent list` did not show the agent | Define it under the `"agent"` key of a project `opencode.json`, which was loaded |

## Provider and model traps

| Trap | Symptom | Fix |
|---|---|---|
| The OpenCode Zen free tier only serves OpenCode itself | A direct `POST https://opencode.ai/inference/openai/v1/chat/completions` with the stored key returned Cloudflare `403 error code: 1010` under Python's User-Agent (the same block as the Go gateway row in [REFERENCE.md](../REFERENCE.md#calling-the-opencode-go-gateway-directly)), then `FreeTierError: OpenCode's free tier can only be used from within OpenCode` under opencode's User-Agent. A tool-less custom agent (`tools: {"*": false}` in a project `opencode.json`) got the same `FreeTierError` | The tier appears to require OpenCode's own agent prompt, so removing the tools also removes eligibility. Do not work around the gate; use a paid key or another route |
| An expired `opencode-go` key | `opencode-go/*` models fail with `This API key has expired… Signing in again will not renew this key` | Renew the key in the OpenCode Console. The `opencode/` (Zen) provider offers the same free model ids |
| A free preview endpoint can be down while its siblings answer | `longcat-2.5-preview-free` returned `Upstream request failed: Endpoint is unavailable` for every prompt, while `beam-free` answered | Send a one-word prompt to each model before batching |
