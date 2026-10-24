---
name: apptainer
description: "Apptainer: run OCI images as rootless batch jobs with --nv GPU passthrough and digest-pinned SIFs. Use when running a CUDA tool without Docker, podman lacks GPU support, or a pull fills root."
allowed-tools: Bash, Read
created: 2026-10-23
modified: 2026-10-24
reviewed: 2026-10-23
---

# Apptainer

Run a container image as one batch command — a CUDA tool that reads files,
writes files and exits — on a Linux host, without a daemon and without root.
Apptainer pulls any OCI/Docker image, converts it to a single read-only `.sif`
file, and runs it **as you**, on the host network, with your home directory
mounted.

## When to Use This Skill

| Use Apptainer when... | Use Docker/Podman/OrbStack instead when... |
|---|---|
| A GPU tool (COLMAP, OpenMVS, a trainer) must run from a pinned image on a Linux box | The container is a long-running service needing port mapping, compose or networks |
| There is no root, or the distro's podman predates CDI GPU support (< 4.1) | You need isolation from the host — Apptainer shares network, PIDs and `$HOME` by default |
| The job is "crunch this directory and exit" | The host is macOS — Apptainer is Linux-only; OrbStack/Docker run there |

Images stay OCI, so the same `@sha256:` image runs under Apptainer on the GPU
box, Docker on a laptop and Kubernetes in CI.

## Install

**Ubuntu / Pop!_OS, maintained path** (apt updates it; needs `sudo` once):

```sh
sudo add-apt-repository -y ppa:apptainer/ppa && sudo apt update && sudo apt install -y apptainer
```

Use the `apptainer-suid` package instead only if you need the setuid variant.
On Ubuntu 24.04+, unprivileged user namespaces are restricted by AppArmor and
must be allowed on the host — see the Apptainer admin guide, *User Namespace
Requirements*.

**No root at all**: the official `install-unprivileged.sh` builds a relocatable
install from EPEL RPMs. It needs `rpm2cpio`, which Debian/Ubuntu lack — see
[REFERENCE.md](REFERENCE.md) for the stand-in and the full command. Check user
namespaces first: `unshare -Ur true && echo ok`.

## The Root-Disk Trap: Cache Under `$HOME`, Temp Under `/tmp`

A pull downloads the OCI layers into `$APPTAINER_CACHEDIR` (default
`~/.apptainer/cache`) and assembles the SIF under `$APPTAINER_TMPDIR` (default
`/tmp`). A 3.4 GB CUDA image therefore needs ~3.4 GB of layers **plus** the
3.2 GB SIF on the root disk unless both are redirected. Point them at the big
disk, persistently, before the first pull:

```sh
export APPTAINER_CACHEDIR=/big/disk/apptainer/cache APPTAINER_TMPDIR=/big/disk/apptainer/tmp
mkdir -p "$APPTAINER_CACHEDIR" "$APPTAINER_TMPDIR"
```

The cache directory must be per-user; do not share one between accounts.

## Pull by Digest Into a Named File

A tag can move; a digest cannot. Resolve the digest once, then pull into a file
named for what it is. Docker Hub's `digest` already carries the `sha256:`
prefix, so it follows the `@` as-is:

```sh
curl -fsSL "https://hub.docker.com/v2/repositories/colmap/colmap/tags?page_size=5&ordering=last_updated" | jq -r '.results[] | "\(.name) \(.digest)"'
apptainer pull /big/disk/images/colmap-20260929.8466.sif docker://colmap/colmap@<digest>
```

`warn rootless{…} ignoring (usually) harmless EPERM on setxattr
"security.capability"` during an unprivileged pull is expected: file
capabilities cannot be set without root, and batch tools do not use them.

## GPU: `--nv`

`--nv` binds the host NVIDIA driver libraries and device nodes into the
container. No nvidia-container-toolkit, no CDI spec. Verify before a long run:

```sh
apptainer exec --nv image.sif nvidia-smi -L
```

The image's CUDA runtime must be supported by the host driver. Read the tool's
own banner too — e.g. `colmap help` prints `with CUDA` for a GPU build.

## Binds: Only Home, the Working Directory and /tmp Appear

By default Apptainer mounts `$HOME`, the current directory and `/tmp` (plus
`/proc`, `/sys`, `/dev`, `/etc/hosts` and `/etc/localtime` — the `mount *` and
`bind path` lines of `apptainer.conf`). Data on any other mount is **absent inside the
container**, and the tool reports a plain "No such file or directory" — it
looks like a wrong path, not a missing bind. Bind data disks explicitly:

```sh
apptainer exec --nv --bind /mnt/data image.sif colmap feature_extractor --image_path /mnt/data/images ...
```

## Not a Sandbox

`exec` runs as your UID with your environment, your network and write access to
everything bound — including `$HOME`. That is what makes it convenient for batch
tools, and why it is no isolation boundary. For a cleaner run, add `--cleanenv`
(drop host environment) and `--containall` (no automatic home/tmp mounts, own
PID/IPC namespaces); then bind exactly what the job needs.

## Scripting It

Wrap the call in a shell **function**, not a string variable:

```bash
colmap() { apptainer exec --nv --bind "$DATA" "$SIF" colmap "$@"; }
colmap feature_extractor --database_path "$W/db.db" --image_path "$IMG"
```

A string such as `C="apptainer exec … colmap"` followed by `$C args` fails in
zsh with exit 127, because zsh does not word-split unquoted parameters (see
`tools-plugin:zsh-gotchas`). This bites over `ssh host '…'` whenever the remote
login shell is zsh. Run multi-line remote scripts as
`ssh host bash -s <<'EOF' … EOF`.

For an overnight job, detach it from the SSH session and log to the data disk:

```sh
setsid nohup bash run.sh </dev/null >/big/disk/run.log 2>&1 &
```

## Agentic Optimizations

| Context | Command |
|---|---|
| GPU visible inside the image | `apptainer exec --nv image.sif nvidia-smi -L` |
| Image size on disk | `ls -lh /big/disk/images/*.sif` |
| Tool options in the pinned version | `apptainer exec image.sif <tool> <subcommand> -h \| grep -E '<flag>'` |
| Cache usage | `du -sh "$APPTAINER_CACHEDIR"` |
| Prune the layer cache | `apptainer cache clean -f` |

## Related

- `tools-plugin:hf-downloads` — the same root-disk trap for Hugging Face caches
- `tools-plugin:zsh-gotchas` — why a command string in a variable fails in zsh
- `configure-plugin:configure-container` — building and publishing the OCI images Apptainer consumes
