---
name: kernel-source-history
description: "Kernel source at a tag: diff functions across releases and for-next. Use when citing kernel line numbers or checking a path changed upstream."
allowed-tools: Bash, Read, Grep, Glob
created: 2026-11-02
modified: 2026-11-02
reviewed: 2026-11-02
---

# Kernel Source History

Answer "what does the kernel do here, and is it still true on current mainline?"
with source fetched at named tags, not from memory and not from a local
checkout of unknown age. Every line number you cite is pinned to a tag.

## When to Use This Skill

| Use this skill when... | Use something else when... |
|---|---|
| Quoting kernel functions or line numbers in a report | Searching mailing-list discussion: `/kernel:lore-search` |
| Checking whether a code path changed after the kernel you traced | Diagnosing where threads block: `code-quality-plugin:debugging-methodology` |
| Finding the first release that contains a commit | Patching vendored or forked code: `git-plugin:git-upstream-fix-check` |

## 1. Fetch Files at a Tag

The `plain/` endpoint on git.kernel.org serves one file at one ref, with no
clone and no bot check:

```bash
B=https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/plain
curl -fsSL "$B/fs/xfs/xfs_reflink.c?h=v7.0" -o xfs_reflink.c-v7.0
```

- **Mainline tags** live in torvalds/linux. A subsystem's development tree is the
  `T:` line of its MAINTAINERS entry; XFS's `for-next` is
  `https://git.kernel.org/pub/scm/fs/xfs/xfs-linux.git/plain/<path>?h=for-next`.
- **Read MAINTAINERS at the same tag**:
  `curl -fsSL "$B/MAINTAINERS?h=v7.4-rc1" | awk '/^XFS FILESYSTEM$/,/^$/'`.
- **`-f` is load-bearing.** git.kernel.org returns intermittent 503s; without
  `-f` the error page lands in the file and every later grep "finds nothing".
- **Control-test each download** before concluding a function is absent or
  unchanged: grep for a function you know the file contains. An empty grep on a
  failed fetch reads exactly like "removed upstream".

## 2. Compare a Function Across Versions

Kernel style puts the function name at column 0 on its own line, so an `awk`
range extracts one body:

```bash
for v in v7.0 v7.2 v7.3 v7.4-rc1; do
  printf '%s ' "$v"
  awk '/^xfs_reflink_find_shared\(/,/^}/' "xfs_reflink.c-$v" | md5
done
```

Equal hashes mean the body is byte-identical. When they differ, `diff` the
extracted bodies, not the whole files: most churn in a release is elsewhere.
Check every function on the path you care about (a traced stack is the list),
because the locking can move into a callee while the caller stays identical.

## 3. Which Release First Contains a Commit

`gh api repos/torvalds/linux/compare/<tag>...<sha> --jq .status` on the GitHub
mirror:

| `status` | Meaning |
|---|---|
| `behind` or `identical` | The commit is in `<tag>` |
| `ahead` or `diverged` | It is **not** in `<tag>` |

`diverged` is the trap: it means the commit sits on a branch the tag does not
contain (a subsystem tree merged later). Counting it as contained mislabels
first-release versions. Commit lists per path:
`gh api 'repos/torvalds/linux/commits?path=fs/xfs/xfs_buf.c&since=2026-04-12T00:00:00Z' --paginate --jq '.[] | "\(.sha[0:12]) \(.commit.message | split("\n")[0])"'`.

## 4. Pin, Vendor, and Label What You Cite

- **Cite `file:line` with the tag**, and repeat the line numbers for the newest
  tag when the report claims the code is unchanged.
- **Vendor the exact file you read** into the investigation repo, suffixed with
  its tag (`xfs_reflink.c-v7.0`), so line references stay checkable after
  upstream moves. Kernel source is GPL-2.0; say so in the file list.
- **Distribution kernels are not tags.** `7.0.0-1014-gcp` is Ubuntu's build of
  7.0 with its own patches; `7.2.12` is a stable point release, not the `v7.2`
  tag. Compare against the tag and state the gap.

## 5. Stack Frames Drift Between Versions

The same wait can show different frames on different kernels, so quote a stack
with its kernel version and arch:

- Refactors move callers: on 7.0 the AGF lock is reached through
  `xfs_buf_get_map → xfs_buf_lookup → xfs_buf_find_lock`; from 7.3
  `xfs_buf_read_map` calls `xfs_buf_find_lock` directly. Same lock, different
  frames.
- The compiler renames and inlines: `xfs_buf_lookup.constprop.0`, or the frame
  missing entirely on another build.
- Syscall entry differs by arch: `__x64_sys_ioctl` vs `__arm64_sys_ioctl`.

> Observed 2026-11 (XFS FIEMAP contention): diffing the stack's functions at
> v7.0, v7.2, v7.3, v7.4-rc1 and xfs `for-next` showed the locking path
> unchanged while the buffer cache was restructured around it twice (v7.1,
> v7.3), so the report could claim "unchanged through v7.4-rc1" with line
> numbers and still warn that 7.3+ stacks look different.

## Agentic Optimizations

| Context | Command |
|---|---|
| One file at a tag | `curl -fsSL "$B/<path>?h=<tag>" -o <file>-<tag>` |
| Function identical across tags? | `awk '/^<fn>\(/,/^}/' <file> \| md5` per tag |
| Commit in a release? | `gh api repos/torvalds/linux/compare/<tag>...<sha> --jq .status` |
| Subject of a commit | `gh api repos/torvalds/linux/commits/<sha> --jq '.commit.message \| split("\n")[0]'` |
| Find a commit by subject | `gh api 'search/commits?q=repo:torvalds/linux+"<subject words>"' --jq '.items[].sha'` |
