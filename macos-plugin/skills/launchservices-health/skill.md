---
name: launchservices-health
description: Diagnose macOS LaunchServices DB bloat and launchservicesd CPU issues. Use when launchservicesd is pegged at high CPU, the LS database feels bloated after long uptime, or you suspect LaunchServices is blocking WindowServer with XPC stalls.
user-invocable: false
allowed-tools: Bash(uname *), Bash(ps *), Bash(pgrep *), Bash(uptime *), Bash(awk *), Bash(grep *), Bash(wc *), Bash(ls *), Bash(stat *), Bash(mktemp *), Bash(rm *), Read, Write, Edit, Grep, Glob
created: 2026-05-03
modified: 2026-05-03
reviewed: 2026-05-03
---

# LaunchServices Health (macOS)

## When to Use This Skill

| Use this skill when... | Use something else when... |
|------------------------|----------------------------|
| `launchservicesd` is at sustained high CPU | General process forensics — use `ps`/`top` directly |
| GUI feels sluggish after weeks of uptime | The machine actually hung — see `macos-incident-postmortem` |
| Quantifying LS DB bloat (size, bundle count, claim count) | Checking app launch failures — use `system_profiler SPApplicationsDataType` |
| Deciding whether `lsregister` rebuild is warranted | First-time install setup — use `configure-plugin` |

## Platform Guard

This skill is **macOS-only**. The `lsregister` binary, `launchservicesd` daemon, and the LaunchServices database are Darwin-specific. Refuse to act if `uname -s` is not `Darwin`.

```bash
test "$(uname -s)" = "Darwin" || { echo "macos-plugin: not Darwin, refusing"; exit 1; }
```

## Core Expertise

LaunchServices is the macOS subsystem that maps documents and URL schemes to applications. State is held by `launchservicesd` and persisted to a binary database. Two failure modes matter:

1. **DB bloat** — over months of uptime and app churn (Homebrew updates, Xcode reinstalls, Wine/CrossOver bottle creation, Electron app upgrades), the DB accumulates stale bundle records and duplicate claims. The bigger the DB, the slower `lsregister -dump` runs and the more memory `launchservicesd` holds.
2. **Daemon wedge** — `launchservicesd` can spin at high CPU when a misbehaving process repeatedly registers/unregisters bundles. WindowServer makes synchronous XPC calls into `launchservicesd` for icon and document-handler lookups; a wedged daemon manifests as a frozen GUI.

The diagnostic answer is always: **measure first, rebuild only if warranted**. Rebuild (`lsregister -kill -r ...`) takes minutes, makes every app's "open with" disappear briefly, and rebuilds the DB from scratch — only do it when the metrics justify it.

### Where the bits live

| Path | Purpose |
|------|---------|
| `/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister` | The `lsregister` CLI — not on `$PATH`, must be invoked by absolute path |
| `~/Library/Application Support/com.apple.PersistentURLTranslator/` | Per-user persisted state |
| `/var/folders/*/0/com.apple.LaunchServices*` | LS cache directories (varies by macOS version) |

## Quick Snapshot

The reference script `ls-stats` produces a one-page health snapshot. Install at `~/.local/bin/ls-stats` (mode 0755):

