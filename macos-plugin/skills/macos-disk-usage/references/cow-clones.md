# macOS Disk Usage — CoW Clones

Detail for the third Core Expertise fact in [SKILL.md](../SKILL.md): why `du` over-counts copy-on-write clones, and how to measure what a delete actually frees.

### CoW clones: `du` over-counts what deleting would free

A copy-on-write clone (`cp -c`, `clonefile(2)`) shares blocks with its source, so it costs ~nothing — but every tool reading `st_blocks` bills it at full size. Measured on a 200 MB file plus one clone (**ground truth: 200 MB**):

| Tool | Reports |
|------|---------|
| BSD `du`, GNU `du`, `dust`, `gdu` | 400M |
| `dust -s` (apparent) | 600M — also counts hardlinks |
| **`df` delta** | **0 MB for the clone** ✅ |

All of them dedupe *hardlinks* by inode; a clone has a **distinct inode**, so that logic never fires.

This is not academic — it is the default on this platform for two common package managers:

| Tool | Global cache | 2nd project's copy costs | `du` claims |
|------|--------------|--------------------------|-------------|
| `uv` → `.venv` | `~/.cache/uv` | **0 bytes** (clonefile) | full size |
| `bun` → `node_modules` | `~/.bun/install/cache` | **0 bytes** (clonefile) | full size |
| `cargo` → `target/` | `~/.cargo/registry` (sources only) | **full size** — each project compiles its own copy | accurate |

So `du` is honest for `target/` and inflated for `node_modules`/`.venv`. **Deleting a clone frees real space only where it holds the last reference to those blocks.**

**When a size gates a decision ("how much will this free?"), measure a `df` delta — it is the only clone-aware measurement available:**

```bash
before=$(df -k / | awk 'NR==2{print $4}'); rm -rf <target>; sync
echo "freed $(( ($(df -k / | awk 'NR==2{print $4}') - before) / 1048576 )) GB"
```

Real cost of skipping this: a reclaim sweep summing `du` predicted **68.7 GB** where the `df` delta was **17.7 GB** — a 4× overstatement (2026-08). Clones *are* detectable via `fcntl(F_LOG2PHYS_EXT)` — a clone shares physical device offsets while having a distinct inode, and `stat`/`MetadataExt` carries no clone signal at all — but no general-purpose tool implements it yet ([bootandy/dust#590](https://github.com/bootandy/dust/issues/590)).
