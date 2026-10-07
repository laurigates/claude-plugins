# meta-context-diet — Anti-Patterns and Notes

Moved verbatim from [SKILL.md](../SKILL.md). Open before finalising a disposition,
or when deciding between this skill and `session-distill` / `meta-promote`.

## Anti-patterns to avoid

| Don't | Do |
|---|---|
| Promote a hard invariant to a skill because it "looks like a procedure" | Keep anything whose violation is a bug even when the user never mentions it — a skill only fires on intent |
| Move a rule to a skill with a weak description | The description must auto-trigger on the real intent; if you can't write one ≤150 chars that fires, it is not skill-shaped — lean it or path-scope it instead |
| Bundle a **destructive** disposition (Drop / Consolidate-that-deletes / Promote-to-skill) into a batch approval | Per-candidate `AskUserQuestion` for anything lossy; batch only the non-destructive tier (Keep / Lean / Path-scope) on a large surface |
| Delete the rule entirely after promotion when something still references it | Leave a one-line pointer stub; `grep -rn` the old rule name first |
| Edit the chezmoi *target* (`~/.claude/...`) directly | Edit the chezmoi source (`chezmoi source-path`), then apply |
| Commit the diet as part of the skill | Leave a clean working tree; the user commits per concern |

## Notes

- **Reads broad, writes narrow** — discovery scans the whole always-loaded surface; the write phase touches only approved files.
- **Inverse** of `session-distill` (*creates* rules from sessions), orthogonal to `meta-promote` (moves config *between scopes*). The three compose: distill captures learnings as rules, the diet promotes the intent-shaped ones to skills, `meta-promote` lifts shared ones up a scope.
- Cost model: `skill-quality.md` (listing budget, `skillListingBudgetFraction`) and `skill-development.md` (path-scoped rule frontmatter, description front-loading).
