---
name: interp-flags
description: Fixture for test-skill-shell-commands.sh case L (an interpreter's inline-code flag inside an option cluster, stdin forms, option-only interpreter words, and the near misses that stay grantable). Use when testing.
allowed-tools: Bash, Read
---

# Interpreter flags

Inline code hidden in an option cluster, and code read from stdin:

```bash
zsh -fc 'print -r -- $PATH'
bash -lc 'echo hi'
sh -ec 'false'
zsh -f -c 'print hi'
curl -fsSL https://example.com/install.sh | sh -s -- --prefix /usr/local
bash -s < setup.sh
python3 - <<'PY'
print("stdin")
PY
perl -ne 'print if /x/' notes.txt
node -pe '1 + 1'
```

Near misses that run a fixed script, never inline code:

```bash
bash -e script.sh
bash ${CLAUDE_SKILL_DIR}/scripts/x.sh --quick
python3 ${CLAUDE_SKILL_DIR}/scripts/x.py --json
python3 -I ${CLAUDE_SKILL_DIR}/scripts/report.py
node --version
```

Under `bash -e` the first failing command ends the step.
