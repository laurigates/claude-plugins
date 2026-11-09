# kitty-plugin

Working inside the [kitty](https://sw.kovidgoyal.net/kitty/) terminal as an
agent: reading other panes through kitty's remote control without disturbing
the user, showing the user an image when the chat cannot draw one, and keeping
kitty sessions recoverable across crashes on macOS.

## Skills

| Skill | Description |
|-------|-------------|
| [kitty-remote-control](skills/kitty-remote-control/SKILL.md) | Read-only `kitty @` commands (`ls`, `get-text`, `get-colors`), notifications, and the commands an agent must never run unasked |
| [kitty-show-image](skills/kitty-show-image/SKILL.md) | Show an image with a note on what to judge, by a file-send tool or a labelled kitty tab (`show-image.sh`) |
| [kitty-session-persistence](skills/kitty-session-persistence/SKILL.md) | Snapshot and restore kitty sessions across WindowServer hangs and force-reboots via `kitten @ ls` and a LaunchAgent (macOS) |

## When to Use

| Scenario | Skill |
|----------|-------|
| Reading a build error in another pane instead of asking for a paste | `kitty-remote-control` |
| Checking whether a `kitty @` command is safe to run | `kitty-remote-control` |
| The user should look at a screenshot or render | `kitty-show-image` |
| `kitty +kitten icat` fails with `open /dev/tty: device not configured` | `kitty-show-image` |
| Terminal sessions vanished after a hard reboot or kitty crash | `kitty-session-persistence` |

## Requirements

- kitty with remote control enabled (`allow_remote_control` and `listen_on` in
  `kitty.conf`), so `$KITTY_LISTEN_ON` reaches the agent's shell
- `jq` for the `kitty @ ls` queries
- `kitty-session-persistence` is macOS-only (LaunchAgents)

## Tests

```bash
just test-skill-scripts
```

runs `skills/kitty-show-image/scripts/tests/test-show-image.sh`, which checks
the script's exit codes without opening a tab.
