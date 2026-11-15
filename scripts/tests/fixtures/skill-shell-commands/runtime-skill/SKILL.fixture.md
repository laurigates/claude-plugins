---
name: runtime-skill
description: Fixture for test-skill-shell-commands.sh case K (table pipes, run-time paths, sudo, runners before a bundled script). Use when testing.
allowed-tools: Bash, Read
---

# Run-time shapes

| Check | Command |
|-------|---------|
| Count rules | `find .claude/rules -name "*.md" \| wc -l` |

```bash
bash $(git rev-parse --show-toplevel)/scripts/claim.sh --agent me
sh ${{ github.action_path }}/install.sh
sudo powermetrics --samplers cpu_power -n 1
timeout 60 ${CLAUDE_SKILL_DIR}/scripts/probe.sh --quick
```
