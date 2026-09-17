---
created: 2026-03-03
modified: 2026-09-16
reviewed: 2026-09-16
paths:
  - "**/skills/**"
  - "**/SKILL.md"
  - "scripts/**"
  - ".claude/hooks/**"
---

# Sandbox Guidance for Skill Authors

Claude Code on the web (claude.ai/code) runs in a sandboxed environment with specific constraints. This rule documents those constraints and best practices for writing skills that work in both local and remote environments.

## Environment Detection

### `CLAUDE_CODE_REMOTE`

Set to `"true"` when Claude Code is running in a web/remote session. Not set (or empty) in local CLI sessions.

```bash
# Defensive form — avoids unbound variable errors under set -u
if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  exit 0  # Skip in local sessions
fi
# Remote-only logic here
```

Use the defensive `${CLAUDE_CODE_REMOTE:-}` form in scripts (rather than `$CLAUDE_CODE_REMOTE`) to avoid `unbound variable` errors when `set -u` is active.

### Smoke-Testing Remote Behavior Locally

Simulate the remote environment without needing a web session:

```bash
CLAUDE_CODE_REMOTE=true bash scripts/install_pkgs.sh
```

Run twice to verify idempotency:

```bash
CLAUDE_CODE_REMOTE=true bash scripts/install_pkgs.sh  # installs
CLAUDE_CODE_REMOTE=true bash scripts/install_pkgs.sh  # should skip (already installed)
```

---

## Network Access

The web sandbox enforces a **"Limited" network allowlist**. Skills must only download from these confirmed-reachable domains:

| Domain | Used For |
|--------|----------|
| `github.com` | Release binaries, git operations |
| `raw.githubusercontent.com` | Install scripts (e.g., helm get-helm-3) |
| `releases.hashicorp.com` | Terraform, vault binaries |
| `pypi.org` | Python packages via pip |

**Do not assume** npm registry (`registry.npmjs.org`), Docker Hub, arbitrary apt mirrors, or other CDNs are reachable.

> **Note (2.1.243)**: The sandboxed Bash tool prompt no longer enumerates the allowed hosts. A request to an unlisted host is now attempted (and surfaces an approval prompt) rather than assumed pre-blocked, so skill authors should not treat the domain table above as an exhaustive hard allowlist derivable from the tool's own prompt.

### Network Mode Configuration

Network access mode is configured in the Claude Code web UI settings — not via code. If a skill requires access beyond the "Limited" allowlist, document this requirement explicitly and instruct users to enable "Full" network access in their web session settings.

---
### Denied Domains

`sandbox.network.deniedDomains` blocks specific domains even when a broader allowedDomains wildcard permits them (2.1.113+):

```json
{
  "sandbox": {
    "network": {
      "deniedDomains": ["evil.example.com", "*.tracking.io"]
    }
  }
}
```

Use to carve out exceptions from broad allow wildcards without restricting other traffic.

### Strict Allowlist — no prompting for non-allowlisted hosts (2.1.219+)

`sandbox.network.strictAllowlist: true` denies any host not on `sandbox.network.allowedDomains` outright, with no permission-prompt fallback. Use when a skill must never reach an unexpected host, even with user approval.

### Per-Command Network Grants — `allowed_domains` (2.1.271+)

Under auto mode with sandboxing, a `Bash`/`PowerShell`/`Monitor` call can carry `allowed_domains`: the hosts that one command needs are reviewed alongside the call itself and opened for it alone, rather than granted against the session-wide allowlist. This is a narrower, per-invocation network grant model distinct from the static domain table above — relevant when authoring a skill that runs under auto mode.

## Filesystem

### Writable Paths

| Path | Notes |
|------|-------|
| `/usr/local/bin` | Writable without sudo; use for binary installs |
| `$TMPDIR` / `mktemp -d` | Standard temp directory; clean up after use |
| `$CLAUDE_PROJECT_DIR` | Project working directory |

The sandbox runs as **root**, so `sudo` is unnecessary for writes to `/usr/local/bin`.

### Git Worktree Write Allowlist (2.1.149+)

