---
name: endpoint-security-cpu
description: macOS EndpointSecurity/EDR high CPU & battery drain. Use when Kandji ESF / XProtect pegs a core; trace the exec storm via powermetrics + eslogger.
user-invocable: false
allowed-tools: Bash(uname *), Bash(ps *), Bash(pgrep *), Bash(uptime *), Bash(systemextensionsctl list*), Bash(sudo powermetrics *), Bash(sudo eslogger *), Bash(sudo killall *), Read, Grep, Glob
created: 2026-06-03
modified: 2026-06-03
reviewed: 2026-06-03
---

# EndpointSecurity / EDR CPU (macOS)

## When to Use This Skill

| Use this skill when... | Use something else when... |
|------------------------|----------------------------|
| A security extension (Kandji ESF, XProtect, an EDR) sits at sustained high CPU | `launchservicesd` is the hot process — use `launchservices-health` |
| Battery drains fast and `powermetrics` blames the security stack | The machine actually hung or panicked — use `macos-incident-postmortem` |
| `syspolicyd`/`trustd`/`tccd`/`auditd` are *all* elevated together | One ordinary app is hot — use `ps`/`top` directly |
| You suspect a process-spawn (exec) storm is taxing the system | Auditing kernel-extension *inventory* — `systemextensionsctl list` alone |

## Platform Guard

**macOS-only.** EndpointSecurity, `eslogger` (macOS 13+), `powermetrics`, and `systemextensionsctl` are Darwin-specific.

```bash
test "$(uname -s)" = "Darwin" || { echo "macos-plugin: not Darwin, refusing"; exit 1; }
```

## Core Insight: the EDR is usually a symptom, not the disease

An EndpointSecurity (ES) client — Kandji's ESF extension, XProtect's behavioral service, a corporate EDR — subscribes to the kernel's `exec`/`open`/`rename` event stream. Its CPU is **proportional to the system-wide rate of those events**. When something spawns hundreds of short-lived processes per second, *every* behavioral/security monitor must inspect each one, so they light up **together**:

```
XprotectService      behavioral malware scan, per exec
syspolicyd           Gatekeeper code-signing assessment, per binary
io.kandji…ESF        corporate EDR, per exec/open
trustd / tccd        cert eval / privacy, per access
auditd               audit record, per event
kernel_task          servicing the syscall + interrupt load
```

That column lighting up at once is the signature: **one exec storm, taxing the whole stack.** Restarting the EDR clears its queue for a few seconds, then the storm refills it. The fix is upstream — find and stop whatever is spawning the processes.

A hot ES extension with **near-zero wakeups** confirms this: it is draining a real inbound event queue in user space, not timer-spinning. High CPU *with* a high wakeup count and a quiet `eslogger` points instead at an internally wedged extension — the one case where restarting it (below) actually helps.

## Diagnose

Both probes need root. If `sudo` isn't cached, hand them to the user with the `!` prefix.

**1. Per-process energy + wakeups — who is taxed, and is it spawn churn?**

```bash
sudo powermetrics --samplers tasks --show-process-energy -n 1 | head -45
```

Read three things:
- **`DEAD_TASKS`** high (CPU + deadlines + wakeups) = a storm of processes that spawned and exited *within the sample* — the exec churn made visible.
- The **security-stack cluster** (XprotectService, syspolicyd, the ESF extension, trustd, tccd, auditd) all elevated together = the one-storm-taxes-all signature.
- The **Wakeups** column. Energy Impact *understates* VMs and wakeup-heavy tasks; a process with a huge wakeup count (e.g. a container VM) keeps the CPU package out of deep idle — the real battery cost on an otherwise "low energy" line.

**2. The EndpointSecurity firehose — name the generator.**

`eslogger` subscribes to the *same* stream the EDR consumes, and reports the initiating process. Rank the offenders over a short sample:

```bash
sudo eslogger exec 2>/dev/null | head -400 | jq -r '.process.executable.path' | sort | uniq -c | sort -rn | head -15
```

Whatever path dominates is the storm's source. If the stream scrolls instantly to 400 lines, the event rate itself is the problem. If it only trickles while the ESF stays hot, the extension is wedged internally — restart it.

## Common exec-storm generators

Recurring sources, with the upstream fix that removes the load (not the symptom):

| Generator (fingerprint in `eslogger`) | Fix |
|---|---|
| `uvx --from git+https://…` MCP / tools re-resolving the git source on every launch | Install once (`uv tool install git+…`) and invoke the bare command |
| `brew` invoked in a loop (`portable-ruby` + Homebrew `bash` + `git`) — often a menubar "outdated" poller or per-invocation auto-update | `export HOMEBREW_NO_AUTO_UPDATE=1`; throttle/remove the caller |
| Many concurrent dev/AI sessions spawning short-lived `git`/`node`/`bun`/`gh` | Collapse duplicate sessions; dedupe per-session helper servers |
| A status tool shelling out on a tight timer | Lengthen its interval or cache its result |

## No-reboot levers

macOS rewards not rebooting — both the EDR and the inventory are inspectable and (mostly) restartable live.

- **Restart a wedged ES extension** (only if `eslogger` trickled while it stayed hot): `sudo killall -9 <ESF-process-name>`. `sysextd` relaunches the `[activated enabled]` extension within seconds. No reboot, no logout.
- **Inventory + stale-version backlog:** `systemextensionsctl list`. Over long uptime, each EDR update leaves the prior version as `[terminated waiting to uninstall on reboot]`. Those are **terminated — zero CPU** — pure disk/registry cruft that only a reboot clears, and **never** the performance problem. Don't reboot *for them*.
- **Managed Macs:** Kandji/JAMF EDR extensions can't be removed on a managed device. If the extension stays hot after the generators are gone *and* a reboot, escalate to IT — a persistently-hot EDR is a known agent failure mode they fix centrally.

## Agentic Optimizations

| Context | Command |
|---------|---------|
| ESF extension CPU now | `ps -Ao pcpu,comm \| grep -i ESF-Extension` |
| Storm source (top initiators) | `sudo eslogger exec 2>/dev/null \| head -400 \| jq -r '.process.executable.path' \| sort \| uniq -c \| sort -rn \| head` |
| Security-stack energy snapshot | `sudo powermetrics --samplers tasks --show-process-energy -n 1 \| head -45` |
| Stale sysext versions (reboot-gated cruft) | `systemextensionsctl list \| grep -c 'waiting to uninstall'` |
| Restart wedged ESF (sysextd relaunches) | `sudo killall -9 <esf-process-name>` |

## Quick Reference

| Tool | Role | Root? |
|------|------|-------|
| `powermetrics --samplers tasks` | Per-process energy, wakeups, `DEAD_TASKS` churn | yes |
| `eslogger exec open rename` | The ES event stream the EDR consumes; names the initiator | yes (macOS 13+) |
| `systemextensionsctl list` | Extension inventory + reboot-gated stale versions | no |
| `ps -Ao pcpu,comm` | Instantaneous CPU per process | no |

## Related Skills

- `launchservices-health` — when `launchservicesd` (not an ES extension) is the hot process
- `macos-incident-postmortem` — when the load caused an actual hang/panic; reconstruct from DiagnosticReports
