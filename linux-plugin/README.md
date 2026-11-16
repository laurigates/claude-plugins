# Linux Plugin

Linux workstation operations for Claude Code: finding what fills a Linux disk and recovering the space, and measuring and diagnosing laptop battery drain while off, suspended or idle.

```
claude plugin install linux-plugin@laurigates-claude-plugins
```

## Skills

| Skill | Description |
|-------|-------------|
| `linux-plugin:linux-disk-usage` | Measure every filesystem, rank the usual suspects (dev caches, build dirs, self-hosted runner workspaces, swap, journal) with a cleanup command and safety tier attached, clean by tier, and archive-verify-delete bulky data onto a drive with room |
| `linux-plugin:linux-battery-drain` | Tell real poweroff from suspend in the journal, rule out running drain (dGPU kept in D0, spinning daemons), and measure off-state and suspend drain from the fuel gauge with tests that log `energy_full`, so a gauge recalibration cannot pass as a result |

The macOS counterpart is `macos-plugin:macos-disk-usage`. Both skills use the same scanner, `scripts/scan-suspects.sh`, with a different catalog (`scripts/suspects.tsv`). Plugins cannot share files, so the scanner is copied; a fix to it must be ported to both.

## Prerequisites

- GNU coreutils and findutils (`du`, `find -printf`).
- [`dust`](https://github.com/bootandy/dust) is optional. The skill runs it with `mise exec aqua:bootandy/dust@latest`, so nothing has to be installed globally.

## Tests

`skills/linux-disk-usage/scripts/tests/test-scan-suspects.sh` runs the scanner against a fixture home it creates itself, so it never measures the real machine. Catalog rows with absolute paths (`/swapfile`, `/var/log/journal`) are left out of the fixture scan for that reason. The test is run by `just test-skill-scripts`.

`skills/linux-battery-drain/scripts/tests/test-drain-calc.sh` checks the drain calculator against rows shaped like real measurements, including a run where the gauge recalibrated mid-test. The off-state and suspend test scripts power the machine down, so they have no automated test.
