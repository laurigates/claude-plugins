---
name: kitty-session-persistence
description: Snapshot and restore kitty terminal sessions across crashes, reboots, and GUI hangs on macOS. Use when you want to survive WindowServer hangs without losing open tabs, configure a periodic kitty session snapshot, or restore a snapshot after a force-reboot.
user-invocable: false
allowed-tools: Bash(kitty *), Bash(kitten *), Bash(launchctl *), Bash(uname *), Bash(plutil *), Bash(test *), Read, Write, Edit, Grep, Glob
created: 2026-05-03
modified: 2026-05-03
reviewed: 2026-05-03
---

# Kitty Session Persistence (macOS)

## When to Use This Skill

| Use this skill when... | Use something else when... |
|------------------------|----------------------------|
| Terminal sessions need to survive WindowServer hangs and force-reboots | The user's terminal is iTerm2 / Terminal.app / Ghostty / Wezterm — kitty-specific |
| Configuring kitty's `listen_on` socket and a snapshot LaunchAgent | Cross-platform terminal config — this is macOS LaunchAgents |
| Restoring a previous session after a crash | One-off "open these tabs" — `kitty @ launch` directly is enough |
| Auditing whether snapshot capture is still running | General system diagnostics — see `macos-incident-postmortem` |

## Platform Guard

This skill is **macOS-only**. All commands assume Darwin and `launchctl`-managed LaunchAgents. Refuse to act if `uname -s` is not `Darwin`.

```bash
test "$(uname -s)" = "Darwin" || { echo "macos-plugin: not Darwin, refusing"; exit 1; }
```

## Core Expertise

Kitty exposes a remote control protocol via a Unix socket. With `listen_on` configured, `kitten @ ls` returns a JSON description of every OS window, tab, and window inside kitty — enough to reconstruct the layout from scratch.

The pattern this skill installs:

1. **Always-listen socket** — `listen_on unix:/tmp/kitty-$USER` in `kitty.conf` so the snapshot script can always reach the running instance.
2. **Snapshot script** — captures `kitten @ ls` output to a timestamped JSON file under `~/.local/state/kitty-sessions/`, with a `latest.json` symlink.
3. **LaunchAgent** — runs the snapshot script every 5 minutes (default) so the worst-case loss is one window of work.
4. **Restore command** — reads `latest.json` and re-launches tabs with the recorded `cwd` and command.

### Architectural notes

- Kitty's remote control requires `allow_remote_control yes` in `kitty.conf` **or** `--allow-remote-control yes` at launch.
- The socket path must match between `listen_on` and the `kitten @ --to` flag the snapshot script uses.
- LaunchAgent `StandardOutPath` and `StandardErrorPath` are essential — failing snapshots are otherwise silent.
- Use `RunAtLoad: false` and rely on `StartInterval` so a kitty restart doesn't spawn a backlog of immediate snapshots.

## Setup

### 1. Configure kitty

Add to `~/.config/kitty/kitty.conf`:

```conf
allow_remote_control yes
listen_on unix:/tmp/kitty-{kitty_pid}
```

Using `{kitty_pid}` makes each kitty instance addressable on its own socket. For the persistent-socket pattern this skill needs, use the user-stable form instead:

```conf
allow_remote_control yes
listen_on unix:/tmp/kitty-USER
```

Replace `USER` with the actual username. The snapshot LaunchAgent points at this exact path.

Reload kitty after editing:

```bash
kitty @ --to unix:/tmp/kitty-USER load-config
```

### 2. Install the snapshot script

Create `~/.local/bin/kitty-snapshot` (mode 0755):

```bash
#!/usr/bin/env bash
set -uo pipefail

[ "$(uname -s)" = "Darwin" ] || exit 0

SOCKET="unix:/tmp/kitty-${USER}"
STATE_DIR="${HOME}/.local/state/kitty-sessions"
mkdir -p "$STATE_DIR"

ts="$(date -u +%Y%m%dT%H%M%SZ)"
out="${STATE_DIR}/${ts}.json"

if ! kitten @ --to "$SOCKET" ls >"$out" 2>>"${STATE_DIR}/snapshot.err"; then
  rm -f "$out"
  exit 0   # kitty not running — silent success
fi

ln -sfn "$out" "${STATE_DIR}/latest.json"

# Keep ~7 days of 5-min snapshots = 2016 files; cap at 4032 (14 days)
ls -1t "$STATE_DIR"/*.json 2>/dev/null | tail -n +4033 | xargs -r rm -f
```

The `exit 0` on `kitten @ ls` failure is intentional — the LaunchAgent fires every 5 minutes regardless of whether kitty is running.

### 3. Install the LaunchAgent

Write `~/Library/LaunchAgents/com.<reverse-dns>.kitty-snapshot.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>com.example.kitty-snapshot</string>
  <key>ProgramArguments</key>
  <array>
    <string>/Users/USER/.local/bin/kitty-snapshot</string>
  </array>
  <key>StartInterval</key>
  <integer>300</integer>
  <key>RunAtLoad</key>
  <false/>
  <key>StandardOutPath</key>
  <string>/Users/USER/.local/state/kitty-sessions/launchd.out</string>
  <key>StandardErrorPath</key>
  <string>/Users/USER/.local/state/kitty-sessions/launchd.err</string>
</dict>
</plist>
```

Replace `com.example` with a stable reverse-DNS prefix and `USER` with the literal username (LaunchAgents do not expand `$HOME`).

Validate, load, and verify:

