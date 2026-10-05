# Settings Hook and Summary Reference

Used by Step 5 (update `.claude/settings.json`) and Step 6 (verify and summarise).

## SessionStart hook entry (Step 5)

1. Read existing `.claude/settings.json` (or start from `{}` if absent)
2. Add or merge the `SessionStart` hook:

```json
"hooks": {
  "SessionStart": [
    {
      "matcher": "",
      "hooks": [
        {
          "type": "command",
          "command": "bash \"$CLAUDE_PROJECT_DIR/scripts/install_pkgs.sh\""
        }
      ]
    }
  ]
}
```

3. Preserve all existing `permissions` and other keys — do not overwrite them.

## Final summary template (Step 6)

Print a final summary:

```
Web session configuration complete
===================================
scripts/install_pkgs.sh  [CREATED/UPDATED]
.claude/settings.json    [CREATED/UPDATED]

Tools configured: helm, terraform, tflint, actionlint, gitleaks, just, pre-commit

Next steps:
1. Commit both files: git add scripts/install_pkgs.sh .claude/settings.json
2. Smoke-test locally: CLAUDE_CODE_REMOTE=true bash scripts/install_pkgs.sh
3. Run again to verify idempotency: CLAUDE_CODE_REMOTE=true bash scripts/install_pkgs.sh
4. Start a remote session on claude.ai/code and confirm tools are available
```
