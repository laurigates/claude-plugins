# meta-context-diet — Report Format

Detail for [SKILL.md](../SKILL.md) Steps 5 and 6. Open when applying
the commit policy at Step 5, or when writing the final report.

### Commit policy

After every write, run `git status` so the user sees exactly what changed before any commit. **Defer to the user's or project's commit policy:**

| Commit policy | Action |
|---|---|
| Says to commit (a user `decision-defaults.md` commit section, a project `CLAUDE.md` git-workflow rule) | Commit **per concern** — path-scoping, leaning, each promotion, each consolidation or drop as its own commit — with a conventional-commit message. Stage explicit paths only (`git add <paths>`, never `git add -A`), then `git commit`. If on the default branch, create a feature branch first (`git switch -c <type>/context-diet-<topic>`); never commit on main/master. |
| Silent, or says not to commit | Leave the tree uncommitted so the user can review it and split it per concern. |

A commit policy never replaces the per-candidate confirmation for lossy edits — commit only what the user approved.

### 6. Report

Emit a final table and the net context saving:

| Unit | Size (tok) | Disposition | Target | Always-loaded delta |
|---|---|---|---|---|
| `.claude/rules/foo.md` | ~1,200 | Promote to skill | `someplugin:foo-workflow` | −1,140 (pointer stays) |
| `CLAUDE.md` § Bar | ~300 | Keep but lean | linked `docs/bar.md` | −260 |
| `.claude/rules/baz.md` | ~400 | Path-scope | `paths: "**/*.py"` | conditional |

**Report the measured net, not the Step 4 estimate.** Re-run `wc -c` on the
same always-loaded files Step 1 measured, after the edits: a deleted file counts
as 0, and text moved into a skill, a `REFERENCE.md` or a `docs/` file leaves the
every-turn surface, so it does not count. The measured net is the Step 1 total
minus the new total, tokens ≈ chars/4. Name the command beside the figure
(`wc -c CLAUDE.md .claude/rules/*.md`, before and after), so the number can be
checked. Where the Step 4 estimate and the measured net disagree, report both.
In one 2026-11 diet the approval table summed to about 8K chars and the diff
measured about 3.7K net (6,162 removed, 2,483 added), because the residual
pointer and invariant lines were never subtracted.

End with: the measured net tokens removed from the every-turn surface and the command that measured it, the new skills created (with their trigger descriptions), and the commit outcome: the per-concern commits made when the user's or project's commit policy says to commit, or — when it does not — the next step (review `git status`, commit per concern with conventional-commit messages).
