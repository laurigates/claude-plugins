# Frontmatter hooks example

```yaml
---
name: my-skill
description: A skill with hooks
allowed-tools: Bash, Read
hooks:
  PreToolUse:
    - matcher: "Bash"
      hooks:
        - type: command
          command: "echo 'Pre-tool hook from skill'"
          timeout: 10
---
```
