---
name: linux-disk-usage
description: Linux disk-usage forensics and space recovery. Use when a Linux disk is near-full, finding what eats space, or clearing caches, build dirs and model stores.
user-invocable: false
allowed-tools: Bash, Read, Grep, Glob, TodoWrite
created: 2026-10-30
modified: 2026-10-30
reviewed: 2026-10-30
---

# Linux Disk Usage & Space Recovery

## When to Use This Skill

| Use this skill when... | Use something else when... |
|------------------------|----------------------------|
| `df` reports a Linux filesystem near-full | The machine is a Mac — `macos-plugin:macos-disk-usage` (APFS, snapshots, OrbStack) |
| Hunting what is eating root or a data drive | Downloading Hugging Face models without filling root — `tools-plugin:hf-downloads` |
| Clearing dev caches, build dirs, CI-runner workspaces, model stores | Deleting a whole git checkout — run `git-plugin:git-repo-delete-check` first |
| Moving bulky data to another drive before deleting it | |

## Platform Guard

```bash
test "$(uname -s)" = "Linux" || { echo "linux-plugin: not Linux, refusing"; exit 1; }
```

## Core Facts

1. **Look at every mount before deciding anything.** Root is often full while a data drive has terabytes free; that turns "delete" into "move". `df -h` alone hides unmounted and secondary disks.
2. **`du` over-counts reflinked copies on XFS and btrfs.** uv installs into a `.venv` by cloning from its cache when the filesystem supports reflinks (an installed file shows `shared` in `filefrag -v`; `xfs_info /` shows `reflink=1`). `du`, `dust` and the scanner bill each clone at full size, so a `.venv` delete frees less than reported. Cargo `target/` dirs are real per-project copies and free what they show. When a size gates a decision, measure a `df` delta (`macos-plugin:macos-disk-usage` covers the same effect for APFS clones).
3. **A cache relocated by symlink is measured as the link.** `~/.cache/huggingface -> /mnt/data/hf-cache` reads as a few bytes under `du`; the bytes are on the other drive. Scan the target, and clean it with the tool's `--cache-dir` (uv) or by path.

## Step 1: Measure every filesystem

```bash
df -h -x tmpfs -x devtmpfs -x squashfs
lsblk -o NAME,SIZE,FSTYPE,MOUNTPOINT
findmnt -no FSTYPE,OPTIONS -T <path>      # reflink-capable? relatime? NTFS (fuseblk)?
swapon --show                              # a swapfile beside zram is a candidate
```

Then the tree. `dust` is the fast lead; run it through `mise exec` so it writes nothing to the global mise config:

```bash
mise exec aqua:bootandy/dust@latest -- dust -x -d 1 -n 20 -b -P /
mise exec aqua:bootandy/dust@latest -- dust -x -d 2 -n 30 -b -P <largest-dir>
```

`-x` stays on one filesystem, so each mount is scanned on its own. Reading `/var` or other users' homes without root under-reports them; say so rather than presenting the figure as complete.

## Step 1.5: The usual-suspects scan

`scripts/scan-suspects.sh` reads `scripts/suspects.tsv` (Linux caches, build dirs, runner workspaces, swap, journal), measures what exists here, and prints a ranked rollup with the cleanup command and safety tier attached:

```bash
bash "${CLAUDE_SKILL_DIR}/scripts/scan-suspects.sh" --home-dir "$HOME" --root "$HOME" --min-mb 500
bash "${CLAUDE_SKILL_DIR}/scripts/scan-suspects.sh" --root ~/repos --min-mb 1000
```

Output: `SUSPECT id=… tier=… size_kb=… cmd="…"`, a ranked table, `TIER_*_KB=` totals, and `UNKNOWN` lines for big uncatalogued dirs. Rows with absolute targets (`/swapfile`, `/var/log/journal`, the linuxbrew Cellar) read the real host whatever `--home-dir` says. A recurring `UNKNOWN` becomes a catalog row, written as a pattern; this repo is public. The scanner is a copy of the macOS one with a different catalog, so a scanner fix lands in both.

## Step 2: Clean by tier

Exhaust `safe` before `decision`; `userdata` needs the user's explicit yes per item. Commands that turned out incomplete in their obvious form:

| Target | Use | Not just | Why |
|--------|-----|----------|-----|
| Homebrew cache | `brew cleanup --prune=all -s` | `brew cleanup -s` | Plain `-s` left 2.5 GB in `downloads/` |
| npm | `npm cache clean --force` **and** `rm -rf ~/.npm/_npx` | the clean alone | The clean leaves the npx cache (437 MB measured) |
| uv cache on another drive | `uv cache clean --cache-dir <dir>` | `uv cache clean` | The default only clears `~/.cache/uv` |
| Rust build output | `cargo clean` in each project | deleting `target/` by hand | Same result, and it respects a custom `target-dir` |
| mise tool versions | `mise prune --dry-run`, then `mise prune` | deleting install dirs | Prune keeps every version a tracked config asks for |
| Go temp build dirs | `rm -rf $TMPDIR/go-build<digits>` older than an hour | `rm -rf ~/.cache/go-build` | That one is the live cache; use `go clean -cache` |

**Self-hosted GitHub Actions runners.** Each runner keeps `externals.<version>` dirs from before an auto-update, about 590 MB each; delete all but the current version. Clear `_work` only while no job runs (`systemctl list-units 'actions.runner.*'`, then the runner's job state).

**Swapfile beside zram.** When `swapon --show` lists zram at a higher priority and the swapfile's `USED` is near zero, the swapfile is spare capacity for memory spikes. Removing it is the user's call: `swapoff`, drop the fstab line, delete.

## Step 3: Data drives and model stores

Model stores (ComfyUI `models/`, Hugging Face, ollama, torch hub) and generated output are the largest items on a workstation data drive, and the least regenerable. Before deleting anything there, open [references/ml-model-stores.md](references/ml-model-stores.md). It covers keeping HF login tokens while wiping the hub, checking workflows for a model's filename, the duplicate-hunt method and its false positives, hardlinking a duplicate that a workflow loads by path, and reading access times before your own scan resets them.

## Step 4: Archive, verify, then delete

For data the user wants kept but not on this drive, copy to a drive with room, verify the copy, and only then delete. A verification that looks clean can still be wrong, especially onto NTFS. Before deleting a git checkout or project directory, follow [references/archive-and-delete.md](references/archive-and-delete.md).

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Every filesystem at once | `df -h -x tmpfs -x devtmpfs -x squashfs` |
| Ranked suspects | `bash "${CLAUDE_SKILL_DIR}/scripts/scan-suspects.sh" --root ~ --min-mb 500` |
| One-level tree, one filesystem | `mise exec aqua:bootandy/dust@latest -- dust -x -d 1 -b -P <dir>` |
| Machine-readable sizes | `dust -j -o b -d1 <dir>` (JSON tree, sizes in bytes) |
| Journal size, no sudo | `journalctl --disk-usage` |
| Prunable mise versions | `mise prune --dry-run` |
| Reflink check | `filefrag -v <file>` (look for `shared`) |
