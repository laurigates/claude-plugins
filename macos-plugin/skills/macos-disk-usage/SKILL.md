---
name: macos-disk-usage
description: macOS disk-usage forensics and space recovery on APFS. Use when df reports a disk near-full, hunting what's eating space, reclaiming OrbStack/Docker, or pruning caches and local snapshots.
user-invocable: false
allowed-tools: Bash(bash *), Bash(uname *), Bash(df *), Bash(du *), Bash(find *), Bash(diskutil *), Bash(tmutil *), Bash(docker *), Bash(brew *), Bash(go *), Bash(pip *), Bash(uv *), Bash(dust *), Bash(dua *), Bash(gdu *), Bash(ncdu *), Bash(mise *), Read, Grep, Glob, TodoWrite
created: 2026-06-21
modified: 2026-07-18
reviewed: 2026-07-18
---

# macOS Disk Usage & Space Recovery

## When to Use This Skill

| Use this skill when... | Use something else when... |
|------------------------|----------------------------|
| `df` reports a volume near-full and you need the honest figure | The root disk on Linux is full — use the Linux-focused `disk-full-recovery` rule |
| Hunting "what's eating my disk" on macOS | General process forensics — use `ps`/`top` directly |
| Reclaiming space from OrbStack/Docker, caches, or local snapshots | A GUI hang/freeze occurred — see `macos-incident-postmortem` |
| `du` totals and free space disagree (purgeable snapshot space) | `launchservicesd` DB bloat specifically — see `launchservices-health` |

## Platform Guard

This skill is **macOS-only**. APFS containers, `diskutil apfs`, `tmutil` local snapshots, and BSD `du` block-counting are Darwin-specific. Refuse to act if `uname -s` is not `Darwin`.

```bash
test "$(uname -s)" = "Darwin" || { echo "macos-plugin: not Darwin, refusing"; exit 1; }
```

This skill **cross-references, does not duplicate**, the Linux-focused `disk-full-recovery` rule (root partition, `~/.cache`, apt/journalctl). The APFS / Time Machine / OrbStack angle below is the macOS-specific complement.

## Core Expertise

The single most-important macOS fact: **APFS shares free space across every volume in a container.** A per-volume `Capacity %` is therefore misleading — the sealed system snapshot volume routinely reads **99%** while the container has tens of GB free. Trust the `Avail` column (or `diskutil apfs list`), never the `Capacity %`, or the investigation goes down the wrong path before it starts.

The second fact: **`du` lies about reclaimable space.** `tmutil` local snapshots hold purgeable space that `du` never counts, so `du` totals and reported free space can disagree by tens of GB. Check snapshots first when the numbers don't reconcile.

## Step 1: Measure honestly (built-in CLI)

```bash
# Trust Avail, NOT Capacity % — APFS shares free space container-wide
df -h /

# The container's real free space, per-volume roles, and snapshot count
diskutil apfs list

# Top-level consumers, one level deep, staying on one filesystem (-x)
du -hx -d1 / 2>/dev/null | sort -h
du -hx -d1 ~ 2>/dev/null | sort -h
```

