# macOS Disk Usage — Third-Party Tooling

Step 3 of [SKILL.md](../SKILL.md).

## Step 3: Third-party tooling

Install via the mise `aqua:` backend (checksum-verified standalone binaries):

```bash
mise use -g aqua:bootandy/dust   # `dust` — fast tree-map, the one to lead with
mise use -g aqua:Byron/dua-cli   # `dua`  — interactive TUI via `dua i`
```

| Tool | Install | Strength |
|------|---------|----------|
| `dust` | `aqua:bootandy/dust` | Fast visual tree; lead with this. `dust -r` reverse, `-d N` depth, `-X <glob>` exclude, `-s` apparent size, `-j` JSON to stdout |
| `dua` | `aqua:Byron/dua-cli` | Interactive deletion TUI (`dua i`) |
| `gdu` / `ncdu` | `aqua:dundee/gdu`, `ncdu` | TUI disk usage analyzers |
| `diskonaut` | `aqua:imsnif/diskonaut` | Spatial treemap navigator |

GUI options (mention, don't install): **DaisyDisk**, **GrandPerspective**, **OmniDiskSweeper**.