```bash
#!/usr/bin/env bash
# ls-stats: macOS LaunchServices DB + launchservicesd health snapshot
set -euo pipefail

[ "$(uname -s)" = "Darwin" ] || { echo "not Darwin" >&2; exit 1; }

LSREG=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
PID=$(pgrep -x launchservicesd) || { echo "launchservicesd not running" >&2; exit 1; }

DUMP=$(mktemp); trap 'rm -f "$DUMP"' EXIT
"$LSREG" -dump >"$DUMP" 2>/dev/null

echo "=== launchservicesd ==="
ps -o pid,rss,etime,command -p "$PID" | sed 's/^/  /'

echo
echo "=== LaunchServices DB ==="
wc -c <"$DUMP" | awk '{printf "  size:    %d bytes (%.1f MB)\n", $1, $1/1048576}'
printf "  bundles: %d\n" "$(grep -c '^bundle id:' "$DUMP")"
printf "  claims:  %d\n" "$(grep -c '^claim '    "$DUMP")"
printf "  records: %d\n" "$(grep -c '^----'      "$DUMP")"

echo
printf "=== Diagnostic reports ===\n  launchservicesd CPU events: %d\n" \
  "$(ls /Library/Logs/DiagnosticReports/ 2>/dev/null | grep -c launchservicesd)"

echo
echo "=== Uptime ==="
uptime | awk '{print "  " $0}'
```

The script prints four blocks: daemon process state (RSS, etime), DB size and counts, recent CPU diagnostic-report count, and current uptime. All numbers are absolute — interpret them against the baseline thresholds below.

## Interpreting the Snapshot

### launchservicesd RSS

| RSS (KB) | Meaning |
|----------|---------|
| < 50 000 (~50 MB) | Healthy |
| 50 000 – 150 000 | Normal for active use |
| 150 000 – 400 000 | Bloated; consider rebuild |
| > 400 000 (~400 MB) | Pathological; rebuild warranted |

### Daemon `etime` (elapsed time since launch)

`launchservicesd` is launched once per boot and lives until reboot. `etime` close to `uptime` is normal. `etime` significantly less than `uptime` means the daemon was relaunched mid-session — usually after a crash; check Diagnostic Reports.

### DB size

| Size | Meaning |
|------|---------|
| < 5 MB | Normal |
| 5 – 20 MB | Healthy heavy-app workstation |
| 20 – 50 MB | Bloated; rebuild improves things |
| > 50 MB | Pathological |

### Bundle / claim / record counts

There is no absolute threshold — these matter relative to the **expected** number of installed apps. Useful sanity check:

```bash
ls /Applications /Applications/Utilities ~/Applications 2>/dev/null | wc -l
```

If `bundle id:` count is 5x or more above the visible-`.app` count, the DB has stale records.

### Diagnostic-report CPU events

`/Library/Logs/DiagnosticReports/launchservicesd-*.cpu_resource.diag` files indicate the daemon hit a CPU threshold (typically 80% sustained for 90s). Each file is one event. Recent volume:

```bash
find /Library/Logs/DiagnosticReports -name 'launchservicesd*.cpu_resource.diag' -mtime -7 | wc -l
```

| Count (last 7 days) | Meaning |
|---------------------|---------|
| 0 | Normal |
| 1 – 3 | Notable; monitor |
| 4+ | Pattern; likely a misbehaving registrar — investigate |

## Rebuild Procedure

Rebuild **only** when the snapshot shows multiple red flags. The rebuild takes 1–10 minutes depending on app count.

```bash
# Rebuild the LaunchServices database
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
  -kill -r -domain local -domain system -domain user
```

What the flags do:

| Flag | Effect |
|------|--------|
| `-kill` | Reset the existing database first |
| `-r` | Recursively scan for bundles to register |
| `-domain local` | `/Applications` |
| `-domain system` | `/System/Applications`, `/System/Library` |
| `-domain user` | `~/Applications`, `~/Library/Application Support` |

Side effects:

- "Open With" submenus regenerate (a few seconds of "no apps available")
- Default-app preferences are preserved (stored separately)
- The Dock badge and icon caches are NOT affected
- A new `launchservicesd` process is spawned; PID changes

### After rebuild

Re-run `ls-stats` to confirm RSS, DB size, and counts dropped.

## Common Patterns

### Snapshot before/after a rebuild

```bash
ls-stats > /tmp/ls-before.txt
"$LSREG" -kill -r -domain local -domain system -domain user
ls-stats > /tmp/ls-after.txt
diff -u /tmp/ls-before.txt /tmp/ls-after.txt
```

