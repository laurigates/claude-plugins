---
name: edge-cases
description: Fixture for test-skill-shell-commands.sh cases G (lone words) and H (quoted scripts). Use when testing.
allowed-tools: Bash, Read
---

# Edge cases

The `magick` command converts images. Mention first, arguments after.

```bash
magick in.png -resize 50% out.png
identify -verbose out.png
```

Arguments first, mention after: `identify` reads metadata.

Only ever named, never run with arguments: `convert`.

The same bundled script, quoted and unquoted:

```bash
bash "${CLAUDE_SKILL_DIR}/scripts/run.sh" --all
bash ${CLAUDE_SKILL_DIR}/scripts/run.sh --one
python3 '${CLAUDE_SKILL_DIR}/scripts/single.py' --json
```