When working in a git worktree, the sandbox write allowlist previously covered the **entire main repo root**, letting sandboxed commands write anywhere in the primary checkout. As of 2.1.149 it is narrowed to only the shared `.git` directory — and even there, `hooks/` and `config` are denied. Sandboxed writes that relied on reaching back into the main repo from a worktree will now be blocked; scope writes to the worktree itself.

A separate Linux sandbox bug (fixed 2.1.239) made a nonexistent `.git/config.worktree` file unreadable in repos with `extensions.worktreeConfig` set, breaking every sandboxed git command in those worktrees. If sandboxed git commands in a linked worktree failed mysteriously before 2.1.239, this was the cause — no workaround is needed on current versions.

### Sandbox Startup Robustness (2.1.176+ / 2.1.178+ / 2.1.179+)

A run of fixes made the Linux sandbox tolerate common repo shapes that previously broke startup or bloated the Bash tool description:

| Version | Fix |
|---------|-----|
| 2.1.176 | Linux sandbox no longer fails to start when `.claude/settings.json` is a **symlink with an absolute target** (common in dotfile/chezmoi setups where settings are symlinked from a managed location). |
| 2.1.178 | Linux sandbox no longer fails to start when `.claude/skills` or `.claude/hooks` is a **symlink** (e.g. shared skill/hook directories linked into a repo). |
| 2.1.179 | A `sandbox.denyRead`/`allowRead` glob spanning a **large directory tree** no longer expands into an enormous Bash tool description — the glob is kept compact instead of enumerating every matched path, which had been inflating per-turn context. |

If a sandboxed session previously failed to start in a repo that symlinks `.claude/` paths, that should now work without unlinking them.

### Apple Events on macOS — `sandbox.allowAppleEvents` (2.1.181+)

`sandbox.allowAppleEvents` is an **opt-in** setting that lets sandboxed commands send Apple Events on macOS (e.g. to script Finder, Terminal, or another app via `osascript`). It is off by default because Apple Events cross the app-isolation boundary; enable it only for commands that genuinely need to drive another macOS app:

```json
{
  "sandbox": {
    "allowAppleEvents": true
  }
}
```

macOS-only — the setting has no effect in the Linux web sandbox.

### Disabling Filesystem Isolation Only — `sandbox.filesystem.disabled` (2.1.216+)

`sandbox.filesystem.disabled: true` skips filesystem sandboxing while keeping network egress control active — useful when a skill needs unrestricted local file access (e.g. tooling that writes outside the working directory) but should still have its outbound network traffic gated.

### Deny Rule Matching and Violation Detail (2.1.224+)

A `denyRead`/`denyWrite` glob is matched with or without a trailing slash as of 2.1.224 — `~/.aws/` and `~/.aws` deny identically (a bare trailing slash was previously silently bypassable on Linux and macOS). When a sandboxed command is denied, the Bash tool result now includes which file or network access was denied and why, instead of a bare failure — read that detail before retrying a blocked command differently (see `.claude/rules/handling-blocked-hooks.md`).

### Temp Directory Pattern

```bash
tmp_dir=$(mktemp -d)
# ... download and extract to tmp_dir ...
cp binary "$tmp_dir/binary" /usr/local/bin/
rm -rf "$tmp_dir"
```

### `$TMPDIR` Consistency (2.1.154+)

Before 2.1.154, `$TMPDIR` could resolve to **different directories** in sandboxed vs unsandboxed Bash commands within the same session — a file written to `$TMPDIR` by one command was not necessarily visible to the next. As of 2.1.154 `$TMPDIR` resolves to the same path across both, so handing a temp path between sandboxed and unsandboxed steps is safe.

---

## Base Image

The web sandbox base image includes standard language runtimes and system tools but **does not** include infrastructure/DevOps tooling.

### Available by Default

| Tool | Notes |
|------|-------|
| `bash`, `curl`, `tar`, `gzip` | Standard shell utilities |
| `apt` | Package manager (e.g., install `unzip`) |
| `pip` | Python package manager |
| Python, Node.js, Go, Rust runtimes | Language toolchains |
| `git` | Version control |
| `jq` | JSON processing |

