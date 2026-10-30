# Archive, Verify, Then Delete

Read from Step 4 of [SKILL.md](../SKILL.md) before deleting data the user wants kept elsewhere, or a directory that may hold the only copy of some work.

## Copy in the background

```bash
mkdir -p <dest-parent> && rsync -a --info=stats1 <src> <dest-parent>/
```

Run it as a background task: 100+ GB onto a spinning disk takes tens of minutes (about 48 MB/s measured onto an NTFS HDD). Note the trailing-slash rule: `<src>` without a slash creates `<dest-parent>/<basename>`.

## Verify before deleting the source

Exit 0 from rsync is not enough. Compare file counts and bytes, then ask rsync what it would still change:

```bash
for d in <src> <dest>; do find "$d" -type f -printf '%s\n' | awk -v d="$d" '{n++; s+=$1} END {print d, n, s}'; done
rsync -a --dry-run --itemize-changes <src>/ <dest>/ | awk '{print $1}' | sort | uniq -c
```

How to read the itemize flags:

| Flags | Meaning | Delete source? |
|-------|---------|----------------|
| Nothing listed | Identical, metadata included | Yes |
| Only `p` and `g` (e.g. `.f...p.g...`) | Permissions and group differ; size, time and content match | Yes, if the destination is NTFS/exFAT (`findmnt` shows `fuseblk`), which cannot store them. Tell the user that executables need `chmod +x` after a restore |
| `s` or `t`, or `>f` lines | Size, mtime or content differs, or the file was not copied | No, re-run the copy and check again |

Counts and bytes matching while rsync lists thousands of `p`/`g` lines is the normal result onto NTFS, not a failed copy.

## Before deleting a git checkout

Run `git-plugin:git-repo-delete-check`. Two cases came up in practice:

- **The branch looks unpushed but was squash-merged.** `git log --branches --not --remotes` lists commits whose content already reached `main` through a squash merge, because the merge changed their ids. `gh pr list --state all --head <branch> --json number,state` returning `MERGED` settles it (`git-plugin:git-merge-hazards`).
- **Uncommitted work.** Commit it on a dated branch and push before deleting:

  ```bash
  git -C <repo> switch -c backup/<branch>-<YYYY-MM-DD>
  git -C <repo> add <paths>
  git -C <repo> commit -m "chore: preserve WIP before deleting local checkout"
  git -C <repo> push -u origin backup/<branch>-<YYYY-MM-DD>
  ```

Also check for gitignored files that hold real state, such as `.env` with credentials or a local database, and for a systemd unit that points into the directory (`systemctl list-unit-files | grep <name>`).

A directory that is not a git repository has no remote. Archive it before deleting it unless the user says it is disposable.
