# meta-context-diet — Anti-Patterns and Notes

Moved verbatim from [SKILL.md](../SKILL.md). Open before finalising a disposition,
or when deciding between this skill and `session-distill` / `meta-promote`.

## Anti-patterns to avoid

| Don't | Do |
|---|---|
| Promote a hard invariant to a skill because it "looks like a procedure" | Keep anything whose violation is a bug even when the user never mentions it — a skill only fires on intent |
| Move a rule to a skill with a weak description | The description must auto-trigger on the real intent; if you can't write one ≤150 chars that fires, it is not skill-shaped — lean it or path-scope it instead |
| Bundle a **destructive** disposition (Drop / Consolidate-that-deletes / Promote-to-skill / Lean-to-pointer) into a batch approval | Per-candidate `AskUserQuestion` for anything lossy; batch only the non-destructive tier (Keep / Lean / Path-scope) on a large surface |
| Delete, consolidate, or promote a rule after checking only inbound markdown links | Run the [consumer sweep](consumer-sweep.md) at inventory and again before executing — the whole tree for the rule's file name, hidden paths included, `.git` excluded, plus `AGENTS.md`, `.github/copilot-instructions.md`, and anything that globs `.claude/rules`; repoint every hit, or leave a one-line pointer stub |
| Switch an approved disposition because the execute-time sweep found a new consumer | Re-confirm that candidate with a single-candidate `AskUserQuestion`; the user approved a specific action |
| Promote a rule to a skill when an indexer or a non-Claude agent reads rule paths | Move the body to `docs/<topic>.md` and lean the rule to its invariant plus a link (or, confirmed per candidate, to a pointer), so the indexer and `AGENTS.md` readers still reach it |
| Edit the chezmoi *target* (`~/.claude/...`) directly | Edit the chezmoi source (`chezmoi source-path`), then apply |
| Commit against the user's or project's commit policy, or land the whole diet as one commit | Defer to the commit policy: when it says commit, one conventional commit per concern with explicit-path staging; otherwise leave the tree uncommitted for the user to review and split |

## Notes

- **Reads broad, writes narrow** — discovery scans the whole always-loaded surface; the write phase touches only approved files.
- **Inverse** of `session-distill` (*creates* rules from sessions), orthogonal to `meta-promote` (moves config *between scopes*). The three compose: distill captures learnings as rules, the diet promotes the intent-shaped ones to skills, `meta-promote` lifts shared ones up a scope.
- Cost model: `skill-quality.md` (listing budget, `skillListingBudgetFraction`) and `skill-development.md` (path-scoped rule frontmatter, description front-loading).
