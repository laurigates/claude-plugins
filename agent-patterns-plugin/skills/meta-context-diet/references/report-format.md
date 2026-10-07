# meta-context-diet — Report Format

Moved verbatim from [SKILL.md](../SKILL.md) (Step 6). Open when writing the final
report.

### 6. Report

Emit a final table and the net context saving:

| Unit | Size (tok) | Disposition | Target | Always-loaded delta |
|---|---|---|---|---|
| `.claude/rules/foo.md` | ~1,200 | Promote to skill | `someplugin:foo-workflow` | −1,200 |
| `CLAUDE.md` § Bar | ~300 | Keep but lean | linked `docs/bar.md` | −260 |
| `.claude/rules/baz.md` | ~400 | Path-scope | `paths: "**/*.py"` | conditional |

End with: total tokens removed from the every-turn surface, the new skills created (with their trigger descriptions), and the next step (review `git status`, commit per concern with conventional-commit messages — this skill does **not** commit).
