---
name: hf-downloads
description: "Hugging Face model downloads without filling root disk — HF_HOME/xet cache redirection, token/gated-repo auth, staging pattern. Use when downloading HF models, hf download errors, ENOSPC during downloads, or GatedRepoError/401s."
allowed-tools: Bash, Read
created: 2026-07-05
modified: 2026-07-05
reviewed: 2026-07-05
---

# Hugging Face Downloads

Download Hugging Face models to a big disk without filling root, authenticate against gated repos, and verify transfers — the failure modes that make multi-GB `hf download` runs abort or 401.

## When to Use This Skill

| Use this skill when... | Skip it when... |
|------------------------|-----------------|
| Downloading multi-GB HF models (`*.safetensors`, GGUF) to a specific disk | A tiny file where cache size is irrelevant |
| `hf download` fails with `No space left on device` (ENOSPC) mid-transfer | Disk-full recovery in general (use `macos-plugin:macos-disk-usage`) |
| A gated download 401s with `GatedRepoError` even though `hf auth whoami` works | Non-HF downloads (`curl`, `wget`, git-lfs from elsewhere) |
| Deciding where to stage a large download so it doesn't fill root | The tool is not `huggingface_hub` / `hf` |

## The Core Trap: `--local-dir` Does Not Cover Transfer State

`--local-dir` only controls where the **final** file lands. HF still writes intermediate transfer state — the hub manifest and, critically, **xet transfer chunks** — to `~/.cache/huggingface/{hub,xet}` regardless.

```sh
hf download <repo> <file> --local-dir /big/disk/staging
```

The final file lands on `/big/disk/`, but the xet chunks stage under `~/.cache/huggingface/xet/`. Xet is HF's newer transfer protocol: it stages compressed blocks under `~/.cache` while reconstructing the file, and those staged blocks are **roughly file-sized**. On a small root disk the symptom is:

```
OSError: I/O error: IO Error: No space left on device (os error 28)
```

## Fix: `HF_HOME` Is the Umbrella

Setting `HF_HOME` relocates both `HF_HUB_CACHE` (`$HF_HOME/hub`) and `HF_XET_CACHE` (`$HF_HOME/xet`) onto the same disk as the destination:

```sh
HF_HOME=/big/disk/hf-cache hf download <repo> <file> --local-dir /big/disk/staging
```

Persist it for a session by exporting in `.zshrc`, `~/.api_tokens` (mise auto-sources), or a per-project `.envrc` (direnv). On a machine whose root is small:

```sh
export HF_HOME=/mnt/big-disk/hf-cache
```

## Two-Stage Staging Pattern

`hf download` preserves the repo's directory structure under `--local-dir`, which is rarely what you want at the destination. Stage first, then move only the file:

```sh
mkdir -p /big/disk/staging /big/disk/hf-cache
HF_HOME=/big/disk/hf-cache hf download <repo> <path/in/repo> --local-dir /big/disk/staging
mv /big/disk/staging/<path/in/repo> /destination/
rm -rf /big/disk/staging
```

**Never stage on `/tmp`.** `/tmp` is sometimes tmpfs (RAM-backed), and on installs that put `/` on a small SSD it fills root fast. Always stage on a disk you've verified with `df -h`. The Claude Code harness also writes Bash output files to `/tmp/claude-<uid>/`, so a full `/tmp` stops Bash entirely.

## Auth: Token Location Diverges Under `HF_HOME`

`hf auth login` writes the token to the **fixed path** `~/.cache/huggingface/token`. But when `HF_HOME` is set, the SDK and CLI read their token from `$HF_HOME/token` instead. The two paths diverge silently: every gated download under `HF_HOME=…` 401s with `GatedRepoError`, even though `hf auth whoami` works fine (it reads `~/.cache/huggingface/token`).

**Signature of this mismatch:** `model_info()` calls succeed (metadata is public), `LICENSE.md` fetches return 200, but `*.safetensors` fetches under the same auth return 401.

Two fixes — prefer `HF_TOKEN` for ephemeral shells, copy the file for persistent setups:

```sh
# Ephemeral: HF_TOKEN is read directly, bypassing the file-location lookup
export HF_HOME=/big/disk/hf-cache
export HF_TOKEN="$(cat ~/.cache/huggingface/token)"

# Persistent: copy the token into the HF_HOME location after login
cp ~/.cache/huggingface/token "$HF_HOME/token"
```

## Gated Repos: Three Independent Conditions

All three must be true to download a gated file:

1. The HF **account** has clicked "Agree and access repository" on the repo's web page.
2. The **token** in use belongs to that same account.
3. The token was **issued after** (or refreshed after) the access was granted. Some HF setups cache permissions at issue time, so a pre-existing token may not pick up newly-granted gated access.

Diagnostic page: <https://huggingface.co/settings/gated-repos> lists every gated repo the **logged-in account** has touched, with status (`Accepted` / `Pending` / `Rejected`). If the repo isn't listed, the "Agree" click landed on the wrong account. `gated: auto` in the API just means the gate auto-approves on click — it does **not** mean the gate is approved for **you**.

**`api.model_info(<gated-repo>)` is not a reliable access probe** — it returns metadata regardless of whether the token can download the actual files. To check real download access, HEAD the file URL with the token (see REFERENCE.md for the script). If the gating page shows `Accepted` but the HEAD returns 401/403, the token is stale: regenerate at <https://huggingface.co/settings/tokens>, `hf auth login` with the new token, and copy it to `$HF_HOME/token` if `HF_HOME` is set.

## Pre-Download Size Check

For very large files, HEAD-check the download URL before committing (see REFERENCE.md for the script). Then confirm the destination disk's free space is at least **2× that** (staging + final), or **1×** if `HF_HOME` is on the destination disk itself.

## Background Downloads

Multi-GB downloads should run via Bash `run_in_background: true`. The harness notifies on completion — do not poll. After completion, move staged files into place, remove the staging dir, and **verify sizes** against the HEAD-reported `Content-Length`:

```sh
stat -c '%s' /destination/<file>
```

`hf download` exiting with code 1 **while the `.safetensors` files are on disk at full size** usually means the **post-download cache cleanup** ran out of root disk, not that the transfer failed. Verify file sizes before re-downloading.

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Redirect all cache to the big disk | `HF_HOME=/big/disk/hf-cache hf download <repo> <file> --local-dir /big/disk/staging` |
| Bypass token-location lookup | `export HF_TOKEN="$(cat ~/.cache/huggingface/token)"` |
| Verify final size vs Content-Length | `stat -c '%s' /destination/<file>` |
| Confirm staging disk has room | `df -h /big/disk` |

For the gated-access HEAD probe and the pre-download size-check scripts, see [REFERENCE.md](REFERENCE.md).

## Related

- `macos-plugin:macos-disk-usage` — general disk-full forensics and space recovery