### Track DB growth across boots

Append a snapshot to a logbook on each session:

```bash
{ date -Iseconds; ls-stats; echo "---"; } >> ~/.local/state/launchservices.log
```

Plot or grep over time to see whether DB size is monotonically growing.

### Identify the registrar driving CPU

When `launchservicesd` is hot and you suspect a specific app:

```bash
log stream --predicate 'process == "launchservicesd"' --style syslog | head -200
```

Look for repeated `bundle id` or `path` strings — that's the offender.

### Check for bottle-creation amplification

Wine/CrossOver bottle creation registers hundreds of `.exe`-as-bundle entries. Count them:

```bash
"$LSREG" -dump 2>/dev/null | grep -c -i 'wineprefix\|bottle'
```

A 4-digit answer is the smoking gun.

## Justfile Recipe

```just
[doc('Quantify LaunchServices DB and launchservicesd state (macOS)')]
[macos]
ls-stats:
    @~/.local/bin/ls-stats
```

The `[macos]` attribute (just 1.34+) skips the recipe on non-Darwin. On older just versions, drop the attribute and let the script's `uname -s` check do the gating.

## Agentic Optimizations

| Context | Command |
|---------|---------|
| One-line size | `$LSREG -dump 2>/dev/null \| wc -c \| awk '{printf "%.1f MB\n", $1/1048576}'` |
| RSS only | `ps -o rss= -p "$(pgrep -x launchservicesd)"` |
| Bundle count | `$LSREG -dump 2>/dev/null \| grep -c '^bundle id:'` |
| Recent CPU events | `find /Library/Logs/DiagnosticReports -name 'launchservicesd*.cpu_resource.diag' -mtime -7 \| wc -l` |
| Daemon uptime vs system uptime | `ps -o etime= -p "$(pgrep -x launchservicesd)"; uptime` |

## Quick Reference

### Key paths

| Path | Purpose |
|------|---------|
| `/System/.../Support/lsregister` | The CLI |
| `/Library/Logs/DiagnosticReports/` | CPU and crash diag files |
| `~/Library/Application Support/com.apple.PersistentURLTranslator/` | Per-user state |

### Useful flags

| Flag | Description |
|------|-------------|
| `-dump` | Print the entire DB to stdout |
| `-kill -r -domain ...` | Rebuild |
| `-h` | List all flags (undocumented elsewhere) |
| `-f <bundle>` | Force-register a single bundle |
| `-u <bundle>` | Unregister a bundle |

### Indicator thresholds (rough)

| Metric | Healthy | Bloated | Rebuild |
|--------|---------|---------|---------|
| DB size | < 5 MB | 20–50 MB | > 50 MB |
| Daemon RSS | < 50 MB | 150–400 MB | > 400 MB |
| Bundle count vs visible apps | 1–2x | 3–5x | > 5x |
| CPU diag events / 7 days | 0 | 1–3 | 4+ |

## Error Handling

| Symptom | Cause | Fix |
|---------|-------|-----|
| `lsregister: command not found` | Not on `$PATH` by design | Use the full `/System/.../Support/lsregister` path |
| `lsregister -dump` exits non-zero with stderr | Permissions or DB corruption | Capture stderr separately; rebuild may resolve it |
| `pgrep -x launchservicesd` returns nothing | Daemon crashed and not yet relaunched | Check Diagnostic Reports; force a relaunch with `lsregister -kill -r ...` |
| Rebuild appears to hang | Indexing many app bundles is genuinely slow | Wait — typical 1–10 min depending on app count |
| Sudden RSS jump after Homebrew upgrade | Many bundles re-registered at once | Expected; will settle within minutes |

## Related Skills

- `macos-incident-postmortem` — when LaunchServices CPU caused a GUI hang, parse Diagnostic Reports there
- `kitty-session-persistence` — recover terminal sessions lost when WindowServer wedged on an LS XPC call