### Requires Explicit Install via SessionStart Hook

| Tool | Install Method |
|------|---------------|
| `helm` | `raw.githubusercontent.com` install script |
| `terraform` | Binary from `releases.hashicorp.com` (`.zip`) |
| `tflint` | GitHub release binary (`.zip`) |
| `actionlint` | GitHub release binary (`.tar.gz`) |
| `helm-docs` | GitHub release binary (`.tar.gz`) |
| `gitleaks` | GitHub release binary (`.tar.gz`) |
| `just` | GitHub release binary (`.tar.gz`) |
| `pre-commit` | `pip install pre-commit` |
| `unzip` | `apt-get install -y unzip` (needed for `.zip` extractions) |

---

## Environment Variables

| Variable | Set When | Purpose |
|----------|----------|---------|
| `CLAUDE_CODE_REMOTE` | Web sessions only | `"true"` in remote sessions |
| `CLAUDE_ENV_FILE` | Always (when hooks run) | File path for persisting env vars across hook calls |
| `CLAUDE_PROJECT_DIR` | Always (hooks, MCP stdio servers as of 2.1.139) | Project root directory; plugin configs can reference `${CLAUDE_PROJECT_DIR}` in commands |
| `CLAUDE_PLUGIN_ROOT` | Frontmatter hooks only | Root of the loaded plugin |
| `CLAUDE_CODE_DISABLE_CRON` | Set to stop scheduled cron jobs mid-session (2.1.72+) | Session cron management |
| `CLAUDE_CODE_SESSION_ID` | Always (incl. stdio MCP server subprocesses as of 2.1.154) | Session ID matching hook `session_id` -- available in Bash tool subprocesses (2.1.132+) |
| `CLAUDECODE` | Stdio MCP server subprocesses (2.1.154+) | Set to `1` so MCP servers can detect they were launched by Claude Code |
| `CLAUDE_CODE_SAFE_MODE` | Troubleshooting (2.1.169+) | Equivalent to the `--safe-mode` flag — starts Claude Code with **all customizations disabled** (CLAUDE.md, plugins, skills, hooks, MCP servers) |
| `CLAUDE_CODE_SUBPROCESS_ENV_SCRUB` | Set to `1` (2.1.83+) | Strips Anthropic and cloud-provider credentials from subprocess environments (Bash tool, hooks, MCP stdio servers) |

> **Note (2.1.169) — Safe mode for troubleshooting**: the `--safe-mode` flag (and the `CLAUDE_CODE_SAFE_MODE` env var) starts a session with every customization disabled — CLAUDE.md, plugins, skills, hooks, and MCP servers all off. Use it to bisect whether a misbehaviour comes from the harness itself or from a custom skill/hook/plugin: if the problem vanishes in safe mode, it's in your customizations. Because skills and hooks are inert in safe mode, do not rely on a SessionStart install hook in a safe-mode session — install tools manually.

> **Note (2.1.139)**: `CLAUDE_PROJECT_DIR` is now passed to MCP stdio servers (matching the hook environment). Plugin `mcpServers` configs can reference `${CLAUDE_PROJECT_DIR}` in `command` / `args` / `env` without having to compute the path inside the server.
>
> **Note (2.1.154)**: Stdio MCP server subprocesses also receive `CLAUDE_CODE_SESSION_ID` (the current session ID) and `CLAUDECODE=1` in their environment, so a server can correlate work with the session and detect that it was launched by Claude Code.

### Persisting Environment Variables

Variables set inside a hook script do not automatically persist to Claude's tool calls. Use `CLAUDE_ENV_FILE` to persist them:

```bash
if [ -n "$CLAUDE_ENV_FILE" ]; then
  echo "PATH=/usr/local/bin:$PATH" >> "$CLAUDE_ENV_FILE"
  echo "NODE_ENV=development" >> "$CLAUDE_ENV_FILE"
fi
```

### PATH Bootstrap for Agent Subshells

