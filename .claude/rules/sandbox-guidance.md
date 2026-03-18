---
created: 2026-03-03
modified: 2026-03-03
reviewed: 2026-03-03
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

### Network Mode Configuration

Network access mode is configured in the Claude Code web UI settings — not via code. If a skill requires access beyond the "Limited" allowlist, document this requirement explicitly and instruct users to enable "Full" network access in their web session settings.

---

## Filesystem

### Writable Paths

| Path | Notes |
|------|-------|
| `/usr/local/bin` | Writable without sudo; use for binary installs |
| `$TMPDIR` / `mktemp -d` | Standard temp directory; clean up after use |
| `$CLAUDE_PROJECT_DIR` | Project working directory |

The sandbox runs as **root**, so `sudo` is unnecessary for writes to `/usr/local/bin`.

### Temp Directory Pattern

```bash
tmp_dir=$(mktemp -d)
# ... download and extract to tmp_dir ...
cp binary "$tmp_dir/binary" /usr/local/bin/
rm -rf "$tmp_dir"
```

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
| `CLAUDE_PROJECT_DIR` | Always | Project root directory |
| `CLAUDE_PLUGIN_ROOT` | Frontmatter hooks only | Root of the loaded plugin |
| `CLAUDE_CODE_DISABLE_CRON` | Set to stop scheduled cron jobs mid-session (2.1.72+) | Session cron management |

### Persisting Environment Variables

Variables set inside a hook script do not automatically persist to Claude's tool calls. Use `CLAUDE_ENV_FILE` to persist them:

```bash
if [ -n "$CLAUDE_ENV_FILE" ]; then
  echo "PATH=/usr/local/bin:$PATH" >> "$CLAUDE_ENV_FILE"
  echo "NODE_ENV=development" >> "$CLAUDE_ENV_FILE"
fi
```

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
