# project-distill Reference

## Update Over Add Decision Table

| Question | If yes... |
|----------|-----------|
| Does this replace an existing rule/recipe/skill? | Remove the old one, add the new |
| Does this improve an existing one? | Update in place |
| Does an existing one already cover this? | Skip it |
| Is this genuinely new and reusable? | Add it |
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

## Proposal Format Examples

```
[UPDATE] `.claude/rules/X.md` - Reason for update (description of change)
[SKIP] Considered rule Y, but Z already covers it
[UPDATE] `plugin/skills/skill-name/SKILL.md` - Pattern discovered
[NEW] Genuinely new and reusable artifact (only if justified)
[UPDATE] `recipe-name` - Better flags discovered (before/after)
[REDUNDANT] `old-recipe` - Superseded by new approach
```
