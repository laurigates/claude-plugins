---
name: git-merge-driver
description: Write a custom git merge driver that merges a file's structure instead of its lines. Use when a tool-rewritten JSON/YAML/lock file keeps conflicting on mechanical fields.
allowed-tools: Bash, Read, Write, Edit, Grep, Glob, TodoWrite
created: 2026-11-03
modified: 2026-11-04
reviewed: 2026-11-03
---

# Custom Git Merge Drivers

A merge driver is a program git runs to merge one file in place of its
line-by-line merge. Git hands it the ancestor, our side and their side; it
writes the result and reports whether the merge was clean. It is the right tool
when a file conflicts on changes that carry no real disagreement: a timestamp
two tool runs both rewrote, a counter, registry entries each branch added at
the same spot.

## When to Use This Skill

| Use this skill when... | Use something else when... |
|---|---|
| A tool-rewritten structured file (JSON/YAML manifest, registry, generated index) conflicts on every parallel branch | The file is append-only with one entry per line → built-in `merge=union` (`configure-plugin:configure-gitattributes`) |
| The conflicts are mechanical: timestamps, counters, disjoint additions | A conflict is in front of you right now → resolve it; a driver only helps the next merge |
| You can state, field by field, what the right merge is | The file is regenerated from sources → regenerate it after merging instead |

Try the built-ins first. `merge=union` keeps both sides' lines with no
markers, `merge=binary` (or `-merge`) refuses to merge and keeps ours. A custom
driver is a program you now maintain, and it is the only option when the
correct merge depends on the file's structure.

## How git calls a driver

A driver has two halves, and only one of them is committed:

| Half | Where | Committed? |
|---|---|---|
| Which files use it | `.gitattributes`: `path/to/file.json merge=my-driver` | yes |
| What it runs | git config: `merge.my-driver.driver = <command>` | **no** |

```
git config merge.my-driver.name   "structural merge for file.json"
git config merge.my-driver.driver "python3 tools/merge.py %O %A %B %P"
```

| Placeholder | Meaning |
|---|---|
| `%O` | temp file: common ancestor (empty when both sides added the file) |
| `%A` | temp file: our side; **write the merged result here** |
| `%B` | temp file: their side |
| `%P` | the path being merged (for messages) |
| `%L` | conflict-marker size |
| `%S` `%X` `%Y` | conflict labels for ancestor, ours, theirs |

The contract (`man gitattributes`, "Defining a custom merge driver"):

| Exit code | Git's reading |
|---|---|
| `0` | clean; `%A` is the result |
| `1`–`128` | conflict; `%A`, whatever is in it, becomes the conflicted file |
| `> 128` | the driver crashed; the whole merge **fails** instead of conflicting |

`merge.<name>.recursive` names the driver for the internal merge of several
merge bases; unset, the same driver runs there too.

Git runs drivers wherever it performs the merge itself: `git merge`, `rebase`,
`cherry-pick`, `revert` and `stash pop`/`apply`. GitHub's server-side
mergeability check and merge button do **not**, so a PR whose only conflict a
driver would resolve still shows as conflicting. Merge the base into the branch
locally and push (`.claude/rules/gitattributes.md` in claude-plugins records
this for `merge=union`; custom drivers behave the same).

## Design rules for a structural driver

1. **Merge three ways, recursively.** For each key: equal on both sides, take
   it; changed on one side only, take that change; added on one side, keep it;
   deleted on one side and untouched on the other, drop it. This alone resolves
   most "both branches touched the file" conflicts.
2. **Write field policies only for fields you can justify.** "The later of two
   timestamps", "the larger of two counters", "the union of two lists that both
   only appended". Every policy is a claim that the field carries no real
   disagreement. Make it only where that is true.
3. **Keep related fields together.** When fields describe one event (a run's
   time, result and stats), take all of them from one side. Merged field by
   field, the file can claim a time from one run and a result from the other.
4. **Everything else is a conflict.** Two branches giving one id to two
   different records is exactly what a merge must surface. A driver that
   "resolves" it has hidden a bug.
5. **On conflict, write git's own markers.** Run
   `git merge-file -L ours -L base -L theirs %A %O %B` into `%A` and exit
   non-zero. The user then sees an ordinary conflict, not a half-merged file.
   If the line merge happens to come out clean, check that the result still
   parses before exiting 0.
