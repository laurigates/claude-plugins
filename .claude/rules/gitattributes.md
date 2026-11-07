---
created: 2026-06-22
modified: 2026-11-07
reviewed: 2026-09-23
paths:
  - "**/.gitattributes"
---
# .gitattributes Conventions

A repo's `.gitattributes` is a path→attribute map git consults for **merge**,
**diff**, **checkout**, and **archive** behavior. This repo uses it for four
things; the reusable cross-repo automation is
[`configure-plugin:configure-gitattributes`](../../configure-plugin/skills/configure-gitattributes/SKILL.md),
and the conflict-resolution side is `scripts/resolve-additive-conflicts.py`.

## The four uses (and what each is safe for)

| Attribute | Effect | Safe for | Never for |
|-----------|--------|----------|-----------|
| `merge=union` | Built-in driver; concatenates both sides' additions, no markers | **Append-only files where every logical entry is exactly one line**, merged only by local git | Code, JSON, multi-line-entry files, anything that gets *edited* not just appended |
| `text=auto eol=lf` | Normalize line endings to LF on commit/checkout | Any repo with shell scripts/hooks (CRLF silently breaks a shebang) | — (safe globally; no-op on an all-LF tree) |
| `linguist-generated` | Collapse in GitHub PR diffs + drop from language stats | Build output, tool-owned files (changelogs, lockfiles, rendered diagrams, compiled prompts) | — (display-only; changes **no** merge behavior, so safe even where `merge=union` is wrong) |
| `merge=<custom>` | Runs a program that merges the file's structure; the command lives in per-clone git config | Tool-rewritten structured files whose conflicts are mechanical: `docs/blueprint/manifest.json` → `merge=blueprint-manifest` ([blueprint-plugin README](../../blueprint-plugin/README.md#manifest-merge-driver-sessionstart)) | Files with no registration path — an unregistered clone silently falls back to the line merge |

## `merge=union` — the one-line-per-entry test

Union merge is correct **only** when both sides add disjoint lines and every
entry is self-contained on one line. It also runs only in local git (see
[GitHub does not honor `merge=union` server-side](#github-does-not-honor-mergeunion-server-side)),
so when parallel PRs routinely append to one file, give each entry its own
file instead, as `docs/regression-ledger/` does since #2947. Apply the test
before marking a file:

- ❌ `docs/regression-ledger.md` — one table row per bug and append-only, so it
  passed the line test and was union-marked until #2947. GitHub ignored the
  mark, and every pair of ledger-appending PRs conflicted there. Now one file
  per entry under `docs/regression-ledger/`, with no driver.
- ❌ `.claude/rules/regression-testing.md` — carried the ledger until #2667; now
  an edited rule, so a stale branch appending there must conflict, not union.
- ❌ `**/CHANGELOG.md` — entries are **multi-line**; union interleaves them
  wrongly. (Also release-please-owned — feature branches never append, so they
  don't conflict anyway.)
- ❌ `marketplace.json`, `.release-please-manifest.json` — JSON; union breaks syntax.
- ❌ Generated/compiled files — a conflict there is resolved by **regenerating**, not interleaving.

For one-line append tables not marked `merge=union`,
`scripts/resolve-additive-conflicts.py` (the deterministic pre-pass in
`auto-resolve-conflicts.yml`) still union-merges them generically — so the
`.gitattributes` allowlist is an optimization (clears the conflict in local
and CI merges), not the only safety net.

**Union also runs on local `git revert` and `git cherry-pick`**, and there it
keeps lines it should drop. Both are three-way merges, so a union-marked file
takes both sides:

- A revert of a commit that appended a row leaves the row in place: the revert
  wants it gone, the current tree has it, and union keeps it.
- Cherry-picking a follow-up commit that *edits* a row onto a branch that already
  has the original keeps both versions side by side.

Observed 2026-11-04 (#3412): reverting three duplicate fixes and cherry-picking a
verifier's follow-up left two stale rows and one duplicate in
`docs/regression-ledger.md` (then still union-marked), with every command
exiting 0. After a revert or
cherry-pick that touches a union-marked file, diff that file against the base
and remove leftovers by hand in the same PR.

## GitHub does not honor `merge=union` server-side

**Empirically confirmed (PR #1759, 2026-06):** GitHub's mergeability check and
the **merge button** do NOT apply `.gitattributes merge=union`. A PR whose only
conflict is a union-marked file will still show `CONFLICTING` / `mergeStateStatus
DIRTY`, even though every *real* git merge (local, rebase, the
`auto-resolve-conflicts.yml` workflow) resolves it cleanly with zero markers.
The driver works everywhere git actually runs the merge — just not in GitHub's
server-side computation.

Fix to make such a PR mergeable: bring the base into the branch **locally**,
where the driver is active, so the base becomes an ancestor and GitHub has
nothing left to merge:

```sh
git fetch origin
git merge --no-ff origin/main      # union driver resolves the marked file here
git push                            # PR flips to MERGEABLE
```

(`--no-ff` because a divergent merge can't fast-forward, and a global
`merge.ff=only` would otherwise abort it.) This also doubles as a live proof the
driver works — the marked file gains both sides' rows with no hand-editing.

The fix is per PR, and a batch pays it again for every PR after the first: on
2026-11-02 three of fourteen PRs merged in sequence each needed a local merge,
a push and a fresh CI wait because of one union-marked ledger (#2947). For a
file that most PRs append to, one file per entry removes the conflict instead.

## `linguist-generated` is the safe default for generated trees

Because it only affects GitHub's display, marking a generated file
`linguist-generated` can never break a merge. Reach for it freely on build
output: compiled prompt trees (`*/generated/**`), rendered diagrams
(`docs/diagrams/*.svg` from committed `.d2` sources), release-please
changelogs/manifests, and lockfiles (`uv.lock`, `bun.lock`).

## Other affordances (lower priority)

`merge=ours` / `-merge` (refuse auto-merge), `linguist-vendored` /
`linguist-language=X` (language-stat / detection overrides), `diff=markdown` /
`diff=python` (better hunk headers), `-diff`/`binary` (treat as binary),
`export-ignore` (exclude from `git archive`). Reach for these only when a
concrete need appears — the three above cover the common cases.

## Authoring checklist

- [ ] `* text=auto eol=lf` (+ explicit `*.sh text eol=lf`) when the repo has shell scripts
- [ ] `merge=union` **only** on one-line-per-entry append-only files (run the test above)
- [ ] `linguist-generated` on build output / tool-owned files (always safe)
- [ ] Comment each non-obvious line with *why* it qualifies
- [ ] Verify a union mark with a sandbox merge (`git merge --no-ff` of two divergent appends → 0 markers, both entries)

## Related

- `configure-plugin:configure-gitattributes` — the reusable skill that audits/writes a repo's `.gitattributes`
- `docs/regression-ledger.md` — why the ledger moved from a union-marked table to one file per entry (#2947)
- `scripts/resolve-additive-conflicts.py` — the deterministic union pre-pass for the conflict workflow
- `.claude/rules/conventional-commits.md` — `chore`/`build` scope for tooling-config commits
