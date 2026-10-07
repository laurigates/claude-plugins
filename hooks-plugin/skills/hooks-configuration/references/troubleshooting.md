# Hook troubleshooting

## Debugging

| Error | Cause | Fix |
|-------|-------|-----|
| Hook cancelled | Timeout exceeded | Add `"timeout"` field or use background subshell pattern |
| Hook failed | Script error | Check exit code; add error handling |
| Command not found | Missing script | Verify script path and permissions |
| Permission denied | Script not executable | `chmod +x ~/.claude/script.sh` |

Use `/hooks` to verify registration, `claude --debug` for verbose logging, and `echo '{"tool_input":{"command":"..."}}' | bash your-hook.sh` to test manually. Check `$?` for exit code. See `hooks/README.md` for plugin hook documentation.