```bash
plutil -lint ~/Library/LaunchAgents/com.example.kitty-snapshot.plist
launchctl bootstrap "gui/$(id -u)" ~/Library/LaunchAgents/com.example.kitty-snapshot.plist
launchctl print "gui/$(id -u)/com.example.kitty-snapshot" | grep -E 'state|last exit'
```

`bootstrap` replaces the deprecated `launchctl load`; on macOS 11+ prefer it.

### 4. Confirm capture is working

After ~5 minutes:

```bash
ls -lt ~/.local/state/kitty-sessions/*.json | head -3
```

There should be JSON files newer than the LaunchAgent install time. The newest file's content should match what kitty has open right now.

## Restore

Read `latest.json` and re-launch each window/tab. A minimal restore script:

```bash
#!/usr/bin/env bash
set -euo pipefail

[ "$(uname -s)" = "Darwin" ] || exit 1

LATEST="${HOME}/.local/state/kitty-sessions/latest.json"
SOCKET="unix:/tmp/kitty-${USER}"

[ -L "$LATEST" ] || { echo "no snapshot found"; exit 1; }

jq -c '.[] | .tabs[] | .windows[] | {cwd, foreground_processes}' "$LATEST" |
while IFS= read -r win; do
  cwd=$(printf '%s' "$win" | jq -r '.cwd')
  cmd=$(printf '%s' "$win" | jq -r '.foreground_processes[0].cmdline | join(" ")')
  kitten @ --to "$SOCKET" launch --type=tab --cwd="$cwd" "$cmd"
done
```

The shape of `kitten @ ls` output is `[{tabs:[{windows:[{cwd, foreground_processes:[{cmdline}]}]}]}]`. Adjust the `jq` query if a future kitty release changes it.

## Common Patterns

### Audit recent snapshots

```bash
ls -1t ~/.local/state/kitty-sessions/*.json | head -10
jq '. | length, [.[].tabs | length] | add' ~/.local/state/kitty-sessions/latest.json
# → window count, tab count
```

### Confirm LaunchAgent is healthy

```bash
launchctl print "gui/$(id -u)/com.example.kitty-snapshot" | \
  grep -E 'state|last exit|on demand'
```

`state = running` (briefly, every 5 minutes) and `last exit code = 0` indicate health. Persistent non-zero exit means something is broken — check `launchd.err`.

### Disable / unload temporarily

```bash
launchctl bootout "gui/$(id -u)/com.example.kitty-snapshot"
```

`bootout` is the modern equivalent of `launchctl unload`.

### Snapshot interval tuning

| Interval | When to use |
|----------|-------------|
| 60s (`StartInterval=60`) | Heavy editing days — minimum loss-on-crash |
| 300s (default) | Balanced — typical workflow |
| 900s (15 min) | Stable, low-edit days — less noise in `ls -lt` |

Reload after editing the plist:

```bash
launchctl bootout "gui/$(id -u)/com.example.kitty-snapshot"
launchctl bootstrap "gui/$(id -u)" ~/Library/LaunchAgents/com.example.kitty-snapshot.plist
```

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Snapshot count last hour | `find ~/.local/state/kitty-sessions -name '*.json' -newermt '1 hour ago' \| wc -l` |
| Most recent snapshot age | `stat -f '%Sm %N' ~/.local/state/kitty-sessions/latest.json` |
| Validate a plist | `plutil -lint ~/Library/LaunchAgents/com.example.kitty-snapshot.plist` |
| Last exit code | `launchctl print "gui/$(id -u)/com.example.kitty-snapshot" \| awk '/last exit code/{print $NF}'` |
| Live socket reachable | `kitten @ --to unix:/tmp/kitty-$USER ls \| jq '. \| length'` |

## Quick Reference

### LaunchAgent commands (macOS 11+)

| Operation | Command |
|-----------|---------|
| Load (modern) | `launchctl bootstrap "gui/$(id -u)" <plist>` |
| Unload (modern) | `launchctl bootout "gui/$(id -u)/<label>"` |
| Inspect | `launchctl print "gui/$(id -u)/<label>"` |
| Run now | `launchctl kickstart -k "gui/$(id -u)/<label>"` |
| List user agents | `launchctl print-disabled "gui/$(id -u)"` |

### Kitty remote control

| Operation | Command |
|-----------|---------|
| List sessions | `kitten @ --to <socket> ls` |
| Launch tab | `kitten @ --to <socket> launch --type=tab --cwd=<path> <cmd>` |
| Reload config | `kitten @ --to <socket> load-config` |
| Send text | `kitten @ --to <socket> send-text --match "title:foo" "ls\n"` |

### Snapshot file structure

```
~/.local/state/kitty-sessions/
├── 20260503T120000Z.json
├── 20260503T120500Z.json
├── ...
├── latest.json -> 20260503T143000Z.json
├── snapshot.err
├── launchd.out
└── launchd.err
```

## Error Handling

| Symptom | Cause | Fix |
|---------|-------|-----|
| `kitten @ ls` fails with "remote control not allowed" | `allow_remote_control no` in `kitty.conf` | Set to `yes`, reload config |
| LaunchAgent loads but `last exit code = 78` | Script not executable | `chmod +x ~/.local/bin/kitty-snapshot` |
| LaunchAgent loads but never fires | `StartInterval` missing or zero | Set to a positive integer (seconds) |
| All snapshots empty `[]` | No kitty windows running, or wrong socket path | Check `listen_on` path matches `--to` |
| `bootstrap` fails with "already loaded" | Old `load` form still active | `launchctl bootout` first, then bootstrap |
| Restore opens windows with wrong shell | `cmdline[0]` is the shell, not the user command | Use `cwd` only and let the user re-run |
