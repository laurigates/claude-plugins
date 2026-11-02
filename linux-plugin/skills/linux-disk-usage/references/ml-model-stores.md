# ML Model Stores and Generated Output

Read from Step 3 of [SKILL.md](../SKILL.md) before deleting anything under a model directory, a Hugging Face or torch cache, or a generation output tree.

## Hugging Face cache

`HF_HOME` is often relocated to a data drive and linked back (`~/.cache/huggingface -> <drive>/hf-cache`). The directory holds more than downloads:

| Entry | What it is | Clear? |
|-------|-----------|--------|
| `hub/`, `xet/` | Downloaded repos and the Xet chunk store | Yes; re-downloaded on demand |
| `modules/` | Dynamic `trust_remote_code` modules | Yes |
| `token`, `stored_tokens` | Login credentials | **Keep**; deleting them logs the user out |

To remove one model rather than all, use `hf cache rm <repo-id> -y` after `hf cache ls --sort size`. For relocating the cache, see `tools-plugin:hf-downloads`.

## Check what points into a cache before wiping it

A model folder or venv can be a symlink into a cache, and wiping the cache breaks it. Look first:

```bash
find <model-dir> <venv-dirs> -xdev -type l \( -lname '*hf-cache*' -o -lname '*uv-cache*' -o -lname '*huggingface*' \)
```

Empty output means the files are real copies, so the cache can go.

## Before deleting a model file, look for workflows that load it

Workflow JSON names model files by their path relative to the model folder. Search the saved workflows and the custom nodes:

```bash
grep -rlF '<model-filename>' <comfyui>/user <comfyui>/custom_nodes --include='*.json' --include='*.py'
```

A model with no hits is safe to remove from the workflows' point of view. Two copies of a model in different formats are a typical case: a sharded Hugging Face folder and a single-file conversion of the same weights. Usually only one of them is referenced.

## Finding duplicates

1. Group files over ~500 MB by exact size.
2. For groups of two or more distinct inodes (hardlinks are not duplicates), hash the first 64 MiB of each.
3. **Before acting on a match, confirm it with a full `sha256sum`.** A partial-hash match can be a false positive when files share a zero-filled or constant header. Game `.pak` archives and blockchain `blk*.dat` files both matched this way.

Where duplicates come from: a model copied into `models/` while also sitting in `hf-cache/`, a container image both in the project dir and in the apptainer cache, the same CUDA libraries in several venvs and uv caches. Most of these resolve by clearing the cache side.

**Keep a duplicate's path if anything loads it by path.** When a workflow loads `clip_vision/FramePack/<file>` and an identical copy sits in `clip_vision/`, replace the duplicate with a hardlink. The path survives and the space is freed:

```bash
sha256sum <keep> <dup>          # must match
ln -f <keep> <dup>
stat -c '%h %i %n' <keep> <dup> # link count 2, same inode
```

## Which models are actually used: access time, read carefully

On a `relatime` mount (`findmnt -no OPTIONS -T <dir>`), a file's access time updates when it is read and the stored atime is older than a day, so it approximates "last loaded". It goes wrong in two ways:

- **A full-read sweep resets everything.** A backup, an indexer or a hash scan that read every file leaves them all with the same date. Treat a date shared by nearly every file as the sweep. Only accesses after it are real use: `find <models> -type f -newerat <day-after-sweep>`.
- **Your own duplicate hash scan is a read.** Hashing the first 64 MiB updates atime on every candidate. **List access times before running any hash or duplicate scan**, or the "recently used" list will contain exactly the files you hashed.

Modification time is the download date, not use.

## Removing a model family completely

A family is the model folder plus its custom node. Delete the custom node only when its checkout is an unmodified upstream clone; then it can be reinstalled:

```bash
git -C <custom_nodes>/<node> remote -v
git -C <custom_nodes>/<node> status --porcelain
git -C <custom_nodes>/<node> log --branches --not --remotes --oneline
```

**Before removing a custom node, or a script that belongs to one, search the workspace repo for what depends on it.** A clean upstream clone says the node itself can come back; it says nothing about your own code that needs it:

```bash
git -C <workspace> grep -n '<NodeClass>'          # workflows and scripts that build graphs with the node
git -C <workspace> grep -nE 'import <module>|from <module> import'   # importers of a script you plan to delete
```

The first hit list is what breaks when the node goes. Removing ComfyUI-KittenTTS broke a recipe whose generator script refused to run without the `KittenTTS` node class, and that script turned out to be imported as a library by three other scripts and three tests, so deleting it would have broken those too. Keep a script that has importers. Where it needs the removed node, make it fail with a message naming what was removed.

A running ComfyUI keeps the node loaded until it restarts. Leave past outputs and the core `comfy/ldm/<family>` code alone. The core code belongs to ComfyUI itself.
