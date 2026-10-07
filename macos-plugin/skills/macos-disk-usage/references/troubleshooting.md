# macOS Disk Usage — Error Handling

Symptom table for [SKILL.md](../SKILL.md).

## Error Handling

| Symptom | Cause | Fix |
|---------|-------|-----|
| `df` shows 99% but space "missing" | APFS per-volume `Capacity %` on the sealed snapshot volume | Read `Avail`, or `diskutil apfs list` |
| `du` total ≪ used space | Purgeable local snapshots | `tmutil listlocalsnapshots /`; thin them |
| Deleted a big tree, `df` barely moved | CoW clones — blocks were shared, `du` billed them per copy | Expected for `.venv`/`node_modules`; measure a `df` delta, and prune the global cache to free the shared blocks |
| `uv cache clean` lock error | Another uv process / active session running | Close other uv work and retry |
| Docker image still huge after prune | Reclaim ran inside VM; host image not yet shrunk | OrbStack auto-shrinks shortly; Docker Desktop needs manual reclaim |
| `volume prune` wiped a database | Named volume pruned while no container ran | Restore from backup; only prune anonymous-hash volumes |