BSD `du` counts **allocated blocks**, so it reports the real on-disk size of sparse files (e.g. OrbStack's `data.img.raw` reads its true 33 GB, not its apparent size). Trust the number.

### Purgeable snapshot space (the thing `du` hides)

When `du` totals and `df` free space disagree, local Time Machine snapshots are the usual cause:

```bash
# List local snapshots holding purgeable space
tmutil listlocalsnapshots /

# Thin them (reclaims purgeable space invisible to du); needs sudo
sudo tmutil thinlocalsnapshots / 999999999999 4
```

## Step 1.5: Fast-path — the usual-suspects scan

Step 1 gives the honest *total*; this gives *where it went* without re-deriving the hunt by hand each time. `scripts/scan-suspects.sh` reads a public catalog of known reclaim targets (`scripts/suspects.tsv` — dev caches, build-artifact dirs, VM images), `du`s the ones that exist on this machine, and emits a ranked rollup with the **cleanup command and safety tier already attached**:

```bash
# Whole home (thorough; slower — du walks every tree)
bash "${CLAUDE_SKILL_DIR}/scripts/scan-suspects.sh" --home-dir "$HOME" --root "$HOME"

# Bound the build-artifact search to where projects live, raise the noise floor
bash "${CLAUDE_SKILL_DIR}/scripts/scan-suspects.sh" --root ~/repos --min-mb 1000
```

Output follows the structured `SUSPECT id=… tier=… size_kb=… cmd="…"` convention, plus a ranked human table and per-tier totals (`TIER_SAFE_KB=…`, `RECLAIMABLE_SAFE=…`). Work the tiers exactly as Step 4 — exhaust `safe` before `decision`, never blind-delete `userdata`.

**This augments Step 1, it does not replace it.** The scan is pure measurement; the judgment stays with the agent — reading the APFS `Avail`-not-`Capacity %` picture, checking purgeable snapshots when `du` and `df` disagree, and deciding *which* `decision`/`userdata` items to actually remove.

**The `UNKNOWN` lines are the feedback loop.** Any big directory *not* in the catalog is surfaced as `UNKNOWN size_kb=… path=…`. When one recurs, add it to `suspects.tsv` **as a pattern** (never a machine-specific path — this repo is public) and open a PR; the catalog grows from real findings. Catalog columns and placeholders (`{dir}`, `{parent}`) are documented in the file's header.

Two operational notes:

- **Runtime scales with disk size** — `du` walks every tree, so a full disk can take a minute or two. Bound with `--root <project-dir>` and `--min-mb`; swap in `dust` (Step 3) if you want the walk parallelised.
- **The catalog is the shared artifact; the scan *output* is machine-specific** — keep it in scratch, never commit it.

## Step 2: The OrbStack / Docker recovery play

OrbStack/Docker is frequently the dominant consumer (100+ GB seen). The VM image (`data.img.raw`) grows but **never shrinks on its own**. The recovery is: prune **inside** the VM, then OrbStack **auto-shrinks** the host image (unlike Docker Desktop, which needs manual reclaim).

```bash
# See what's reclaimable before pruning
docker system df

# Prune unused images + build cache (NOT volumes — see warning below)
docker system prune -a -f
```

A real session reclaimed **85 GB** this way (159 images / 57 GB reclaimable, 42 GB build cache), after which OrbStack auto-shrank the host image **103 GB → 33 GB**.

### Never blind-prune named volumes

`docker volume ls -f dangling=true` lists named volumes (`olmap_postgres_data`, `docker_neo4j_data`, …) that are "unused" **only because no container is currently running** — they hold live project databases. A blind `docker volume prune` would wipe them.

```bash
# Inspect first — named volumes are project data, anonymous-hash ones are scratch
docker volume ls -f dangling=true
```

Prune **only anonymous-hash volumes** (long hex names), never the human-named ones, and only after confirming with the user.

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

## Step 4: Tiered cleanup

Work top-down — exhaust the safe tier before touching anything that needs a decision.

| Tier | What | How | Notes |
|------|------|-----|-------|
| **Safe / regenerable** | Homebrew downloads | `brew cleanup -s` | Rebuilds on next install |
| | Go module cache | `go clean -modcache` | Re-downloads on next build |
| | pip cache | `pip cache purge` | |
| | uv cache | `uv cache clean` | **Fails with a lock error** if another uv process / active session is running |
| | Playwright / Yarn / node-gyp caches | `rm -rf ~/Library/Caches/{ms-playwright,Yarn,node-gyp}` | Regenerable |
| **Needs a decision** | Docker images + build cache | `docker system prune -a -f` | OrbStack auto-shrinks host image after |
| | Local Time Machine snapshots | `sudo tmutil thinlocalsnapshots /` | Loses local restore points |
| **User data** | Named Docker volumes | confirm each | Live project databases — never blind-prune |
| | Anything in `~/Documents`, `~/Downloads` | user confirms | Irreplaceable |

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

## Error Handling

| Symptom | Cause | Fix |
|---------|-------|-----|
| `df` shows 99% but space "missing" | APFS per-volume `Capacity %` on the sealed snapshot volume | Read `Avail`, or `diskutil apfs list` |
| `du` total ≪ used space | Purgeable local snapshots | `tmutil listlocalsnapshots /`; thin them |
| `uv cache clean` lock error | Another uv process / active session running | Close other uv work and retry |
| Docker image still huge after prune | Reclaim ran inside VM; host image not yet shrunk | OrbStack auto-shrinks shortly; Docker Desktop needs manual reclaim |
| `volume prune` wiped a database | Named volume pruned while no container ran | Restore from backup; only prune anonymous-hash volumes |

## Related Skills

- `launchservices-health` — when `launchservicesd` DB bloat (not disk usage) is the concern
- `macos-incident-postmortem` — when a freeze/panic, not a full disk, is the symptom
- `disk-full-recovery` (user-global rule) — the Linux-focused complement to this APFS-specific skill
