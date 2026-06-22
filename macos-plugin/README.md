# macos-plugin

macOS-specific operational tooling for the dev-environment concerns that don't fit cleanly into cross-platform plugins: recovering from GUI freezes, diagnosing macOS-specific instability, and long-uptime hygiene.

All skills are **Darwin-only** — they detect non-macOS systems and refuse to act.

## Skills

| Skill | Description |
|-------|-------------|
| [kitty-session-persistence](skills/kitty-session-persistence/skill.md) | Snapshot and restore kitty terminal sessions across crashes and reboots via `kitten @ ls` and a LaunchAgent |
| [launchservices-health](skills/launchservices-health/skill.md) | Quantify the LaunchServices DB, `launchservicesd` RSS/uptime, and surface the safe rebuild command |
| [macos-incident-postmortem](skills/macos-incident-postmortem/skill.md) | Reconstruct what happened from `/Library/Logs/DiagnosticReports/`, `kern.boottime`, and shell history after a hang or panic |
| [endpoint-security-cpu](skills/endpoint-security-cpu/skill.md) | Diagnose an EndpointSecurity/EDR extension (Kandji ESF, XProtect) hot from a process-spawn storm; trace the source with `powermetrics` + `eslogger` |
| [macos-disk-usage](skills/macos-disk-usage/skill.md) | Disk-usage forensics and space recovery on APFS — trust `df` `Avail` not `Capacity %`, reclaim OrbStack/Docker, thin `tmutil` snapshots, tiered cache cleanup |

## When to Use

| Scenario | Skill |
|----------|-------|
| Terminal sessions vanished after a hard reboot or kitty crash | `kitty-session-persistence` |
| `launchservicesd` is pegged at high CPU; LS DB feels bloated | `launchservices-health` |
| GUI froze and you're not sure if the machine actually rebooted | `macos-incident-postmortem` |
| Investigating recent kernel panics, watchdog timeouts, jetsam events | `macos-incident-postmortem` |
| A security extension (Kandji ESF, XProtect, an EDR) is pegged at high CPU; battery drains | `endpoint-security-cpu` |
| A disk reads near-full, or you're hunting what's eating space / reclaiming OrbStack-Docker | `macos-disk-usage` |
| `syspolicyd`/`trustd`/`tccd`/`auditd` are all elevated together — an exec storm | `endpoint-security-cpu` |
| Auditing whether the machine is "due for a reboot" after weeks of uptime | `macos-incident-postmortem` + `launchservices-health` |

## Scope

- **macOS-only** — every skill checks `uname -s` and refuses on non-Darwin systems.
- **Runtime diagnostics, not initial setup** — overlaps with `configure-plugin` are intentional gaps; that plugin is for project setup, this is for recovery and observability.
- **OS health, not Claude Code health** — `health-plugin` covers Claude Code config; this covers the host operating system.

## Origin

Created in response to a real 2026-04-22 incident: a 33-day uptime plus repeated `wineserver` crashes pushed `launchservicesd` to sustained 85% CPU, blocking WindowServer's main thread on a LaunchServices XPC call. The GUI froze, kitty was killed, all open Claude Code sessions terminated mid-write. Recovery required reconstructing what was open from `~/.claude/projects/*/*.jsonl` mtimes and ad-hoc `lsregister -dump` analysis. The skills here turn that ad-hoc recovery into repeatable workflows.

See [issue #1108](https://github.com/laurigates/claude-plugins/issues/1108) for the original proposal.

## Future Skills

These are deliberately out of scope for the initial release; track in follow-up issues if needed:

- `pmset-analysis` — sleep/wake assertion attribution
- `mdworker-diagnostics` — Spotlight indexing health
- `homebrew-services-audit` — long-running brew services hygiene
- `mac-kernel-extension-status` — `kmutil` / `systemextensionsctl` summaries
