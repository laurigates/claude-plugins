# project-distill Reference

## Update Over Add Decision Table

| Question | If yes... |
|----------|-----------|
| Does this replace an existing rule/recipe/skill? | Remove the old one, add the new |
| Does this improve an existing one? | Update in place |
| Does an existing one already cover this? | Skip it |
| Is this genuinely new and reusable? | Add it |
| Is this reusable **beyond this repo** / would other repos benefit? | `[PROMOTE]` it to the owning plugin (PR), don't bury it in one repo's `.claude/` |
| Is this a one-off that won't be needed again? | Skip it |

## Evaluation Criteria

### Rules Worth Capturing

| Capture when... | Skip when... |
|-----------------|--------------|
| Pattern applies across sessions | One-time fix |
| Convention that prevents mistakes | Obvious best practice |
| Project-specific constraint discovered | Generic advice |
| Tool behavior that's non-obvious | Well-documented behavior |

### Recipes Worth Capturing

| Capture when... | Skip when... |
|-----------------|--------------|
| Command was run 3+ times with same flags | One-off command |
| Multi-step workflow that should be atomic | Single simple command |
| Flags that are hard to remember | Common well-known flags |
| Project-specific pipeline step | Standard `just` template recipe |

### Skill Improvements Worth Proposing

| Propose when... | Skip when... |
|-----------------|--------------|
| Discovered better command flags | Minor style preference |
| Found a pattern the skill doesn't cover | Edge case unlikely to recur |
| Existing guidance was misleading | Niche use case |
| New tool version changed behavior | Temporary workaround |

### Promotion Candidates ([PROMOTE] — additive, cross-repo)

These do not require anything to have gone wrong; a smooth session is a valid
source. Distinct from "Skill Improvements" because the target is a **named
plugin in another repo**, applied as a PR.

| Promote when... | Skip when... |
|-----------------|--------------|
| Session invented a reusable technique with **no home skill** anywhere | Pattern is specific to this repo -> local `[NEW]` rule instead |
| A **named plugin's skill is missing** a capability the session needed | The skill already covers it (just under-discovered) -> no change |
| The same technique would help **other repos**, not just this one | One-off, won't recur -> skip |
| A focusing fix: "this belongs in `<plugin>/skills/<skill>`" | You can't identify a plausible owner and it isn't clearly reusable |

## Proposal Format Examples

```
[UPDATE] `.claude/rules/X.md` - Reason for update (description of change)
[SKIP] Considered rule Y, but Z already covers it
[UPDATE] `plugin/skills/skill-name/SKILL.md` - Pattern discovered
[NEW] Genuinely new and reusable artifact (only if justified)
[UPDATE] `recipe-name` - Better flags discovered (before/after)
[REDUNDANT] `old-recipe` - Superseded by new approach
[PROMOTE] -> rust-plugin/skills/cargo-worktree-builds (new) - shared CARGO_TARGET_DIR across worktree agents; reusable beyond this repo, no home skill -> PR
[PROMOTE] -> git-plugin/skills/git-pr (edit) - stacked-PR --onto squash cleanup the skill is missing -> PR
```
