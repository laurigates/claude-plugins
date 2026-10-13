# macOS Disk Usage — Error Handling

Symptom table for [SKILL.md](../SKILL.md).

## Error Handling

| Symptom | Cause | Fix |
|---------|-------|-----|
| `df` shows 99% but space "missing" | APFS per-volume `Capacity %` on the sealed snapshot volume | Read `Avail`, or `diskutil apfs list` |
| `du` total ≪ used space | Purgeable local snapshots | `tmutil listlocalsnapshots /`; thin them |
| Deleted a big tree, `df` barely moved | CoW clones — blocks were shared, `du` billed them per copy | Expected for `.venv`/`node_modules`; measure a `df` delta, and prune the global cache to free the shared blocks |
| `uv cache clean` / `uv cache prune` waits on the cache lock and retrying never helps | Both take an exclusive lock; every `uvx` / `uv run` / `uv tool run` process holds a shared lock for its whole lifetime (intended: [astral-sh/uv#19317](https://github.com/astral-sh/uv/issues/19317)). A long-lived stdio MCP server launched via `uvx` therefore blocks the purge for as long as its client session runs | Stop the `uvx`-launched processes (quit the MCP clients), then rerun. Without that, use the narrower `uv cache clean --force <pkg>` from the `--force` row — not `prune --force` |
| Considering `--force` to get past the lock | `uv cache prune --force` deletes every cached environment (`environments-v2/`), including the ones running `uvx` processes execute from | Do not force `prune` while tools run. `uv cache clean --force <pkg>` is narrower: it removes only `wheels-v6/pypi/<pkg>` plus archives left unreferenced, and leaves the environments alone (uv 0.12.21, `Cache::remove()` in `crates/uv-cache/src/lib.rs`; a running `uvx` tool survived force-cleaning all of its own packages) |
| Docker image still huge after prune | Reclaim ran inside VM; host image not yet shrunk | OrbStack auto-shrinks shortly; Docker Desktop needs manual reclaim |
| `volume prune` wiped a database | Named volume pruned while no container ran | Restore from backup; only prune anonymous-hash volumes |
