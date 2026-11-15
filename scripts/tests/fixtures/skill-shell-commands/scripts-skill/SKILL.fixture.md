---
name: scripts-skill
description: Fixture skill that runs bundled scripts, for test-skill-shell-commands.sh. Use when testing.
allowed-tools: Bash(bash *), Read
---

# Run the checks

```bash
bash ${CLAUDE_SKILL_DIR}/scripts/check.sh --home-dir "$HOME"
python3 "${CLAUDE_SKILL_DIR}/scripts/report.py" --json
${CLAUDE_SKILL_DIR}/scripts/direct.sh
"${CLAUDE_SKILL_DIR}/scripts/quoted-direct.sh" video.mp4
```

See REFERENCE.md for the manual fallback.
