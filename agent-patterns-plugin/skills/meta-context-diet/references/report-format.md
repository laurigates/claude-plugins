# meta-context-diet — Report Format

Moved verbatim from [SKILL.md](../SKILL.md) (Steps 5 and 6). Open when applying
the commit policy at Step 5, or when writing the final report.

### Commit policy

After every write, run `git status` so the user sees exactly what changed before any commit. **Defer to the user's or project's commit policy:**

| Commit policy | Action |
|---|---|
| Says to commit (a user `decision-defaults.md` commit section, a project `CLAUDE.md` git-workflow rule) | Commit **per concern** — path-scoping, leaning, each promotion, each consolidation or drop as its own commit — with a conventional-commit message. Stage explicit paths only (`git add <paths>`, never `git add -A`), then `git commit`. |
| Silent, or says not to commit | Leave the tree uncommitted so the user can review it and split it per concern. |

A commit policy never replaces the per-candidate confirmation for lossy edits — commit only what the user approved.

### 6. Report

Emit a final table and the net context saving:

| Unit | Size (tok) | Disposition | Target | Always-loaded delta |
|---|---|---|---|---|
| `.claude/rules/foo.md` | ~1,200 | Promote to skill | `someplugin:foo-workflow` | −1,200 |
| `CLAUDE.md` § Bar | ~300 | Keep but lean | linked `docs/bar.md` | −260 |
| `.claude/rules/baz.md` | ~400 | Path-scope | `paths: "**/*.py"` | conditional |

End with: total tokens removed from the every-turn surface, the new skills created (with their trigger descriptions), and the commit outcome: the per-concern commits made when the user's or project's commit policy says to commit, or — when it does not — the next step (review `git status`, commit per concern with conventional-commit messages).
