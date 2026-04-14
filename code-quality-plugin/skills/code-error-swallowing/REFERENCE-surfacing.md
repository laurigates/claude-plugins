# Reference — Context-Aware Error Surfacing

The right way to surface a previously-swallowed error depends on the host
application. This file encodes the decision matrix and the privacy policy
applied to every suggested replacement string.

## Detecting app context

Apply these signals in order; first match wins.

| Order | Signal | Context |
|-------|--------|---------|
| 1 | `.github/workflows/*.yml` / top-level `Makefile` / `justfile` with `ci` target, AND the target file is under `scripts/`, `.github/`, `ci/` | **CI / build script** |
| 2 | `Dockerfile` with `CMD` running a long-lived process, OR `*.service` file, OR `pyproject.toml` with `gunicorn`/`uvicorn`/`celery` entry points | **Daemon / service** |
| 3 | `package.json` with `main`/`types` and no `bin` entry, OR `lib.rs`/`__init__.py` with no `__main__` | **Library** |
| 4 | `index.html` at root, OR `package.json` with `react`/`vue`/`svelte`/`solid` dependency | **Web frontend** |
| 5 | `package.json` with `express`/`fastify`/`hono`/`koa`, OR Django/Flask/FastAPI entry | **Web backend** |
| 6 | `#!/usr/bin/env bash` on file, OR `bin/` directory, OR `package.json` with `bin` entry, OR `pyproject.toml` with `[project.scripts]` | **CLI / shell** |
| 7 | Fallback | **Library** (propagate) |

A single repository can contain multiple contexts (e.g., a CLI plus a web
dashboard). Detect per-file: use signal 1–2 for files matching their
globs, then fall through to signals 3–6 based on the file's directory's
nearest `package.json` / `pyproject.toml` / `Cargo.toml`.

## Surfacing matrix

| App context | Recommended channel | Exit / status | User copy |
|-------------|---------------------|---------------|-----------|
| **CLI / shell** | `echo "<level>: <msg>" >&2` | Non-zero exit on High; continue on Medium | Short, actionable: `"error: could not fetch release; check network"` |
| **Web frontend** | `console.error(detail, err)` + `toast.error(shortCopy)` / banner / tooltip | No HTTP status (client-side); no auto-retry | Short, action-oriented, no stack traces, no URLs |
| **Web backend** | Structured log (`logger.error({err, op}, msg)`) with correlation ID + throw/return 5xx | HTTP 4xx/5xx per semantics | Opaque message + correlation ID: `"Request failed (id: abc123). Contact support."` |
| **Daemon / service** | Structured log + metrics counter increment + optional retry | Internal state only | N/A (no direct user) |
| **Library** | Propagate: `throw` / `return Err` / `raise` / `return error` | N/A | N/A — caller's concern |
| **CI / build script** | `echo "::error file=<f>,line=<l>::<msg>"` (GitHub Actions) or stderr + non-zero exit | Non-zero exit always on High | For CI logs only — assume public readable |

### Frontend split

For web frontend findings, **always split** the surfacing into two calls:

1. Developer channel: `console.error('<op> failed', err)` — verbose, full
   `err` object, stack OK.
2. User channel: a sanitized short-copy `toast`/`banner`/`tooltip`/
   `inline-form-error`.

The generated patch must include both, with the user-channel string run
through the privacy redaction rules below.

## Privacy redaction rules

Apply these to every string that will appear in (a) the report, (b) the
emitted patch, or (c) any log call's message argument (the object
argument passed alongside may remain verbose):

### Rule 1 — Redact env values by name pattern

Replace the *value* of any env variable whose **name** matches:

```
*TOKEN*  *KEY*  *SECRET*  *PASSWORD*
GH_*  GITHUB_*  ANTHROPIC_*  CLAUDE_*
AWS_*  AZURE_*  GCP_*  GOOGLE_*
OPENAI_*  HF_*
```

with `[REDACTED]`. Names are matched case-insensitively.

### Rule 2 — Rewrite absolute home paths

- `$HOME/…` → `~/…`
- `/Users/<user>/…` → `~/…`
- `/home/<user>/…` → `~/…`
- `C:\Users\<user>\…` → `~\…`

### Rule 3 — Truncate to 200 characters

Message payloads longer than 200 chars are cut to 197 + `"..."`. This
prevents a multi-kilobyte stack trace from being echoed into a
user-facing toast.

### Rule 4 — Prefer action-oriented copy

Transform raw stderr forwarding into action-oriented copy:

| Raw | Action-oriented |
|-----|------------------|
| `"ENOTFOUND api.example.com"` | `"Could not reach API. Check your network."` |
| `"401 Unauthorized"` | `"Session expired. Please sign in again."` |
| `"EACCES /var/foo"` | `"Permission denied writing <path>."` |
| `"timeout of 5000ms exceeded"` | `"Request timed out. Try again."` |

When the tool cannot safely translate, keep the raw message *only in the
developer channel* and use a generic short copy for the user channel:
`"Something went wrong. Please try again."`

### Rule 5 — Never forward xtrace output

If the swallowed stream was `set -x` output (shell), do NOT echo it to
stderr after un-swallowing. Replace with a single high-level message.
Detection: the stream being redirected away is the output of a block
preceded by `set -x` with no intervening `set +x`.

## Report / patch embedding

Every generated user-facing string in a patch must be followed by this
inline comment so the human reviewer can polish wording:

```
<inserted-string>  // TODO(error-swallowing): review wording
```

(Use the language's comment syntax: `#` in shell/Python, `//` in JS/TS/Go/
Rust, `--` in SQL.)

## Example end-to-end

Scenario: `release.sh` has `npm publish 2>/dev/null || true`.

- App context → **CI / build script** (file is `.github/workflows/`-adjacent).
- Severity → **High** (`npm publish` matches the High-op regex).
- Channel → `echo "::error::..."` + non-zero exit.
- Redaction → strip any `NPM_TOKEN` value that might leak into the msg.

Patch:

```diff
-npm publish 2>/dev/null || true
+if ! err=$(npm publish 2>&1 >/dev/null); then
+  echo "::error::npm publish failed: ${err:0:200}"  # TODO(error-swallowing): review wording
+  exit 1
+fi
```