Agent subshells spawned by the harness do **not** source the user's interactive shell config (`~/.zshrc`, `~/.bash_profile`). They start with a `/usr/bin:/bin`-only PATH and report `command not found: head` / `command not found: jq` even though the parent CLI shell has both. The fix is a SessionStart hook that prepends Homebrew bin directories to PATH via `$CLAUDE_ENV_FILE`. Guard each candidate directory with `[ -d ]` so the same script is safe in remote sandboxes where `/opt/homebrew` may not exist.

```bash
# scripts/path-bootstrap.sh
if [ -z "${CLAUDE_ENV_FILE:-}" ]; then exit 0; fi

prepend=""
for dir in /opt/homebrew/bin /opt/homebrew/sbin /usr/local/bin /usr/local/sbin; do
  [ -d "$dir" ] || continue
  case ":${PATH:-}:" in *":$dir:"*) continue ;; esac
  prepend="${prepend:+$prepend:}$dir"
done

if [ -n "$prepend" ]; then
  printf 'PATH=%s:%s\n' "$prepend" "${PATH:-/usr/bin:/bin}" >> "$CLAUDE_ENV_FILE"
fi
```

Wire it into `.claude/settings.json` under `hooks.SessionStart` with an empty matcher so it runs on every session start (including resumes and `/clear`).

---

## SessionStart Hook Patterns

### Standard Remote Install Script

```bash
#!/bin/bash
# scripts/install_pkgs.sh
# Remote guard — exit immediately in local sessions
if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  exit 0
fi

# Idempotency guard per tool
if ! command -v helm >/dev/null 2>&1; then
  curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
fi

if ! command -v gitleaks >/dev/null 2>&1; then
  tmp_dir=$(mktemp -d)
  curl -fsSL -o "$tmp_dir/gitleaks.tar.gz" \
    "https://github.com/gitleaks/gitleaks/releases/download/v8.21.2/gitleaks_8.21.2_linux_x64.tar.gz"
  tar -xzf "$tmp_dir/gitleaks.tar.gz" -C "$tmp_dir"
  cp "$tmp_dir/gitleaks" /usr/local/bin/
  rm -rf "$tmp_dir"
fi
```

### Settings.json Hook Configuration

```json
{
  "hooks": {
    "SessionStart": [
      {
        "matcher": "startup",
        "hooks": [
          {
            "type": "command",
            "command": "bash \"$CLAUDE_PROJECT_DIR/scripts/install_pkgs.sh\"",
            "timeout": 120
          }
        ]
      }
    ]
  }
}
```

Use `matcher: "startup"` to run only on new sessions (not on `/clear` or context compaction). Use `once: true` on the hook handler for truly one-time setup.

### Timeout Guidance

| Operation | Recommended Timeout |
|-----------|---------------------|
| Single binary install | 30–60s |
| Multiple tool installs | 120–300s |
| npm/pip dependency install | 120s |
| Full stack setup | 300s |

The default hook timeout is 600 seconds (10 minutes), but explicit timeouts document intent and prevent runaway scripts.

---

## Credential Protection

`sandbox.credentials` (2.1.187+) blocks sandboxed commands from reading credential files and secret environment variables outright.

### Masking Instead of Denying — `mode: "mask"` (2.1.221+)

A credential-file entry can be configured with `mode: "mask"` instead of `deny`. On Linux and WSL, sandboxed commands read a sentinel copy of the file (the whole file, or just the spans an `extract` regex captures), and the sandbox network proxy substitutes the real value only on egress. On macOS, file masking is unsupported and falls back to `deny`.

### Structured Masking (2.1.224+)

Further masking options, all requiring `sandbox.network.tlsTerminate` and honored **only** from user, managed, or `--settings` settings — a project `.claude/settings.json` cannot configure them:

| Option | Masks |
|---|---|
| `extract` / `onExtractNoMatch` | A substring inside a structured env value |
| `decode: "jwt"` + `maskClaims` | Specific JWT claims |
| `awsPairs` / `sigv4` | Re-signs AWS requests after masking the underlying credential |

## Auto-Allow in Sandbox

### `autoAllowBashIfSandboxed` and Shell Expansions (2.1.139+)