6. **Never exit above 128.** Clamp the exit code. Git reads a crash code as
   "abort the merge", which is worse than a conflict.
7. **Fall back on unparseable input.** If any side does not parse, line-merge
   as in rule 5 instead of raising.
8. **Preserve formatting byte for byte.** Write the output with the same
   serializer settings the tool uses (indent, key order, trailing newline,
   non-ASCII escaping). Verify by round-tripping the committed file: parse and
   re-serialize must produce identical bytes, or every merge adds a diff.
9. **Know which interpreter git will run.** A bare `python3` in the driver
   command resolves through the PATH git inherits at merge time, which can
   differ from your shell's. A terminal with mise or Homebrew gets that
   Python; a git GUI launched from Finder, or another bare `/usr/bin:/bin`
   environment, gets the macOS Xcode `python3` (3.9). Either support the
   oldest one that can be reached, or check the version at startup and exit 1
   with a message, so the merge falls back to a normal conflict.

A minimal Python skeleton with the exit-code contract, the `git merge-file` fallback and the parse check in place: [REFERENCE.md § Minimal driver skeleton](REFERENCE.md#minimal-driver-skeleton).

A production example with run-state grouping, timestamp and counter policies,
and the test layers in [Testing it](#testing-it) is blueprint-plugin's manifest driver
(`merge-manifest.py`, documented in the blueprint-plugin README under
"Manifest Merge Driver").

## Registering it in every clone

The config half is never committed, and a clone without it falls back to the
line merge **silently**: the attribute names a driver git cannot find, so git
uses the default. Pick a registration path deliberately:

| Option | How | Trade-off |
|---|---|---|
| Setup recipe | `just setup` runs the two `git config` lines | Explicit; forgotten on a fresh clone |
| Committed include | Commit `.gitconfig-drivers`; each clone runs `git config --local include.path ../.gitconfig-drivers` once | Driver edits ship with the repo; still one manual step |
| SessionStart hook | A Claude Code plugin hook writes the config when `.gitattributes` declares the driver | Automatic for agent sessions; plain-git users still need a setup step |

`include.path` resolves relative to the config file holding it, so `../` from
`.git/config` is the repo root. Linked worktrees share the main repo's config,
so register once per clone, not per worktree.

When the driver lives at a path that can move (a plugin cache directory that
changes on every update), make the registered command fall back when the
script is gone, so a stale path conflicts instead of crashing:

```
f='/path/to/merge.py'; if [ -f "$f" ]; then python3 "$f" %O %A %B %P; else git merge-file -L ours -L base -L theirs %A %O %B; fi
```

Git runs the command through the shell, so this works as the `driver` value.
Re-register whenever the path changes.

Confirm the wiring:

```
git check-attr merge -- path/to/file.json   # -> merge: my-driver
git config --get merge.my-driver.driver     # -> the command
```

## Testing it

A driver is unproven until a real git merge runs through it. Test three layers:

| Layer | What to assert |
|---|---|
| Direct calls | Fixture `base`/`ours`/`theirs` files: each field policy, one-sided changes, disjoint additions, a real collision exits 1–128 with `<<<<<<<` in `%A`, unparseable input falls back |
| Real git, with a control | In a `mktemp -d` repo: two branches edit the file, `git merge` is clean with the driver registered. The **same merge with the driver unregistered must conflict**, or the fixture never exercised the driver |
| The path that bit you | If the motivating conflict came from `git stash pop` or a rebase, reproduce that command too |

Then break the driver on purpose. Remove one policy, or make the final
conflict rule return `ours`, and confirm the matching test fails. Restore from
a `cp` snapshot. A suite that stays green under those mutations is not testing
the driver.

Sandbox hygiene: `export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1`,
unset the inherited `GIT_DIR` family, and guard the `mktemp -d` result before
any `git -C`.

## Related

- `configure-plugin:configure-gitattributes`: the built-in attributes (`union`, `linguist-generated`, `eol`)
- `git-plugin:git-merge-hazards`: GitHub's merge machinery, including what the server-side merge ignores
- `git-plugin:git-local-hazards`: local git results that look right and aren't
