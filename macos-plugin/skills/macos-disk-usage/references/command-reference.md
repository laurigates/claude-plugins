# macOS Disk Usage — Command Reference

One-line commands for the steps in [SKILL.md](../SKILL.md).

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Ranked usual-suspects rollup | `bash "${CLAUDE_SKILL_DIR}/scripts/scan-suspects.sh" --root ~/repos` |
| Honest free space | `df -h / \| awk 'NR==2{print $4" avail"}'` |
| Container free space | `diskutil apfs list \| grep -i 'Capacity In Use\|Free'` |
| Top home consumers | `du -hx -d1 ~ 2>/dev/null \| sort -h \| tail -15` |
| Snapshot count | `tmutil listlocalsnapshots / \| grep -c com.apple` |
| Docker reclaimable | `docker system df` |
| Fast tree (dust) | `dust -d2 -r ~` |
| Machine-readable sizes (dust) | `dust -j -o b -d1 <dir> \| jq -r '.children[] \| [(.size \| rtrimstr("B") \| tonumber), .name] \| @tsv' \| sort -rn` — `-j` emits a `{size, name, children}` tree to stdout; `-o b` makes sizes bytes (`"12345B"`) instead of human strings |

## Quick Reference

| Need | Command |
|------|---------|
| Fast-path suspect scan | `bash "${CLAUDE_SKILL_DIR}/scripts/scan-suspects.sh"` |
| Honest free space | `df -h /` (read `Avail`, not `Capacity %`) |
| APFS container truth | `diskutil apfs list` |
| Disk hog scan | `du -hx -d1 <dir>` or `dust -d2 -r <dir>` |
| Purgeable snapshots | `tmutil listlocalsnapshots /` |
| Thin snapshots | `sudo tmutil thinlocalsnapshots / 999999999999 4` |
| Docker reclaim | `docker system df` then `docker system prune -a -f` |
