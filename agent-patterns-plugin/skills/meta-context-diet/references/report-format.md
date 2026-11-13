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
same always-loaded files Step 1 measured, after the edits. `wc -c` counts bytes,
not characters: an em-dash or an arrow is 3 bytes, so tokens ≈ bytes/4 runs
slightly high on text that uses them. A deleted file counts as 0, and text moved
into a skill, a `REFERENCE.md` or a `docs/` file leaves the every-turn surface,
so it does not count. A rule that this diet gave a `paths:` glob is still on
disk at the same size, so a re-run of the same glob would show it saving
nothing. Leave it out of the after-sum and report its bytes as conditional, as
the Path-scope row in the table does. The measured net is the Step 1 total minus
the new total. Name the command beside the figure, with the files it summed
(`wc -c CLAUDE.md .claude/rules/a.md .claude/rules/b.md`, before and after), so
the number can be checked. Where the Step 4 estimate and the measured net
disagree, report both.

In one 2026-11 diet the approval table summed to about 8K, and the diff removed
6,162 bytes and added 2,483 (each count includes one diff-marker byte per
line), a net of about 3.7K. The gap has two parts: about 1.8K of the approved
size was never deleted, and the 2,483 added bytes were residual pointer and
invariant text that the estimate did not subtract.

End with: the measured net tokens removed from the every-turn surface and the command that measured it, the new skills created (with their trigger descriptions), and the commit outcome: the per-concern commits made when the user's or project's commit policy says to commit, or — when it does not — the next step (review `git status`, commit per concern with conventional-commit messages).
