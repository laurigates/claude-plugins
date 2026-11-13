---
name: cli-ref
description: Fixture CLI-reference skill for test-skill-shell-commands.sh. Use when testing.
allowed-tools: Bash, Read
---

# jq reference

Filter a file:

```bash
jq '.items[] | .name' data.json
jq -r '.[]' list.json | head -5
jq '.tags | sort | unique' data.json
cat data.json | jq .
```

Pass a variable with `jq --arg name value '.x'`. Prose such as `--arg value`,
`.items[]` or a path like `.claude/settings.json` is not a command.

```python
import json  # a python fence never counts
```

```
Router ──► Shadow
   │
```