The `autoAllowBashIfSandboxed` setting auto-approves Bash tool calls when the harness is running in a sandboxed environment. Before 2.1.139, the auto-approval **skipped** commands containing shell expansions like `$VAR` or `$(cmd)` — those still surfaced a permission prompt even though they were sandbox-safe. The fix means a sandboxed session no longer prompts for routine `git diff $(git merge-base HEAD origin/main)`-style invocations.

If you previously worked around the gap with explicit `Bash(... $VAR ...)` allow rules, you can remove them.

### `NO_COLOR` / `FORCE_COLOR` Scoping (2.1.143+)

Setting `NO_COLOR` or `FORCE_COLOR` under `env` in `settings.json` previously also stripped Claude Code's own UI colours, because the variable was exported into the harness process. As of 2.1.143, these two variables are passed only to **subprocesses** — the harness UI keeps its colours. Configure them for tools (linters, formatters) without losing CLI usability:

```json
{
  "env": {
    "NO_COLOR": "1"
  }
}
```

### Managed-Only Sandbox Binary Overrides — `sandbox.ripgrep` (2.1.232+)

`sandbox.ripgrep` (the sandbox's ripgrep binary path) is honored only from user, managed, or `--settings` settings as of 2.1.232 — a project `.claude/settings.json` entry is ignored. The same restriction applies to `sandbox.bwrapPath`/`sandbox.socatPath`, and managed-settings overrides of any of the three now require explicit approval.

### Failing Closed When the Sandbox Can't Start — `sandbox.failIfUnavailable` (2.1.83+)

`sandbox.failIfUnavailable` exits with an error when the sandbox is enabled but cannot start, instead of silently running the command unsandboxed. Use it when a hard failure is preferable to an unnoticed unsandboxed fallback.

## Multi-Agent Patterns in Sandbox

### Push Delegation

Sub-agents (spawned via the `Task` tool) can encounter TLS errors or sandbox blocks when performing `git push` or PR creation operations. Always delegate push/PR operations to the orchestrator agent:

```markdown
## Execution

1. Sub-agents: implement changes in worktrees, commit locally
2. Orchestrator: collect results, then push and create PRs sequentially
```

Do NOT allow sub-agents to push independently in web sessions.

---

## Skills That Work in Both Environments

### Decision Table

| Skill behavior | Local | Remote (web) |
|----------------|-------|--------------|
| Filesystem reads | ✓ Same | ✓ Same |
| `git status`, `git diff` | ✓ Same | ✓ Same |
| `git push` | ✓ Same | ⚠ Delegate to orchestrator in multi-agent |
| Install tools | N/A (pre-installed) | ✓ Via SessionStart hook |
| Network fetch (github.com) | ✓ | ✓ (in allowlist) |
| Network fetch (arbitrary) | ✓ | ✗ (blocked) |
| `/usr/local/bin` writes | ✓ | ✓ (runs as root) |

### Conditional Behavior Pattern

For skills that need different behavior in local vs remote:

```bash
#!/bin/bash
if [ "${CLAUDE_CODE_REMOTE:-}" = "true" ]; then
  # Remote-specific path
  INSTALL_DIR="/usr/local/bin"
  DOWNLOAD_TIMEOUT=30
else
  # Local path — assume tool is pre-installed
  if ! command -v mytool >/dev/null 2>&1; then
    echo "mytool not found. Install it with: brew install mytool" >&2
    exit 1
  fi
fi
```

---

## Quick Reference

### Remote Guard (copy-paste ready)

```bash
if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then exit 0; fi
```

### Idempotency Guard (copy-paste ready)

```bash
if ! command -v <tool> >/dev/null 2>&1; then
  # install <tool>
fi
```

### Allowed Download Domains

```
github.com
raw.githubusercontent.com
releases.hashicorp.com
pypi.org
```

### Related Skills

- `/configure:web-session` — automates SessionStart hook setup for infrastructure tools
- `/hooks:session-start-hook` — generates SessionStart hooks for language dependencies

## Related Rules

- `.claude/rules/hooks-reference.md` — complete hook event reference and `CLAUDE_CODE_REMOTE` definition
- `.claude/rules/shell-scripting.md` — safe shell patterns for hook scripts
- `.claude/rules/skill-development.md` — skill creation patterns



