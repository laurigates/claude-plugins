#!/usr/bin/env bash
# Build a neutral throwaway "repository" for the config sweep to run in.
#
# Why a fixture instead of the real repo: the sweep must run from a cwd with NO
# .mcp.json and NO project .claude in its ancestry, or (a) project MCP servers
# load ~90k of tool schemas and (b) the project's enabledPlugins leak skills
# into even the clean arm — both destroy the isolation. A self-contained repo
# under /tmp has neither. It carries just enough tree for the read-only probes:
# markdown under docs/ (01), a README (02), a searchable source file (04), and
# git history (06).
set -euo pipefail

dest="${1:?usage: make-fixture.sh <dest-dir>}"
rm -rf "$dest"
mkdir -p "$dest/docs" "$dest/src" "$dest/.claude-plugin"
cd "$dest"

cat > README.md <<'EOF'
# Sample Service

A tiny fixture repository for claude-probe config-isolation runs.

## Overview

This repo exists only so behavior probes have a realistic tree to act on:
markdown under docs/, a source file, and a git history. Nothing here is real.

## Layout

- docs/  design notes
- src/   application code
EOF

cat > docs/architecture.md <<'EOF'
# Architecture

The service is a single module. There is deliberately nothing to see here.
EOF

cat > docs/deployment.md <<'EOF'
# Deployment

Deployed by hand in the fixture. Do not do this at home.
EOF

cat > docs/faq.md <<'EOF'
# FAQ

Q: Is this a real service? A: No, it is a claude-probe fixture.
EOF

cat > src/settings.py <<'EOF'
import os

# Toggle to skip auto-loaded memory files during tests.
CLAUDE_CODE_DISABLE_AUTO_MEMORY = os.environ.get("CLAUDE_CODE_DISABLE_AUTO_MEMORY", "0")
DEBUG = False
EOF

cat > src/main.py <<'EOF'
from settings import DEBUG


def main() -> None:
    print("hello", DEBUG)


if __name__ == "__main__":
    main()
EOF

cat > .claude-plugin/marketplace.json <<'EOF'
{ "name": "sample-marketplace", "owner": "fixture", "plugins": [] }
EOF

git init -q
git config user.email fixture@example.com
git config user.name Fixture
git add -A
git commit -qm "initial fixture"

echo "[make-fixture] sample repo at $dest ($(find . -type f -not -path './.git/*' | wc -l | tr -d ' ') files)"
