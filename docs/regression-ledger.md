# Regression Ledger — Known Regressions (Documented Bugs)

One entry per bug that was fixed together with a regression check, per
[`.claude/rules/regression-testing.md`](../.claude/rules/regression-testing.md).
The rule says **how** to guard a fix; this file records **what** was guarded,
and where.

## Adding an entry

- **Add one new file per fix:** `docs/regression-ledger/<number>-<slug>.md`,
  where `<number>` is the issue or PR the fix closes (`0` when there is none)
  and `<slug>` is a few lowercase, hyphenated words naming the defect. Never
  edit another entry to add yours, and never add a row to this page.
- The file holds **exactly one line**: one table row with the columns below.
  `scripts/check-regression-ledger.sh` rejects anything else.
- Columns: the defect as observed, its root cause and fix, the check that now
  guards it (script + test, and how it was shown red before the fix), and the
  issue or PR.

Entries are separate files because GitHub's server-side merge, which runs
`gh pr update-branch`, the PR mergeability check and "Update branch", ignores
custom merge drivers. Until #2947 this page held the whole table under
`merge=union`, which only local git honours, so every pair of open PRs that
each appended a row conflicted on GitHub. Two PRs now add two different
files and cannot conflict.

## Why this is not a rule file

Until issue #2667 this table lived inside the rule, which is scoped to
`**/skills/**` and `scripts/**`. A path-scoped rule loads whole into any agent
that touches a matching file, so every subagent working on a skill paid for the
entire ledger — 513 KB, roughly 128K tokens, growing ~3.5 KB per merged fix.
That pushed a haiku eval subagent past its context window (HTTP 400 `Prompt is
too long`), and the always-loaded budget in `check-context-engineering.py` could
not see it, because it sums only unscoped rules. The ledger is read on demand
now, and the scanner carries a per-rule size ceiling that applies whatever a
rule's scoping.

## Reading the ledger

The table is rendered from the entry files and is not committed, since a
committed rendering would put every entry back into one shared file:

```bash
bash scripts/render-regression-ledger.sh                 # print the table
bash scripts/render-regression-ledger.sh --output FILE   # write it to a file
```

Entries are ordered by their leading number. To search the ledger without
rendering it, grep `docs/regression-ledger/` directly. The 462 entries that
predate #2947 were split out of this page unchanged; the 48 whose row cites no
issue or PR number carry `0`.

> **Rows are dated records — quotes are preserved as written.** Several rows
> quote user-global rules that `laurigates/dotfiles` #353 later promoted into
> marketplace skills; the rule files survive as pointer stubs at the same
> paths, so every citation still resolves, but the quoted prose now lives in
> the skill. Current homes: `pr-merge-hazards.md` →
> `git-plugin:git-merge-hazards`, `documentation-authoring.md` →
> `documentation-plugin:docs-single-source`, `taskwarrior-tracking.md` →
> `taskwarrior-plugin:task-add` + `session-plugin:session-wrap`,
> `scaffold-fix-backport.md` → `code-quality-plugin:code-scaffold-backport`,
> `repo-deletion-safety.md` → `git-plugin:git-repo-delete-check`,
> `verify-upstream-before-patching.md` → `git-plugin:git-upstream-fix-check`,
> `read-issue-thread-before-contributing.md` → `git-plugin:git-issue-scoping`,
> `verify-machine-facts-before-publishing.md` →
> `documentation-plugin:docs-verify-machine-facts`. One live-scope caveat: the
> `#2268` row states that `check-branch-containment-guidance.sh` rules 1–4
> scan `git-plugin/**/*.md` only "so … `pr-merge-hazards.md` stay[s] free to
> quote the broken forms while TEACHING them". That still holds for the
> **stub**, but `git-plugin/skills/git-merge-hazards/SKILL.md` now teaches the
> same traps from *inside* the scanned corpus and is deliberately **not**
> exempted — it complies instead (see that script's header comment).
