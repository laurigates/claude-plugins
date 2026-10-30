# Linux Plugin

Linux workstation operations for Claude Code. The first skill finds what fills a Linux disk and recovers the space, from the root partition through secondary data drives that hold model stores and generated output.

```
claude plugin install linux-plugin@laurigates-claude-plugins
```

## Skills

| Skill | Description |
|-------|-------------|
| `linux-plugin:linux-disk-usage` | Measure every filesystem, rank the usual suspects (dev caches, build dirs, self-hosted runner workspaces, swap, journal) with a cleanup command and safety tier attached, clean by tier, and archive-verify-delete bulky data onto a drive with room |

The macOS counterpart is `macos-plugin:macos-disk-usage`. Both skills use the same scanner, `scripts/scan-suspects.sh`, with a different catalog (`scripts/suspects.tsv`). Plugins cannot share files, so the scanner is copied; a fix to it must be ported to both.

## Prerequisites

- GNU coreutils and findutils (`du`, `find -printf`).
- [`dust`](https://github.com/bootandy/dust) is optional. The skill runs it with `mise exec aqua:bootandy/dust@latest`, so nothing has to be installed globally.

## Tests

`skills/linux-disk-usage/scripts/tests/test-scan-suspects.sh` runs the scanner against a fixture home it creates itself, so it never measures the real machine. Catalog rows with absolute paths (`/swapfile`, `/var/log/journal`) are left out of the fixture scan for that reason. The test is run by `just test-skill-scripts`.
